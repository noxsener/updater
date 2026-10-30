import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';
import '../models/file_entry.dart';
import '../models/installed_store.dart';
import '../models/root_context.dart';
import 'app_logger.dart';
import 'shortcut_service.dart';
import 'url_guard.dart';

enum AppStatus { notInstalled, updateAvailable, upToDate, offline }

typedef ProgressCallback =
    void Function(String message, double total, double file);

class AppInfo {
  final AppStatus status;
  final String? installedVersion;
  final String? availableVersion;
  final int? sizeBytes;

  const AppInfo({
    required this.status,
    this.installedVersion,
    this.availableVersion,
    this.sizeBytes,
  });
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
  final http.Client _client;

  UpdateService({
    required this.baseDir,
    required this.store,
    required this.log,
    this.shortcuts,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static String currentOs() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unsupported';
  }

  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Directory installDir(AppEntry app, Variant variant) =>
      Directory('${baseDir.path}/apps/${app.id}/${variant.id}');

  // ── Manifest ───────────────────────────────────────────────────────────────

  Future<Manifest> fetchManifest(String url) async {
    final response = await _client
        .get(requireSecureUri(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Sunucu yapılandırma için ${response.statusCode} yanıtı döndürdü.');
    }
    final context = RootContext.fromJson(
      json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
    return Manifest(context, sha256.convert(response.bodyBytes).toString());
  }

  /// Durum + sürüm/boyut bilgisi. Kurulu değilse ve [needManifest] false ise
  /// sunucuya gitmez.
  Future<AppInfo> inspect(
    AppEntry app,
    Variant variant,
    String os, {
    bool needManifest = false,
  }) async {
    final record = store.get(app.id, variant.id);
    final target = variant.desktop[os];
    if (target == null || (record == null && !needManifest)) {
      return AppInfo(status: AppStatus.notInstalled, installedVersion: record?.version);
    }
    try {
      final manifest = await fetchManifest(target.manifestUrl);
      final osFiles = manifest.context.osFileList.where((f) => f.os == os);
      final size = osFiles.isEmpty
          ? null
          : osFiles.first.fileList.fold<int>(0, (a, f) => a + f.fileSize);
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

  // ── Install / update ───────────────────────────────────────────────────────

  Future<void> install(
    AppEntry app,
    Variant variant,
    String os,
    ProgressCallback onProgress,
  ) async {
    final target = variant.desktop[os];
    if (target == null) {
      throw Exception('${app.name} için $os sürümü bulunamadı.');
    }
    final dir = installDir(app, variant);
    await dir.create(recursive: true);
    log.write('Kurulum başladı: ${app.id}/${variant.id} → ${dir.path}');

    onProgress('Yapılandırma alınıyor...', 0.05, 0);
    final manifest = await fetchManifest(target.manifestUrl);
    final osFiles = manifest.context.osFileList.firstWhere(
      (f) => f.os == os,
      orElse: () => throw Exception('$os için yapılandırma bulunamadı.'),
    );

    final total = osFiles.fileList.length;
    for (var i = 0; i < total; i++) {
      final entry = osFiles.fileList[i];
      double overall(double fileFraction) => 0.10 + 0.85 * ((i + fileFraction) / total);
      await _syncFile(dir, entry, (msg, fileFraction) {
        onProgress(msg, overall(fileFraction), fileFraction);
      });
      onProgress('✓ ${entry.name}', overall(1), 0);
    }

    // Başarısız bir kurulum "kurulu" sayılmasın diye kayıt en sonda yazılır.
    await store.put(
      app.id,
      variant.id,
      InstalledRecord(
        fingerprint: manifest.fingerprint,
        version: manifest.context.version,
        updatedAt: DateTime.now(),
      ),
    );
    await _createShortcut(app, variant, os, dir);
    onProgress('Hazır.', 1.0, 0);
    log.write('Kurulum tamamlandı: ${app.id}/${variant.id}');
  }

  Future<void> _createShortcut(
    AppEntry app,
    Variant variant,
    String os,
    Directory dir,
  ) async {
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

  Future<void> uninstall(AppEntry app, Variant variant) async {
    final dir = installDir(app, variant);
    log.write('Kaldırılıyor: ${app.id}/${variant.id}');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      throw Exception(
        'Kaldırılamadı; uygulama çalışıyor olabilir. (${e.osError?.message ?? e.message})',
      );
    }
    await shortcuts?.remove(app, variant);
    await store.remove(app.id, variant.id);
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
            onTimeout: () =>
                throw Exception('Bağlantı zaman aşımına uğradı: ${entry.name}'),
          );
      if (response.statusCode != 200) {
        throw Exception('${entry.name} indirilemedi (HTTP ${response.statusCode}).');
      }
      final totalBytes = response.contentLength ?? entry.fileSize;
      var received = 0;
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        onFile(
          'İndiriliyor: ${entry.name}',
          received / (totalBytes > 0 ? totalBytes : 1),
        );
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
      throw Exception(
        '${entry.name} boyut uyuşmazlığı. Beklenen: ${entry.fileSize}, Alınan: $length',
      );
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

  Future<String> _sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  Future<void> _postProcess(File file, FileEntry entry, Directory localDir) async {
    if (Platform.isMacOS) {
      await Process.run('xattr', ['-dr', 'com.apple.quarantine', file.path]);
      log.write('Quarantine kaldırıldı: ${file.path}');
    }

    final inBinDir = entry.path.split(RegExp(r'[/\\]')).contains('bin');
    if ((Platform.isMacOS || Platform.isLinux) &&
        (entry.name.endsWith('.sh') || inBinDir)) {
      await Process.run('chmod', ['+x', file.path]);
      log.write('chmod +x: ${file.path}');
    }

    if (entry.name.endsWith('.zip')) {
      await _extractZip(file.path, localDir.path);
      // unzip macOS/Linux'ta çalıştırma izinlerini düşürür; bin/ için geri ver.
      if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('find', [
          localDir.path, '-path', '*/bin/*', '-type', 'f',
          '-exec', 'chmod', '+x', '{}', '+',
        ]);
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
    final segments = relative
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty && s != '.')
        .toList();
    if (segments.contains('..') || relative.startsWith('/') || relative.contains(':')) {
      throw Exception('Geçersiz dosya yolu reddedildi: $relative');
    }
    return [root.path, ...segments].join('/');
  }

  // ── Launch ─────────────────────────────────────────────────────────────────

  Future<void> launch(AppEntry app, Variant variant, String os) async {
    final target = variant.desktop[os];
    if (target == null) throw Exception('$os için başlatma yapılandırması yok.');
    final dir = installDir(app, variant);
    final exePath = _safeJoin(dir, target.launch.executable)
        .replaceAll('/', Platform.pathSeparator);

    if (!await File(exePath).exists()) {
      throw Exception('Çalıştırılabilir dosya bulunamadı: $exePath');
    }
    if (Platform.isLinux || Platform.isMacOS) {
      // İndirme çalıştırma iznini taşımaz; ana dosya bin/ altında olmayabilir.
      await Process.run('chmod', ['+x', exePath]);
    }
    log.write('Başlatılıyor: $exePath ${target.launch.args.join(' ')}');
    await Process.start(
      exePath,
      target.launch.args,
      workingDirectory: dir.path,
      mode: ProcessStartMode.detached,
    );
  }
}
