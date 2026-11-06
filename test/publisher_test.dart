import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/admin/admin_config.dart';
import 'package:codenfast_updater/admin/catalog_doc.dart';
import 'package:codenfast_updater/admin/publisher.dart';
import 'package:codenfast_updater/admin/ssh_client.dart';
import 'package:codenfast_updater/models/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

class _Fake {
  final calls = <List<String>>[];
  final workDirs = <String?>[];
  String? remoteCatalog; // null: sunucuda yok
  Map<String, dynamic>? uploadedCatalog;
  Map<String, dynamic>? uploadedManifest;

  Future<ProcessResult> run(String exe, List<String> args, {String? workingDirectory}) async {
    calls.add([exe, ...args]);
    workDirs.add(workingDirectory);
    if (exe == 'ssh' && args.last.startsWith('test -f')) {
      return ProcessResult(0, remoteCatalog == null ? 1 : 0, '', '');
    }
    if (exe == 'scp') {
      final dest = args.last;
      if (dest.endsWith('catalog.json.tmp')) {
        uploadedCatalog =
            json.decode(await File('$workingDirectory/catalog.json').readAsString()) as Map<String, dynamic>;
      } else if (dest.endsWith('files.json.tmp')) {
        uploadedManifest =
            json.decode(await File('$workingDirectory/files.json').readAsString()) as Map<String, dynamic>;
      } else if (!dest.contains('@h:')) {
        await File(dest).writeAsString(remoteCatalog!); // indirme
      }
    }
    return ProcessResult(0, 0, '', '');
  }

  List<String> get kinds => [
    for (final c in calls) c[0] == 'ssh' ? 'ssh:${c.last.split(' ').first}' : 'scp:${c.last.split('/').last}',
  ];
}

void main() {
  late Directory src;
  late _Fake fake;
  late Publisher publisher;

  PublishRequest request({String exe = 'bin/run.sh', List<String> ignore = const []}) => PublishRequest(
    sourceDir: src,
    appId: 'demo',
    variantId: 'std',
    variantName: 'Standart',
    os: 'linux',
    version: '2.0.0',
    ignore: ignore,
    meta: const AppMeta(name: 'Demo', category: 'Araç', description: 'd'),
    launchExe: exe,
    launchArgs: const ['--x'],
  );

  setUp(() async {
    src = await Directory.systemTemp.createTemp('publish_src');
    await Directory('${src.path}/bin').create();
    await File('${src.path}/bin/run.sh').writeAsString('#!/bin/sh');
    await File('${src.path}/app.jar').writeAsString('jar');
    await Directory('${src.path}/secrets').create();
    await File('${src.path}/secrets/key.pem').writeAsString('secret');
    fake = _Fake();
    final config = AdminConfig(host: 'h', user: 'u', remoteRoot: '/srv/app', publicBaseUrl: 'https://app.example.com');
    publisher = Publisher(config, SshClient(config, runner: fake.run));
  });

  tearDown(() => src.delete(recursive: true));

  test('prepare builds manifest with public urls and honours ignore', () async {
    final plan = await publisher.prepare(request(ignore: ['secrets/']));
    expect(plan.problems, isEmpty);
    expect(plan.manifest.files.map((f) => f.rel), ['app.jar', 'bin/run.sh']);
    expect(plan.remoteDir, '/srv/app/demo/std/linux');
    expect(plan.manifestUrl, 'https://app.example.com/demo/std/linux/files.json');
    final first = ((plan.manifest.json['osFileList'] as List).first['fileList'] as List).first;
    expect(first['url'], 'https://app.example.com/demo/std/linux/app.jar');
    expect(plan.manifest.json['version'], '2.0.0');
  });

  test('prepare reports missing launch file and unsafe paths', () async {
    expect(
      (await publisher.prepare(request(exe: 'nope.sh', ignore: ['secrets/']))).problems.single,
      contains('Başlatma dosyası klasörde yok'),
    );
    await File('${src.path}/bad name.txt').writeAsString('x');
    final plan = await publisher.prepare(request(ignore: ['secrets/']));
    expect(plan.problems.single, contains('bad name.txt'));
  });

  test('publish uploads files, then manifest, then catalog; nothing ignored leaves', () async {
    final plan = await publisher.prepare(request(ignore: ['secrets/']));
    await publisher.publish(request(ignore: ['secrets/']), plan, (_) {});

    final k = fake.kinds;
    expect(k.first, 'ssh:echo');
    final lastFileUpload = fake.calls.lastIndexWhere((c) => c[0] == 'scp' && c.last.endsWith('/'));
    expect(lastFileUpload, greaterThan(0));
    expect(k.indexOf('scp:files.json.tmp'), greaterThan(lastFileUpload));
    expect(k.last, 'ssh:mv');
    expect(k.indexOf('scp:catalog.json.tmp'), greaterThan(k.indexOf('scp:files.json.tmp')));
    expect(fake.calls.any((c) => c.contains('./key.pem')), isFalse);
    expect(fake.calls.any((c) => c.last == 'u@h:/srv/app/demo/std/linux/bin/' && c.contains('./run.sh')), isTrue);
    expect(fake.calls.any((c) => c.last.startsWith('cp -f')), isFalse); // eski katalog yoktu

    final app = (fake.uploadedCatalog!['apps'] as List).single as Map<String, dynamic>;
    final target = (((app['variants'] as List).single as Map)['desktop'] as Map)['linux'] as Map;
    expect(target['manifestUrl'], 'https://app.example.com/demo/std/linux/files.json');
    expect(target['launch'], {
      'exe': 'bin/run.sh',
      'args': ['--x'],
    });
  });

  test('existing catalog is merged, unknown fields kept, backup made', () async {
    fake.remoteCatalog = json.encode({
      'note': 'keep me',
      'apps': [
        {'id': 'other', 'name': 'Other', 'custom': 1, 'variants': []},
      ],
    });
    final plan = await publisher.prepare(request(ignore: ['secrets/']));
    await publisher.publish(request(ignore: ['secrets/']), plan, (_) {});

    expect(fake.uploadedCatalog!['note'], 'keep me');
    final ids = (fake.uploadedCatalog!['apps'] as List).map((a) => a['id']).toList();
    expect(ids, ['other', 'demo']);
    expect(fake.calls.any((c) => c.last == 'cp -f /srv/app/catalog.json /srv/app/catalog.json.bak'), isTrue);
  });

  test('updateCatalog edits only the catalog: no file uploads, backup kept', () async {
    fake.remoteCatalog = json.encode({
      'note': 'keep me',
      'apps': [
        {'id': 'a', 'name': 'A', 'description': 'eski', 'variants': []},
        {'id': 'b', 'name': 'B', 'variants': []},
      ],
    });
    await publisher.updateCatalog((doc) {
      doc.upsertApp(id: 'a', name: 'A', description: 'yeni');
      doc.removeApp('b');
    }, (_) {});

    expect(fake.uploadedCatalog!['note'], 'keep me');
    final apps = (fake.uploadedCatalog!['apps'] as List).cast<Map>();
    expect(apps.map((a) => a['id']), ['a']);
    expect(apps.single['description'], 'yeni');
    expect(fake.kinds.where((k) => k.startsWith('scp:')), ['scp:remote_catalog.json', 'scp:catalog.json.tmp']);
    expect(fake.calls.any((c) => c.last == 'cp -f /srv/app/catalog.json /srv/app/catalog.json.bak'), isTrue);
  });

  PublishRequest depRequest() => PublishRequest(
    sourceDir: src,
    appId: 'vcredist',
    variantId: 'dep',
    variantName: '',
    os: 'linux',
    meta: const AppMeta(name: ''),
    launchExe: 'bin/run.sh',
    launchArgs: const ['/quiet'],
    dependency: const DependencyMeta(
      name: 'VC++ Redist',
      registryKey: r'HKLM\SOFTWARE\X',
      registryValue: 'Installed',
      equals: '1',
    ),
  );

  test('dependency is published under _deps and recorded in dependencies', () async {
    fake.remoteCatalog = json.encode({
      'apps': [
        {'id': 'demo', 'name': 'Demo', 'requires': <String>[], 'variants': []},
      ],
    });
    final req = depRequest();
    final plan = await publisher.prepare(req);
    expect(plan.problems, isEmpty);
    expect(plan.remoteDir, '/srv/app/_deps/vcredist/linux');
    expect(plan.manifestUrl, 'https://app.example.com/_deps/vcredist/linux/files.json');
    await publisher.publish(req, plan, (_) {});

    final cat = fake.uploadedCatalog!;
    expect(cat['apps'], hasLength(1)); // uygulama kaydı eklenmedi
    final dep = (cat['dependencies'] as List).single as Map;
    expect(dep['id'], 'vcredist');
    final target = (dep['desktop'] as Map)['linux'] as Map;
    expect(target['run'], {
      'exe': 'bin/run.sh',
      'args': ['/quiet'],
    });
    expect(target['detect'], {'registryKey': r'HKLM\SOFTWARE\X', 'registryValue': 'Installed', 'equals': '1'});
  });

  test('apt dependency: .deb folder is the offline fallback; package list can be saved alone', () async {
    final req = PublishRequest(
      sourceDir: src,
      appId: 'libs',
      variantId: 'dep',
      variantName: '',
      os: 'linux',
      meta: const AppMeta(name: ''),
      launchExe: '',
      ignore: const ['secrets/'],
      dependency: const DependencyMeta(name: 'Libs', aptPackages: ['libfoo1']),
    );
    expect((await publisher.prepare(req)).problems.single, contains('.deb'));

    await File('${src.path}/libfoo1.deb').writeAsString('deb');
    final plan = await publisher.prepare(req);
    expect(plan.problems, isEmpty);
    await publisher.publish(req, plan, (_) {});
    var dep = (fake.uploadedCatalog!['dependencies'] as List).single as Map;
    expect((dep['desktop'] as Map)['linux'], {
      'apt': {
        'packages': ['libfoo1'],
        'offlineManifestUrl': 'https://app.example.com/_deps/libs/linux/files.json',
      },
    });

    // Yalnızca liste güncellenince çevrimdışı adres korunur.
    fake.remoteCatalog = json.encode(fake.uploadedCatalog);
    await publisher.updateCatalog(
      (d) => d.upsertAptTarget(id: 'libs', name: 'Libs', packages: ['libfoo1', 'libbar2']),
      (_) {},
    );
    dep = (fake.uploadedCatalog!['dependencies'] as List).single as Map;
    final apt = ((dep['desktop'] as Map)['linux'] as Map)['apt'] as Map;
    expect(apt['packages'], ['libfoo1', 'libbar2']);
    expect(apt['offlineManifestUrl'], contains('_deps/libs/linux/files.json'));
  });

  test('dependency in use cannot be removed; requires must exist', () {
    final doc = CatalogDoc.parse(
      json.encode({
        'dependencies': [
          {'id': 'vc', 'name': 'VC', 'desktop': {}},
        ],
        'apps': [
          {
            'id': 'a',
            'name': 'A',
            'requires': ['vc'],
            'variants': [],
          },
        ],
      }),
    );
    expect(() => doc.removeDependency('vc'), throwsA(predicate((e) => '$e'.contains('a'))));
    doc.setRequires('a', ['yok']);
    expect(doc.validate, throwsFormatException);
    doc.setRequires('a', []);
    expect(doc.removeDependency('vc'), isTrue);
    doc.validate();
  });

  test('download: local ISO is uploaded before catalog; entry stores url, sha256 and size', () async {
    final iso = File('${src.path}/u.iso')..writeAsBytesSync(List.filled(2048, 7));
    final req = DownloadPublishRequest(
      id: 'ubuntu',
      meta: const DownloadMeta(name: 'Ubuntu', category: 'İşletim Sistemleri', version: '26.04'),
      fileLabel: 'Desktop (amd64)',
      fileName: 'ubuntu-26.04.iso',
      local: iso,
    );
    await publisher.publishDownload(req, (_) {});

    final k = fake.kinds;
    expect(k.indexOf('scp:ubuntu-26.04.iso.tmp'), greaterThan(-1));
    expect(k.indexOf('scp:catalog.json.tmp'), greaterThan(k.indexOf('scp:ubuntu-26.04.iso.tmp')));
    expect(fake.calls.any((c) => c.contains('mkdir -p /srv/app/_files/ubuntu')), isTrue);

    final d = (fake.uploadedCatalog!['downloads'] as List).single as Map;
    expect(d['version'], '26.04');
    final f = (d['files'] as List).single as Map;
    expect(f['url'], 'https://app.example.com/_files/ubuntu/ubuntu-26.04.iso');
    expect(f['size'], 2048);
    expect(f['sha256'], hasLength(64));
  });

  test('download: external url needs https + sha256; adding a second file keeps the first', () async {
    DownloadPublishRequest ext({String? url, String? sha, String file = 'a.iso'}) => DownloadPublishRequest(
      id: 'dist',
      meta: const DownloadMeta(name: 'Dist'),
      fileLabel: file,
      fileName: file,
      url: url,
      sha256: sha,
    );
    expect(await publisher.prepareDownload(ext(url: 'http://x/a.iso', sha: 'a' * 64)), isNotEmpty);
    expect(await publisher.prepareDownload(ext(url: 'https://x/a.iso', sha: 'zz')), isNotEmpty);
    expect(await publisher.prepareDownload(ext(url: 'https://x/a.iso', sha: 'A' * 64)), isEmpty);
    expect(
      await publisher.prepareDownload(
        DownloadPublishRequest(
          id: 'dist',
          meta: const DownloadMeta(name: 'Dist'),
          fileLabel: 'x',
          fileName: '../x.iso',
          url: 'https://x/x.iso',
          sha256: 'a' * 64,
        ),
      ),
      isNotEmpty,
    );

    await publisher.publishDownload(ext(url: 'https://m.example/a.iso', sha: 'A' * 64), (_) {});
    fake.remoteCatalog = json.encode(fake.uploadedCatalog);
    await publisher.publishDownload(ext(url: 'https://m.example/b.iso', sha: 'b' * 64, file: 'b.iso'), (_) {});
    final files = (((fake.uploadedCatalog!['downloads'] as List).single as Map)['files'] as List).cast<Map>();
    expect(files.map((f) => f['fileName']), ['a.iso', 'b.iso']);
    expect(files.first['sha256'], 'a' * 64);
    expect(fake.kinds.where((k) => k.endsWith('.iso.tmp')), isEmpty); // harici: yükleme yok
  });

  group('installer apps (windows)', () {
    PublishRequest installerRequest({
      String type = 'inno',
      String file = 'Setup.exe',
      String name = 'Demo',
      String exe = r'%ProgramFiles%\Demo\demo.exe',
      String os = 'windows',
    }) => PublishRequest(
      sourceDir: src,
      appId: 'demo',
      variantId: 'std',
      variantName: 'Standart',
      os: os,
      ignore: const ['secrets/'],
      meta: const AppMeta(name: 'Demo'),
      launchExe: exe,
      installer: InstallerSpec(type: type, file: file, displayName: name, args: const ['ALLUSERS=1']),
    );

    Map windowsTarget() {
      final app = (fake.uploadedCatalog!['apps'] as List).single as Map;
      final variant = (app['variants'] as List).single as Map;
      return (variant['desktop'] as Map)['windows'] as Map;
    }

    test('prepare validates setup file, display name, launch path, msi extension and os', () async {
      await File('${src.path}/Setup.exe').writeAsString('x');
      expect((await publisher.prepare(installerRequest())).problems, isEmpty);
      expect((await publisher.prepare(installerRequest(file: 'Yok.exe'))).problems.single, contains('klasörde yok'));
      expect((await publisher.prepare(installerRequest(name: ' '))).problems.single, contains('displayName'));
      expect((await publisher.prepare(installerRequest(exe: ''))).problems.single, contains('başlatma yolu'));
      expect((await publisher.prepare(installerRequest(type: 'msi'))).problems.single, contains('.msi'));
      expect((await publisher.prepare(installerRequest(os: 'linux'))).problems.single, contains('yalnızca Windows'));
    });

    test('publish writes installer into the catalog; republishing as portable removes it', () async {
      await File('${src.path}/Setup.exe').writeAsString('x');
      final req = installerRequest();
      await publisher.publish(req, await publisher.prepare(req), (_) {});
      var t = windowsTarget();
      expect(t['installer'], {
        'type': 'inno',
        'file': 'Setup.exe',
        'displayName': 'Demo',
        'args': ['ALLUSERS=1'],
      });
      expect((t['launch'] as Map)['exe'], '%ProgramFiles%/Demo/demo.exe');

      fake.remoteCatalog = json.encode(fake.uploadedCatalog);
      final portable = PublishRequest(
        sourceDir: src,
        appId: 'demo',
        variantId: 'std',
        variantName: 'Standart',
        os: 'windows',
        ignore: const ['secrets/'],
        meta: const AppMeta(name: 'Demo'),
        launchExe: 'Setup.exe',
      );
      await publisher.publish(portable, await publisher.prepare(portable), (_) {});
      t = windowsTarget();
      expect(t.containsKey('installer'), isFalse);
    });
  });

  test('unsafe remote paths are rejected', () {
    expect(() => requireSafeRemotePath('/srv/app; rm -rf /'), throwsException);
    expect(() => requireSafeRemotePath('/srv/../etc'), throwsException);
    expect(requireSafeRemotePath('/srv/app/a-b_c.1'), '/srv/app/a-b_c.1');
  });
}
