import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';
import '../models/file_entry.dart';
import '../models/installed_store.dart';
import '../models/root_context.dart';
import 'app_logger.dart';
import 'dependency_runner.dart';
import 'windows_programs.dart';
import 'shortcut_service.dart';
import 'url_guard.dart';

enum AppStatus { notInstalled, updateAvailable, upToDate, offline }

typedef ProgressCallback = void Function(String message, double total, double file);

class AppInfo {
  final AppStatus status;
  final String? installedVersion;
  final String? availableVersion;
  final int? sizeBytes;

  const AppInfo({required this.status, this.installedVersion, this.availableVersion, this.sizeBytes});
}

class Manifest {
  final RootContext context;
  final String fingerprint;

  const Manifest(this.context, this.fingerprint);
}

class UpdateService {
  final Directory baseDir;
  final InstalledStore store;
  final AppLogger log;
  final ShortcutService? shortcuts;
  final DependencyRunner _deps;
  final WindowsPrograms _programs;
  final http.Client _client;

  UpdateService({
    required this.baseDir,
    required this.store,
    required this.log,
    this.shortcuts,
    DependencyRunner? dependencyRunner,
    WindowsPrograms? programs,
    http.Client? client,
  }) : _deps = dependencyRunner ?? DependencyRunner(),
       _programs = programs ?? WindowsPrograms(),
       _client = client ?? http.Client();

  static String currentOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unsupported';
  }

  static bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Directory installDir(AppEntry app, Variant variant) => Directory('${baseDir.path}/apps/${app.id}/${variant.id}');

  // ── Manifest ───────────────────────────────────────────────────────────────

  Future<Manifest> fetchManifest(String url) async {
    final response = await _client.get(requireSecureUri(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Sunucu yapılandırma için ${response.statusCode} yanıtı döndürdü.');
    }
    final context = RootContext.fromJson(json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
    return Manifest(context, sha256.convert(response.bodyBytes).toString());
  }

  /// Durum + sürüm/boyut bilgisi. Kurulu değilse ve [needManifest] false ise
  /// sunucuya gitmez.
  Future<AppInfo> inspect(AppEntry app, Variant variant, String os, {bool needManifest = false}) async {
    final record = store.get(app.id, variant.id);
    final target = variant.desktop[os];
    if (target?.installer != null) {
      return _inspectInstaller(app, variant, os, target!, needManifest: needManifest);
    }
    if (target == null || (record == null && !needManifest)) {
      return AppInfo(status: AppStatus.notInstalled, installedVersion: record?.version);
    }
    try {
      final manifest = await fetchManifest(target.manifestUrl);
      final osFiles = manifest.context.osFileList.where((f) => f.os == os);
      final size = osFiles.isEmpty ? null : osFiles.first.fileList.fold<int>(0, (a, f) => a + f.fileSize);
      final status = record == null
          ? AppStatus.notInstalled
          : manifest.fingerprint == record.fingerprint
          ? AppStatus.upToDate
          : AppStatus.updateAvailable;
      return AppInfo(
        status: status,
        installedVersion: record?.version,
        availableVersion: manifest.context.version,
        sizeBytes: size,
      );
    } catch (e) {
      log.write('Durum kontrolü başarısız (${app.id}/${variant.id}): $e');
      return AppInfo(
        status: record == null ? AppStatus.notInstalled : AppStatus.offline,
        installedVersion: record?.version,
      );
    }
  }

  /// Kurucuyla kurulan uygulama: kurulu mu ve sürüm, kayıt defterinden okunur.
  Future<AppInfo> _inspectInstaller(
    AppEntry app,
    Variant variant,
    String os,
    DesktopTarget target, {
    required bool needManifest,
  }) async {
    final installer = target.installer!;
    InstalledProgram? program;
    try {
      program = await _programs.find(installer.displayName);
    } catch (e) {
      log.write('Kurulu programlar okunamadı (${app.id}): $e');
    }
    if (program == null && !needManifest) return const AppInfo(status: AppStatus.notInstalled);
    try {
      final manifest = await fetchManifest(target.manifestUrl);
      final osFiles = manifest.context.osFileList.where((f) => f.os == os);
      final size = osFiles.isEmpty ? null : osFiles.first.fileList.fold<int>(0, (a, f) => a + f.fileSize);
      final available = manifest.context.version;
      final record = store.get(app.id, variant.id);
      final status = program == null
          ? AppStatus.notInstalled
          : available != null
          ? (_sameVersion(available, program.version) ? AppStatus.upToDate : AppStatus.updateAvailable)
          : (record == null || record.fingerprint == manifest.fingerprint
                ? AppStatus.upToDate
                : AppStatus.updateAvailable);
      return AppInfo(status: status, installedVersion: program?.version, availableVersion: available, sizeBytes: size);
    } catch (e) {
      log.write('Durum kontrolü başarısız (${app.id}/${variant.id}): $e');
      return AppInfo(
        status: program == null ? AppStatus.notInstalled : AppStatus.offline,
        installedVersion: program?.version,
      );
    }
  }

  /// `v1.2`, `1.2.0` ve `1.2` aynı sayılır (sondaki `.0` parçaları atılır).
  static bool _sameVersion(String a, String? b) {
    if (b == null) return false;
    String norm(String v) => v.trim().replaceFirst(RegExp(r'^[vV]'), '').replaceAll(RegExp(r'(\.0+)+$'), '');
    return norm(a) == norm(b);
  }

  // ── Install / update ───────────────────────────────────────────────────────

  Future<void> install(AppEntry app, Variant variant, String os, ProgressCallback onProgress) async {
    final target = variant.desktop[os];
    if (target == null) {
      throw Exception('${app.name} için $os sürümü bulunamadı.');
    }
    // Bağımlılıklar uygulamadan önce: eksik biri kurulamazsa uygulama kurulmaz.
    for (final dep in app.requires) {
      await _ensureDependency(dep, os, onProgress);
    }

    final dir = installDir(app, variant);
    await dir.create(recursive: true);
    log.write('Kurulum başladı: ${app.id}/${variant.id} → ${dir.path}');
    final installer = target.installer;
    if (installer != null) {
      await _installWithSetup(app, variant, os, target, installer, dir, onProgress);
      return;
    }

    onProgress('Yapılandırma alınıyor...', 0.09, 0);
    final manifest = await fetchManifest(target.manifestUrl);
    await _syncManifest(dir, manifest, os, (msg, total, file) {
      onProgress(msg, 0.10 + 0.85 * total, file);
    });

    // Başarısız bir kurulum "kurulu" sayılmasın diye kayıt en sonda yazılır.
    await store.put(
      app.id,
      variant.id,
      InstalledRecord(fingerprint: manifest.fingerprint, version: manifest.context.version, updatedAt: DateTime.now()),
    );
    await _createShortcut(app, variant, os, dir);
    onProgress('Hazır.', 1.0, 0);
    log.write('Kurulum tamamlandı: ${app.id}/${variant.id}');
  }

  static const _setupSuccess = [0, 1641, 3010];

  /// MSI / Inno kurucusunu indirip sessiz çalıştırır (Windows'ta UAC ile). Üstüne kurarak
  /// güncellenir. Başarıdan sonra kurucu dosyaları silinir.
  Future<void> _installWithSetup(
    AppEntry app,
    Variant variant,
    String os,
    DesktopTarget target,
    InstallerSpec installer,
    Directory dir,
    ProgressCallback onProgress,
  ) async {
    if (os != 'windows') throw Exception('${app.name}: kurucu tipi yalnızca Windows için desteklenir.');
    onProgress('Yapılandırma alınıyor...', 0.09, 0);
    final manifest = await fetchManifest(target.manifestUrl);
    await _syncManifest(dir, manifest, os, (msg, total, file) {
      onProgress(msg, 0.10 + 0.75 * total, file);
    });

    final setup = File(_safeJoin(dir, installer.file).replaceAll('/', Platform.pathSeparator));
    if (!await setup.exists()) throw Exception('Kurucu dosya bulunamadı: ${installer.file}');
    final (exe, args) = installer.installCommand(setup.path);
    onProgress('${app.name} kuruluyor...', 0.88, 0);
    log.write('Kurucu çalışıyor: $exe ${args.join(' ')}');
    final code = await _deps.run(File(exe), args, dir);
    if (!_setupSuccess.contains(code)) throw Exception('${app.name} kurulamadı (kurucu çıkış kodu $code).');
    if (code == 3010) log.write('${app.name}: yeniden başlatma gerekiyor.');

    _programs.invalidate();
    final program = await _programs.find(installer.displayName);
    if (program == null) {
      throw Exception(
        'Kurucu tamamlandı ama "${installer.displayName}" kurulu programlar listesinde bulunamadı. '
        'Katalogdaki displayName değerini kontrol edin.',
      );
    }
    // Başarısız bir kurulum "kurulu" sayılmasın diye kayıt en sonda yazılır.
    await store.put(
      app.id,
      variant.id,
      InstalledRecord(
        fingerprint: manifest.fingerprint,
        version: program.version ?? manifest.context.version,
        updatedAt: DateTime.now(),
      ),
    );
    try {
      await dir.delete(recursive: true); // kurucu dosyaları yer kaplamasın
    } on FileSystemException catch (e) {
      log.write('Kurucu dosyaları silinemedi: ${e.message}');
    }
    onProgress('Hazır.', 1.0, 0);
    log.write('Kurulum tamamlandı: ${app.id}/${variant.id} (${program.version})');
  }

  /// Manifestteki [os] dosyalarını [dir]'e senkronlar; `total` 0..1 aralığındadır.
  Future<void> _syncManifest(Directory dir, Manifest manifest, String os, ProgressCallback onProgress) async {
    final osFiles = manifest.context.osFileList.firstWhere(
      (f) => f.os == os,
      orElse: () => throw Exception('$os için yapılandırma bulunamadı.'),
    );
    final total = osFiles.fileList.length;
    for (var i = 0; i < total; i++) {
      final entry = osFiles.fileList[i];
      double overall(double fileFraction) => (i + fileFraction) / total;
      await _syncFile(dir, entry, (msg, fileFraction) {
        onProgress(msg, overall(fileFraction), fileFraction);
      });
      onProgress('✓ ${entry.name}', overall(1), 0);
    }
  }

  // ── Bağımlılıklar ──────────────────────────────────────────────────────────

  static const _depRecordApp = '_dep';

  Directory dependencyDir(Dependency dep, String os) => Directory('${baseDir.path}/deps/${dep.id}/$os');

  /// Bağımlılık makinede yoksa indirir ve kurar. Bu işletim sistemi için hedefi
  /// yoksa hiçbir şey yapmaz. İlerleme çubuğunun ilk %10'unu kullanır.
  static const onlineCheckUrl = 'https://checkip.amazonaws.com';

  /// İnternete çıkılabiliyor mu? `checkip.amazonaws.com` IP adresi döndürüyorsa evet.
  Future<bool> isOnline() async {
    try {
      final r = await _client.get(Uri.parse(onlineCheckUrl)).timeout(const Duration(seconds: 5));
      return r.statusCode == 200 && RegExp(r'^[0-9a-fA-F.:]{7,45}$').hasMatch(r.body.trim());
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureDependency(Dependency dep, String os, ProgressCallback onProgress) async {
    final target = dep.desktop[os];
    if (target == null) return;
    final apt = target.apt;
    if (apt != null) return _ensureApt(dep, apt, os, onProgress);
    return _ensureInstaller(dep, target, os, onProgress);
  }

  /// İnternet varsa `apt-get install`, yoksa sunucudaki `.deb` dosyalarıyla `dpkg -i`.
  Future<void> _ensureApt(Dependency dep, AptSpec apt, String os, ProgressCallback onProgress) async {
    if (os != 'linux') throw Exception('${dep.name}: apt yalnızca Linux için tanımlanabilir.');
    if (!_deps.hasApt) {
      log.write('${dep.id}: apt bulunamadı (Debian/Ubuntu değil); bağımlılık atlandı.');
      return;
    }
    final missing = await _deps.missingPackages(apt.packages);
    if (missing.isEmpty) {
      log.write('Bağımlılık zaten kurulu: ${dep.id}');
      return;
    }

    final ({int code, String error}) result;
    if (await isOnline()) {
      onProgress('${dep.name} kuruluyor (apt)...', 0.02, 0);
      log.write('Çevrimiçi: apt-get install ${missing.join(' ')}');
      result = await _deps.aptInstall(missing);
    } else {
      final url = apt.offlineManifestUrl;
      if (url == null) {
        throw Exception(
          '${dep.name} için internet gerekiyor (eksik: ${missing.join(', ')}); '
          'çevrimdışı .deb paketi tanımlı değil.',
        );
      }
      log.write('Çevrimdışı: sunucudan .deb paketleri alınıyor (${dep.id})');
      final manifest = await fetchManifest(url);
      final dir = dependencyDir(dep, os);
      await dir.create(recursive: true);
      await _syncManifest(dir, manifest, os, (msg, total, file) {
        onProgress('${dep.name}: $msg', 0.01 + 0.06 * total, file);
      });
      final files = manifest.context.osFileList.firstWhere((f) => f.os == os).fileList;
      final debs = [
        for (final f in files)
          if (f.name.endsWith('.deb')) File(_safeJoin(Directory(_safeJoin(dir, f.path)), f.name)),
      ];
      if (debs.isEmpty) throw Exception('${dep.name}: çevrimdışı pakette .deb dosyası yok.');
      onProgress('${dep.name} kuruluyor (dpkg)...', 0.07, 0);
      result = await _deps.dpkgInstall(debs);
    }
    if (result.code != 0) {
      throw Exception(
        '${dep.name} kurulamadı (çıkış kodu ${result.code})'
        '${result.error.isEmpty ? '' : ': ${result.error}'}.',
      );
    }
    log.write('Bağımlılık kuruldu: ${dep.id}');
  }

  Future<void> _ensureInstaller(Dependency dep, DependencyTarget target, String os, ProgressCallback onProgress) async {
    final rule = target.detect;
    if (rule != null && await _deps.isInstalled(rule)) {
      log.write('Bağımlılık zaten kurulu: ${dep.id}');
      return;
    }

    onProgress('${dep.name} hazırlanıyor...', 0.01, 0);
    final manifest = await fetchManifest(target.manifestUrl!);
    // Ölçüt tanımsızsa tek ipucu önceki kurulumun kaydıdır.
    if (rule == null && store.get(_depRecordApp, dep.id)?.fingerprint == manifest.fingerprint) {
      return;
    }

    final dir = dependencyDir(dep, os);
    await dir.create(recursive: true);
    await _syncManifest(dir, manifest, os, (msg, total, file) {
      onProgress('${dep.name}: $msg', 0.01 + 0.07 * total, file);
    });

    onProgress('${dep.name} kuruluyor...', 0.08, 0);
    final exe = File(_safeJoin(dir, target.run!.executable).replaceAll('/', Platform.pathSeparator));
    if (!await exe.exists()) {
      throw Exception('${dep.name} kurucusu bulunamadı: ${target.run!.executable}');
    }
    log.write('Bağımlılık kuruluyor: ${dep.id} → ${exe.path} ${target.run!.args.join(' ')}');
    final code = await _deps.run(exe, target.run!.args, dir);
    if (!target.successCodes.contains(code)) {
      throw Exception('${dep.name} kurulamadı (çıkış kodu $code).');
    }
    if (code == 3010) log.write('${dep.name}: yeniden başlatma gerekiyor.');

    await store.put(
      _depRecordApp,
      dep.id,
      InstalledRecord(fingerprint: manifest.fingerprint, version: manifest.context.version, updatedAt: DateTime.now()),
    );
    log.write('Bağımlılık kuruldu: ${dep.id}');
  }

  Future<void> _createShortcut(AppEntry app, Variant variant, String os, Directory dir) async {
    final launch = variant.desktop[os]!.launch;
    await shortcuts?.create(
      app: app,
      variant: variant,
      exePath: _safeJoin(dir, launch.executable).replaceAll('/', Platform.pathSeparator),
      args: launch.args,
      workDir: dir.path,
      iconPath: await _fetchIcon(app, dir),
    );
  }

  /// Menü kaydı için logoyu (yalnızca png/svg) en iyi çabayla indirir.
  Future<String?> _fetchIcon(AppEntry app, Directory dir) async {
    final url = app.logoUrl;
    if (url == null || !Platform.isLinux) return null;
    final ext = url.toLowerCase().split('?').first.split('.').last;
    if (ext != 'png' && ext != 'svg') return null;
    try {
      final r = await _client.get(requireSecureUri(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return null;
      final file = File('${dir.path}/.codenfast-icon.$ext');
      await file.writeAsBytes(r.bodyBytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<void> uninstall(AppEntry app, Variant variant, {String? os}) async {
    final dir = installDir(app, variant);
    log.write('Kaldırılıyor: ${app.id}/${variant.id}');
    final installer = variant.desktop[os ?? currentOs()]?.installer;
    if (installer != null) {
      await _uninstallWithSetup(app, variant, installer, dir);
      return;
    }
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      throw Exception('Kaldırılamadı; uygulama çalışıyor olabilir. (${e.osError?.message ?? e.message})');
    }
    await shortcuts?.remove(app, variant);
    await store.remove(app.id, variant.id);
    final parent = dir.parent;
    if (await parent.exists() && await parent.list().isEmpty) await parent.delete();
  }

  /// Kayıt defterindeki kaldırma komutunu sessiz çalıştırır.
  Future<void> _uninstallWithSetup(AppEntry app, Variant variant, InstallerSpec installer, Directory dir) async {
    final program = await _programs.find(installer.displayName);
    if (program != null) {
      final (exe, args) = WindowsPrograms.uninstallCommand(program, installer.type);
      log.write('Kaldırıcı çalışıyor: $exe ${args.join(' ')}');
      final code = await _deps.run(File(exe), args, dir.existsSync() ? dir : baseDir);
      if (!_setupSuccess.contains(code)) throw Exception('${app.name} kaldırılamadı (çıkış kodu $code).');
      _programs.invalidate();
      if (await _programs.find(installer.displayName) != null) {
        throw Exception('${app.name} kaldırılamadı; program hâlâ kurulu görünüyor (kullanıcı iptal etmiş olabilir).');
      }
    }
    await store.remove(app.id, variant.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    final parent = dir.parent;
    if (await parent.exists() && await parent.list().isEmpty) await parent.delete();
  }

  Future<void> _syncFile(
    Directory root,
    FileEntry entry,
    void Function(String message, double fileFraction) onFile,
  ) async {
    final localDir = Directory(_safeJoin(root, entry.path));
    await localDir.create(recursive: true);
    final file = File(_safeJoin(localDir, entry.name));

    if (await _isUpToDate(file, entry)) return;

    onFile('İndiriliyor: ${entry.name}', 0);
    final part = File('${file.path}.part');
    final sink = part.openWrite();
    try {
      final response = await _client
          .send(http.Request('GET', requireSecureUri(entry.url)))
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Bağlantı zaman aşımına uğradı: ${entry.name}'),
          );
      if (response.statusCode != 200) {
        throw Exception('${entry.name} indirilemedi (HTTP ${response.statusCode}).');
      }
      final totalBytes = response.contentLength ?? entry.fileSize;
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onFile('İndiriliyor: ${entry.name}', received / (totalBytes > 0 ? totalBytes : 1));
      }
      await sink.flush();
    } catch (e) {
      log.write('Download hatası: $e');
      await sink.close();
      if (await part.exists()) await part.delete();
      rethrow;
    }
    await sink.close();

    final length = await part.length();
    if (length != entry.fileSize) {
      await part.delete();
      throw Exception('${entry.name} boyut uyuşmazlığı. Beklenen: ${entry.fileSize}, Alınan: $length');
    }
    if (entry.sha256 != null && await _sha256Of(part) != entry.sha256) {
      await part.delete();
      throw Exception('${entry.name} sağlama toplamı (sha256) uyuşmuyor.');
    }

    try {
      await part.rename(file.path);
    } on FileSystemException catch (e) {
      await part.delete();
      throw Exception(
        '${entry.name} yazılamadı; dosya kullanımda olabilir. '
        'Uygulamayı kapatıp tekrar deneyin. (${e.osError?.message ?? e.message})',
      );
    }

    await _postProcess(file, entry, localDir);
  }

  Future<bool> _isUpToDate(File file, FileEntry entry) async {
    if (!await file.exists() || await file.length() != entry.fileSize) {
      return false;
    }
    return entry.sha256 == null || await _sha256Of(file) == entry.sha256;
  }

  Future<String> _sha256Of(File file) async => (await sha256.bind(file.openRead()).first).toString();

  Future<void> _postProcess(File file, FileEntry entry, Directory localDir) async {
    if (Platform.isMacOS) {
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', file.path]);
      log.write('Quarantine kaldırıldı: ${file.path}');
    }

    final inBinDir = entry.path.split(RegExp(r'[/\\]')).contains('bin');
    if ((Platform.isMacOS || Platform.isLinux) && (entry.name.endsWith('.sh') || inBinDir)) {
      await Process.run('chmod', ['+x', file.path]);
      log.write('chmod +x: ${file.path}');
    }

    if (entry.name.endsWith('.zip')) {
      await _extractZip(file.path, localDir.path);
      // unzip macOS/Linux'ta çalıştırma izinlerini düşürür; bin/ için geri ver.
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('find', [localDir.path, '-path', '*/bin/*', '-type', 'f', '-exec', 'chmod', '+x', '{}', '+']);
        log.write('chmod +x bin files in: ${localDir.path}');
      }
    }
  }

  Future<void> _extractZip(String zipPath, String destDir) async {
    log.write('Extracting: $zipPath → $destDir');
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('powershell', [
        '-Command',
        'Expand-Archive -Force -Path "${zipPath.replaceAll('/', '\\')}" '
            '-DestinationPath "${destDir.replaceAll('/', '\\')}"',
      ]);
    } else {
      result = await Process.run('unzip', ['-o', zipPath, '-d', destDir]);
    }
    if (result.exitCode != 0) {
      throw Exception('Zip açma başarısız: ${result.stderr}');
    }
    if (Platform.isMacOS) {
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', destDir]);
    }
    log.write('Extraction tamamlandı: $zipPath');
  }

  /// Sunucudan gelen göreli yolu kök dizinin dışına çıkaramaz hale getirir.
  String _safeJoin(Directory root, String relative) {
    final segments = relative.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty && s != '.').toList();
    if (segments.contains('..') || relative.startsWith('/') || relative.contains(':')) {
      throw Exception('Geçersiz dosya yolu reddedildi: $relative');
    }
    return [root.path, ...segments].join('/');
  }

  // ── Launch ─────────────────────────────────────────────────────────────────

  Future<void> launch(AppEntry app, Variant variant, String os) async {
    final target = variant.desktop[os];
    if (target == null) throw Exception('$os için başlatma yapılandırması yok.');
    final installer = target.installer;
    if (installer != null) return _launchInstalled(target, installer);
    final dir = installDir(app, variant);
    final exePath = _safeJoin(dir, target.launch.executable).replaceAll('/', Platform.pathSeparator);

    if (!await File(exePath).exists()) {
      throw Exception('Çalıştırılabilir dosya bulunamadı: $exePath');
    }
    if (Platform.isLinux || Platform.isMacOS) {
      // İndirme çalıştırma iznini taşımaz; ana dosya bin/ altında olmayabilir.
      await Process.run('chmod', ['+x', exePath]);
    }
    log.write('Başlatılıyor: $exePath ${target.launch.args.join(' ')}');
    await Process.start(exePath, target.launch.args, workingDirectory: dir.path, mode: ProcessStartMode.detached);
  }

  /// Kurulu uygulamayı başlatır; yol ortam değişkenleriyle verilebilir, göreliyse
  /// kayıt defterindeki kurulum klasörüne göre çözülür.
  Future<void> _launchInstalled(DesktopTarget target, InstallerSpec installer) async {
    var path = expandEnv(target.launch.executable, Platform.environment);
    if (!isAbsoluteWindowsPath(path)) {
      final location = (await _programs.find(installer.displayName))?.installLocation;
      if (location == null) throw Exception('Kurulum klasörü bulunamadı; "${target.launch.executable}" çözülemedi.');
      path = '${location.replaceAll(RegExp(r'[\\/]+$'), '')}\\$path';
    }
    if (!await File(path).exists()) throw Exception('Çalıştırılabilir dosya bulunamadı: $path');
    log.write('Başlatılıyor: $path ${target.launch.args.join(' ')}');
    await Process.start(
      path,
      target.launch.args,
      workingDirectory: File(path).parent.path,
      mode: ProcessStartMode.detached,
    );
  }
}
