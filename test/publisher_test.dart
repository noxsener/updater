import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/admin/admin_config.dart';
import 'package:codenfast_updater/admin/publisher.dart';
import 'package:codenfast_updater/admin/ssh_client.dart';
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
        uploadedCatalog = json.decode(await File('$workingDirectory/catalog.json').readAsString()) as Map<String, dynamic>;
      } else if (dest.endsWith('files.json.tmp')) {
        uploadedManifest = json.decode(await File('$workingDirectory/files.json').readAsString()) as Map<String, dynamic>;
      } else if (!dest.contains('@h:')) {
        await File(dest).writeAsString(remoteCatalog!); // indirme
      }
    }
    return ProcessResult(0, 0, '', '');
  }

  List<String> get kinds => [
    for (final c in calls)
      c[0] == 'ssh' ? 'ssh:${c.last.split(' ').first}' : 'scp:${c.last.split('/').last}',
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
    final config = AdminConfig(
      host: 'h', user: 'u', remoteRoot: '/srv/app', publicBaseUrl: 'https://app.example.com',
    );
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
    expect((await publisher.prepare(request(exe: 'nope.sh', ignore: ['secrets/']))).problems.single,
        contains('Başlatma dosyası klasörde yok'));
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
    expect(target['launch'], {'exe': 'bin/run.sh', 'args': ['--x']});
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

  test('unsafe remote paths are rejected', () {
    expect(() => requireSafeRemotePath('/srv/app; rm -rf /'), throwsException);
    expect(() => requireSafeRemotePath('/srv/../etc'), throwsException);
    expect(requireSafeRemotePath('/srv/app/a-b_c.1'), '/srv/app/a-b_c.1');
  });
}
