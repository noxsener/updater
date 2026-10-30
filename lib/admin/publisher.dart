import 'dart:convert';
import 'dart:io';

import '../generator/generator.dart';
import '../models/catalog.dart';
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

  const AppMeta({
    required this.name,
    this.category,
    this.description,
    this.logoUrl,
    this.android,
    this.ios,
  });
}

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
  });
}

class PublishPlan {
  final GeneratedManifest manifest;
  final String remoteDir;
  final String publicDir;
  final List<String> problems; // boş değilse yayınlanamaz

  const PublishPlan({
    required this.manifest,
    required this.remoteDir,
    required this.publicDir,
    required this.problems,
  });

  String get manifestUrl => '$publicDir/files.json';
}

const _desktopOs = {'windows', 'linux', 'macos'};
final _safeRel = RegExp(r'^[A-Za-z0-9._/-]+$');

String _norm(String p) => p.replaceAll('\\', '/');

class Publisher {
  final AdminConfig config;
  final SshClient ssh;

  Publisher(this.config, this.ssh);

  String remoteDirFor(PublishRequest r) =>
      '${config.remoteRoot}/${r.appId}/${r.variantId}/${r.os}';

  String publicDirFor(PublishRequest r) =>
      '${config.publicBaseUrl.replaceAll(RegExp(r'/+$'), '')}/${r.appId}/${r.variantId}/${r.os}';

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
    if (exe.isEmpty) {
      problems.add('Başlatma dosyası (exe) belirtilmedi.');
    } else if (!manifest.files.any((f) => f.rel == exe)) {
      problems.add('Başlatma dosyası klasörde yok: $exe');
    }

    return PublishPlan(
      manifest: manifest,
      remoteDir: remoteDirFor(r),
      publicDir: publicDir,
      problems: problems,
    );
  }

  /// Sıra: bağlantı → katalog çek/birleştir/doğrula → klasörler → dosyalar →
  /// files.json (dosyalardan sonra: istemci yeni manifesti ancak her şey
  /// yerindeyken görür) → catalog.json (yedekle, atomik değiştir).
  Future<void> publish(
    PublishRequest r,
    PublishPlan plan,
    void Function(String) log,
  ) async {
    if (plan.problems.isNotEmpty) throw Exception(plan.problems.join('\n'));
    final tmp = await Directory.systemTemp.createTemp('codenfast_publish');
    try {
      log('Bağlanılıyor: ${config.user}@${config.host}');
      await ssh.test();

      log('Katalog hazırlanıyor...');
      final catalog = await fetchCatalog(tmp);
      final hadCatalog = catalog.existed;
      final doc = catalog.doc;
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
      doc.upsertDesktopTarget(
        appId: r.appId,
        variantId: r.variantId,
        variantName: r.variantName,
        os: r.os,
        manifestUrl: plan.manifestUrl,
        exe: _norm(r.launchExe),
        args: r.launchArgs,
      );
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

  /// Dosya yüklemeden yalnızca catalog.json'u değiştirir: sunucudaki güncel
  /// katalog çekilir, [edit] uygulanır, doğrulanır, yedeklenir, atomik yazılır.
  Future<void> updateCatalog(
    void Function(CatalogDoc doc) edit,
    void Function(String) log,
  ) async {
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
