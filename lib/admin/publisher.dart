import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../generator/generator.dart';
import '../models/catalog.dart';
import '../services/url_guard.dart';
import 'admin_config.dart';
import 'catalog_doc.dart';
import 'ssh_client.dart';

class AppMeta {
  final String name;
  final String? category;
  final String? description;
  final String? logoUrl;
  final String? android;
  final String? ios;

  /// Gerekli bağımlılık kimlikleri; null ise katalogdaki mevcut değer korunur.
  final List<String>? requires;

  const AppMeta({
    required this.name,
    this.category,
    this.description,
    this.logoUrl,
    this.android,
    this.ios,
    this.requires,
  });
}

/// Bağımlılık yayınında katalogdaki `dependencies` kaydını oluşturan bilgiler.
class DependencyMeta {
  final String name;
  final String? description;
  final String? registryKey;
  final String? registryValue;
  final String? equals;
  final String? file;

  /// Doluysa Linux `apt` bağımlılığıdır: klasördeki `.deb` dosyaları çevrimdışı yedektir.
  final List<String>? aptPackages;

  const DependencyMeta({
    required this.name,
    this.description,
    this.registryKey,
    this.registryValue,
    this.equals,
    this.file,
    this.aptPackages,
  });
}

/// Uygulama ya da (ortak) bağımlılık yayını. [dependency] doluysa [appId] bağımlılık
/// kimliğidir, [variantId]/[meta] yok sayılır ve [launchExe]/[launchArgs] kurucudur.
class PublishRequest {
  final Directory sourceDir;
  final String appId;
  final String variantId;
  final String variantName;
  final String os; // windows | linux | macos
  final String? version;
  final List<String> ignore;
  final AppMeta meta;
  final String launchExe;
  final List<String> launchArgs;
  final DependencyMeta? dependency;

  /// Doluysa (yalnızca Windows) uygulama dosya senkronu yerine MSI/Inno kurucusuyla kurulur.
  final InstallerSpec? installer;

  const PublishRequest({
    required this.sourceDir,
    required this.appId,
    required this.variantId,
    required this.variantName,
    required this.os,
    this.version,
    this.ignore = const [],
    required this.meta,
    required this.launchExe,
    this.launchArgs = const [],
    this.dependency,
    this.installer,
  });

  /// Sunucudaki ve genel adresteki ürün dizini (`<os>` bunun altındadır).
  String get relDir => dependency != null ? '_deps/$appId' : '$appId/$variantId';
}

class PublishPlan {
  final GeneratedManifest manifest;
  final String remoteDir;
  final String publicDir;
  final List<String> problems; // boş değilse yayınlanamaz

  const PublishPlan({required this.manifest, required this.remoteDir, required this.publicDir, required this.problems});

  String get manifestUrl => '$publicDir/files.json';
}

/// "İşletim Sistemleri" sekmesindeki kaydın bilgileri.
class DownloadMeta {
  final String name;
  final String? description;
  final String? category;
  final String? logoUrl;
  final String? version;

  const DownloadMeta({required this.name, this.description, this.category, this.logoUrl, this.version});
}

/// Tek bir indirilebilir dosya (ISO). [local] doluysa sunucuya yüklenir; yoksa
/// [url] (harici yansı) ve [sha256] verilmelidir.
class DownloadPublishRequest {
  final String id;
  final DownloadMeta meta;
  final String fileLabel;
  final String fileName;
  final File? local;
  final String? url;
  final String? sha256;
  final int? size;

  const DownloadPublishRequest({
    required this.id,
    required this.meta,
    required this.fileLabel,
    required this.fileName,
    this.local,
    this.url,
    this.sha256,
    this.size,
  });
}

const _desktopOs = {'windows', 'linux', 'macos'};
final _safeRel = RegExp(r'^[A-Za-z0-9._/-]+$');

String _norm(String p) => p.replaceAll('\\', '/');

class Publisher {
  final AdminConfig config;
  final SshClient ssh;

  Publisher(this.config, this.ssh);

  String remoteDirFor(PublishRequest r) => '${config.remoteRoot}/${r.relDir}/${r.os}';

  String publicDirFor(PublishRequest r) => '${config.publicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/${r.relDir}/${r.os}';

  /// Ağa çıkmadan: klasörü tarar, manifesti üretir, sorunları listeler.
  Future<PublishPlan> prepare(PublishRequest r, {void Function(String)? log}) async {
    final problems = <String>[...config.validate()];
    if (!_desktopOs.contains(r.os)) problems.add('Geçersiz işletim sistemi: ${r.os}');
    for (final id in [r.appId, r.variantId]) {
      try {
        Catalog.fromJson({
          'apps': [
            {'id': id, 'name': 'x'},
          ],
        });
      } on FormatException {
        problems.add('Geçersiz kimlik: "$id" (harf, rakam, . _ - kullanın).');
      }
    }
    if (!await r.sourceDir.exists()) problems.add('Klasör bulunamadı: ${r.sourceDir.path}');
    if (problems.isNotEmpty) {
      return PublishPlan(
        manifest: const GeneratedManifest({}, [], 0),
        remoteDir: '',
        publicDir: '',
        problems: problems,
      );
    }

    final publicDir = publicDirFor(r);
    final manifest = await generateManifest(
      GeneratorArgs(
        ignorePatterns: r.ignore,
        outputPath: 'files.json', // klasörde eski bir files.json varsa yük sayılmaz
        baseUrl: publicDir,
        osOverride: r.os,
        rootDir: r.sourceDir.path,
        version: r.version?.trim().isEmpty ?? true ? null : r.version!.trim(),
      ),
      log: log,
    );

    if (manifest.files.isEmpty) problems.add('Klasörde yüklenecek dosya yok.');
    final unsafe = manifest.files.where((f) => !_safeRel.hasMatch(f.rel)).map((f) => f.rel).toList();
    if (unsafe.isNotEmpty) {
      problems.add(
        'Şu dosya yolları boşluk/özel karakter içeriyor (URL ve uzak kabuk için güvensiz). '
        'Yeniden adlandırın veya yoksayın:\n  ${unsafe.take(5).join('\n  ')}'
        '${unsafe.length > 5 ? '\n  … ve ${unsafe.length - 5} dosya daha' : ''}',
      );
    }
    final exe = _norm(r.launchExe);
    final setup = r.installer;
    if (setup != null) {
      if (r.os != 'windows') problems.add('Kurucu tipi yalnızca Windows için tanımlanabilir.');
      if (setup.displayName.trim().isEmpty) {
        problems.add('Kurulu program adı (displayName) gerekli; kurulu mu denetimi buna bakar.');
      }
      final file = _norm(setup.file);
      if (file.isEmpty) {
        problems.add('Kurucu dosya belirtilmedi.');
      } else if (!manifest.files.any((f) => f.rel == file)) {
        problems.add('Kurucu dosya klasörde yok: $file');
      } else if (setup.type == 'msi' && !file.toLowerCase().endsWith('.msi')) {
        problems.add('MSI tipinde kurucu .msi uzantılı olmalı: $file');
      }
      if (exe.isEmpty) {
        problems.add('Kurulu uygulamanın başlatma yolu gerekli (örn. %ProgramFiles%\\Uygulama\\app.exe).');
      }
    } else if (r.dependency?.aptPackages != null) {
      if (r.os != 'linux') problems.add('apt paketleri yalnızca Linux için tanımlanabilir.');
      if (!manifest.files.any((f) => f.rel.endsWith('.deb'))) {
        problems.add('Klasörde .deb dosyası yok (çevrimdışı yedek için gerekli).');
      }
    } else if (exe.isEmpty) {
      problems.add(r.dependency != null ? 'Kurucu dosya belirtilmedi.' : 'Başlatma dosyası (exe) belirtilmedi.');
    } else if (!manifest.files.any((f) => f.rel == exe)) {
      problems.add('${r.dependency != null ? 'Kurucu dosya' : 'Başlatma dosyası'} klasörde yok: $exe');
    }

    return PublishPlan(manifest: manifest, remoteDir: remoteDirFor(r), publicDir: publicDir, problems: problems);
  }

  /// Sıra: bağlantı → katalog çek/birleştir/doğrula → klasörler → dosyalar →
  /// files.json (dosyalardan sonra: istemci yeni manifesti ancak her şey
  /// yerindeyken görür) → catalog.json (yedekle, atomik değiştir).
  Future<void> publish(PublishRequest r, PublishPlan plan, void Function(String) log) async {
    if (plan.problems.isNotEmpty) throw Exception(plan.problems.join('\n'));
    final tmp = await Directory.systemTemp.createTemp('codenfast_publish');
    try {
      log('Bağlanılıyor: ${config.user}@${config.host}');
      await ssh.test();

      log('Katalog hazırlanıyor...');
      final catalog = await fetchCatalog(tmp);
      final hadCatalog = catalog.existed;
      final doc = catalog.doc;
      final dep = r.dependency;
      if (dep?.aptPackages != null) {
        doc.upsertAptTarget(
          id: r.appId,
          name: dep!.name,
          description: dep.description,
          packages: dep.aptPackages!,
          offlineManifestUrl: plan.manifestUrl,
        );
      } else if (dep != null) {
        doc.upsertDependencyTarget(
          id: r.appId,
          name: dep.name,
          description: dep.description,
          os: r.os,
          manifestUrl: plan.manifestUrl,
          exe: _norm(r.launchExe),
          args: r.launchArgs,
          registryKey: dep.registryKey,
          registryValue: dep.registryValue,
          equals: dep.equals,
          file: dep.file,
        );
      } else {
        final m = r.meta;
        doc.upsertApp(
          id: r.appId,
          name: m.name,
          category: m.category,
          description: m.description,
          logoUrl: m.logoUrl,
          android: m.android,
          ios: m.ios,
        );
        if (m.requires != null) doc.setRequires(r.appId, m.requires!);
        doc.upsertDesktopTarget(
          appId: r.appId,
          variantId: r.variantId,
          variantName: r.variantName,
          os: r.os,
          manifestUrl: plan.manifestUrl,
          exe: _norm(r.launchExe),
          args: r.launchArgs,
          installer: r.installer,
        );
      }
      doc.validate();

      final dirs = <String>{plan.remoteDir};
      final byDir = <String, List<String>>{};
      for (final f in plan.manifest.files) {
        final i = f.rel.lastIndexOf('/');
        final dir = i < 0 ? '' : f.rel.substring(0, i);
        final name = i < 0 ? f.rel : f.rel.substring(i + 1);
        byDir.putIfAbsent(dir, () => []).add(name);
        if (dir.isNotEmpty) dirs.add('${plan.remoteDir}/$dir');
      }
      log('${dirs.length} uzak klasör hazırlanıyor...');
      await ssh.mkdirs(dirs.toList()..sort());

      var done = 0;
      final total = plan.manifest.files.length;
      for (final entry in byDir.entries) {
        final localDir = entry.key.isEmpty ? r.sourceDir.path : '${r.sourceDir.path}/${entry.key}';
        final remoteDir = entry.key.isEmpty ? plan.remoteDir : '${plan.remoteDir}/${entry.key}';
        for (var i = 0; i < entry.value.length; i += 40) {
          final chunk = entry.value.sublist(i, i + 40 > entry.value.length ? entry.value.length : i + 40);
          await ssh.upload(localDir, chunk, remoteDir);
          done += chunk.length;
          log('Yüklendi: $done/$total');
        }
      }

      log('files.json yükleniyor...');
      final manifestFile = File('${tmp.path}/files.json');
      await manifestFile.writeAsString(_pretty(plan.manifest.json));
      await ssh.uploadAtomic(manifestFile, '${plan.remoteDir}/files.json');

      log('catalog.json güncelleniyor...');
      if (hadCatalog) {
        await ssh.copyRemote(config.catalogRemotePath, '${config.catalogRemotePath}.bak');
      }
      final catalogFile = File('${tmp.path}/catalog.json');
      await catalogFile.writeAsString(doc.encode());
      await ssh.uploadAtomic(catalogFile, config.catalogRemotePath);

      log('✓ Yayınlandı: ${plan.manifestUrl}');
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  static final _sha256 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// Büyük dosyayı belleğe almadan sha256 ve boyutunu hesaplar.
  static Future<({String sha256, int size})> hashFile(File f) async =>
      (sha256: (await sha256.bind(f.openRead()).first).toString(), size: await f.length());

  String downloadPublicUrl(DownloadPublishRequest r) =>
      '${config.publicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/_files/${r.id}/${r.fileName}';

  /// Ağa çıkmadan denetler; boş liste: yayınlanabilir.
  Future<List<String>> prepareDownload(DownloadPublishRequest r) async {
    final problems = <String>[...config.validate()];
    try {
      Catalog.fromJson({
        'apps': [],
        'downloads': [
          {
            'id': r.id,
            'name': 'x',
            'files': [
              {'fileName': r.fileName, 'url': 'https://x', 'sha256': 'a' * 64},
            ],
          },
        ],
      });
    } on FormatException {
      problems.add(
        'Geçersiz kimlik veya dosya adı (harf, rakam, . _ - kullanın; boşluk olmaz): "${r.id}" / "${r.fileName}"',
      );
    }
    if (r.local != null) {
      if (!await r.local!.exists()) problems.add('Dosya bulunamadı: ${r.local!.path}');
    } else {
      if (r.url == null || r.url!.trim().isEmpty) {
        problems.add('Harici URL ya da yüklenecek dosya gerekli.');
      } else {
        try {
          requireSecureUri(r.url!.trim());
        } on Exception {
          problems.add('URL https olmalı: ${r.url}');
        }
      }
      if (r.sha256 == null || !_sha256.hasMatch(r.sha256!.trim())) {
        problems.add('Harici dosya için 64 haneli sha256 gerekli.');
      }
    }
    return problems;
  }

  /// Sıra: bağlantı → katalog çek/birleştir/doğrula → (yükleme) → catalog.json.
  /// Dosya katalogdan önce yüklenir; istemci yeni kaydı ancak dosya yerindeyken görür.
  Future<void> publishDownload(DownloadPublishRequest r, void Function(String) log) async {
    final problems = await prepareDownload(r);
    if (problems.isNotEmpty) throw Exception(problems.join('\n'));
    final tmp = await Directory.systemTemp.createTemp('codenfast_download');
    try {
      log('Bağlanılıyor: ${config.user}@${config.host}');
      await ssh.test();
      final catalog = await fetchCatalog(tmp);
      final doc = catalog.doc;

      final String url;
      final String sha;
      final int? size;
      if (r.local != null) {
        log('sha256 hesaplanıyor...');
        final h = await hashFile(r.local!);
        sha = h.sha256;
        size = h.size;
        url = downloadPublicUrl(r);
        final remoteDir = '${config.remoteRoot}/_files/${r.id}';
        await ssh.mkdirs([remoteDir]);
        log('Yükleniyor (${(size / (1024 * 1024)).toStringAsFixed(0)} MB; büyük dosyalarda uzun sürebilir)...');
        await ssh.uploadAtomic(r.local!, '$remoteDir/${r.fileName}');
      } else {
        url = r.url!.trim();
        sha = r.sha256!.trim().toLowerCase();
        size = r.size;
      }

      final m = r.meta;
      doc.upsertDownload(
        id: r.id,
        name: m.name,
        description: m.description,
        category: m.category,
        logoUrl: m.logoUrl,
        version: m.version,
      );
      doc.upsertDownloadFile(id: r.id, name: r.fileLabel, fileName: r.fileName, url: url, sha256: sha, size: size);
      doc.validate();

      log('catalog.json güncelleniyor...');
      if (catalog.existed) {
        await ssh.copyRemote(config.catalogRemotePath, '${config.catalogRemotePath}.bak');
      }
      final file = File('${tmp.path}/catalog.json');
      await file.writeAsString(doc.encode());
      await ssh.uploadAtomic(file, config.catalogRemotePath);
      log('✓ Yayınlandı: $url');
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// Dosya yüklemeden yalnızca catalog.json'u değiştirir: sunucudaki güncel
  /// katalog çekilir, [edit] uygulanır, doğrulanır, yedeklenir, atomik yazılır.
  Future<void> updateCatalog(void Function(CatalogDoc doc) edit, void Function(String) log) async {
    final tmp = await Directory.systemTemp.createTemp('codenfast_catalog_edit');
    try {
      log('Bağlanılıyor: ${config.user}@${config.host}');
      await ssh.test();
      final catalog = await fetchCatalog(tmp);
      edit(catalog.doc);
      catalog.doc.validate();

      log('catalog.json güncelleniyor...');
      if (catalog.existed) {
        await ssh.copyRemote(config.catalogRemotePath, '${config.catalogRemotePath}.bak');
      }
      final file = File('${tmp.path}/catalog.json');
      await file.writeAsString(catalog.doc.encode());
      await ssh.uploadAtomic(file, config.catalogRemotePath);
      log('✓ Katalog güncellendi.');
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// Sunucudaki katalog; yoksa boş katalog. Bağlantı hatası fırlatılır.
  Future<({CatalogDoc doc, bool existed})> fetchCatalog([Directory? tmpDir]) async {
    final tmp = tmpDir ?? await Directory.systemTemp.createTemp('codenfast_catalog');
    try {
      if (!await ssh.fileExists(config.catalogRemotePath)) {
        return (doc: CatalogDoc.empty(), existed: false);
      }
      final local = File('${tmp.path}/remote_catalog.json');
      await ssh.download(config.catalogRemotePath, local);
      return (doc: CatalogDoc.parse(await local.readAsString()), existed: true);
    } finally {
      if (tmpDir == null) await tmp.delete(recursive: true);
    }
  }

  String _pretty(Map<String, dynamic> j) => '${const JsonEncoder.withIndent('  ').convert(j)}\n';
}
