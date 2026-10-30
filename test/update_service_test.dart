import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/models/catalog.dart';
import 'package:codenfast_updater/models/installed_store.dart';
import 'package:codenfast_updater/models/root_context.dart';
import 'package:codenfast_updater/services/app_logger.dart';
import 'package:codenfast_updater/services/shortcut_service.dart';
import 'package:codenfast_updater/services/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _manifestUrl = 'https://example.com/app/linux/files.json';
final _payload = utf8.encode('hello world');

String _manifest({String? sha, String path = '', String? version, String url = 'https://example.com/app/hello.txt'}) =>
    json.encode({
      if (version != null) 'version': version,
      'osFileList': [
        {
          'os': 'linux',
          'fileList': [
            {
              'name': 'hello.txt',
              'fileSize': _payload.length,
              if (sha != null) 'sha256': sha,
              'path': path,
              'url': url,
            },
          ],
        },
      ],
    });

final _app = AppEntry(
  id: 'demo',
  name: 'Demo',
  description: '',
  logoUrl: null,
  mobile: const {},
  variants: [
    Variant(
      id: 'std',
      name: 'Standart',
      desktop: const {
        'linux': DesktopTarget(
          manifestUrl: _manifestUrl,
          launch: LaunchConfig(executable: 'hello.txt'),
        ),
      },
    ),
  ],
);

void main() {
  late Directory tmp;
  late String manifestBody;
  late UpdateService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('updater_test');
    manifestBody = _manifest(sha: sha256.convert(_payload).toString(), version: '1.0.0');
    final client = MockClient((req) async {
      if (req.url.toString() == _manifestUrl) return http.Response(manifestBody, 200);
      return http.Response.bytes(_payload, 200);
    });
    service = UpdateService(
      baseDir: tmp,
      store: await InstalledStore.load(tmp),
      log: await AppLogger.open(tmp),
      client: client,
    );
  });

  tearDown(() => tmp.delete(recursive: true));

  test('catalog parses apps, variants and mobile links', () {
    final catalog = Catalog.fromJson({
      'apps': [
        {
          'id': 'flykobi',
          'name': 'Flykobi',
          'mobile': {'android': 'https://play.google.com/x'},
          'variants': [
            {
              'id': 'std',
              'name': 'Standart',
              'desktop': {
                'windows': {
                  'manifestUrl': 'https://x/files.json',
                  'launch': {'exe': 'a.exe', 'args': ['-x']},
                },
              },
            },
          ],
        },
      ],
    });
    final app = catalog.apps.single;
    expect(app.mobile['android'], 'https://play.google.com/x');
    expect(app.variants.single.desktop['windows']!.launch.args, ['-x']);
  });

  test('legacy manifest without sha256/version still parses', () {
    final ctx = RootContext.fromJson(json.decode(_manifest()) as Map<String, dynamic>);
    expect(ctx.version, isNull);
    expect(ctx.osFileList.single.fileList.single.sha256, isNull);
  });

  test('install -> upToDate; changed manifest -> updateAvailable', () async {
    expect((await service.inspect(_app, _app.variants.first, 'linux')).status, AppStatus.notInstalled);

    await service.install(_app, _app.variants.first, 'linux', (_, _, _) {});
    final file = File('${service.installDir(_app, _app.variants.first).path}/hello.txt');
    expect(await file.readAsBytes(), _payload);
    expect(await File('${file.path}.part').exists(), isFalse);
    expect((await service.inspect(_app, _app.variants.first, 'linux')).status, AppStatus.upToDate);

    manifestBody = _manifest(sha: sha256.convert(_payload).toString(), version: '1.0.1');
    expect((await service.inspect(_app, _app.variants.first, 'linux')).status, AppStatus.updateAvailable);
  });

  test('sha256 mismatch fails and leaves no file or install record', () async {
    manifestBody = _manifest(sha: 'a' * 64);
    await expectLater(
      service.install(_app, _app.variants.first, 'linux', (_, _, _) {}),
      throwsA(isA<Exception>()),
    );
    final dir = service.installDir(_app, _app.variants.first);
    expect(await File('${dir.path}/hello.txt').exists(), isFalse);
    expect(await File('${dir.path}/hello.txt.part').exists(), isFalse);
    expect(service.store.get('demo', 'std'), isNull);
  });

  test('legacy manifest (size only) installs', () async {
    manifestBody = _manifest();
    await service.install(_app, _app.variants.first, 'linux', (_, _, _) {});
    expect(service.store.get('demo', 'std'), isNotNull);
  });

  test('path traversal in manifest is rejected', () async {
    manifestBody = _manifest(path: '../../evil');
    await expectLater(
      service.install(_app, _app.variants.first, 'linux', (_, _, _) {}),
      throwsA(isA<Exception>()),
    );
  });

  test('non-https file url is rejected', () async {
    manifestBody = _manifest(url: 'http://example.com/hello.txt');
    await expectLater(
      service.install(_app, _app.variants.first, 'linux', (_, _, _) {}),
      throwsA(isA<Exception>()),
    );
  });

  test('uninstall removes files, record and empty app dir', () async {
    await service.install(_app, _app.variants.first, 'linux', (_, _, _) {});
    await service.uninstall(_app, _app.variants.first);
    expect(await service.installDir(_app, _app.variants.first).exists(), isFalse);
    expect(service.store.get('demo', 'std'), isNull);
    expect(await Directory('${tmp.path}/apps/demo').exists(), isFalse);
    expect(
      (await service.inspect(_app, _app.variants.first, 'linux')).status,
      AppStatus.notInstalled,
    );
  });

  test('inspect reports version and size without installing', () async {
    final info = await service.inspect(_app, _app.variants.first, 'linux', needManifest: true);
    expect(info.status, AppStatus.notInstalled);
    expect(info.availableVersion, '1.0.0');
    expect(info.sizeBytes, _payload.length);
  });

  test('ids that could escape the install dir are rejected', () {
    expect(
      () => AppEntry.fromJson({'id': '../x', 'name': 'x'}),
      throwsA(isA<FormatException>()),
    );
  });

  test('desktop entry escapes Exec arguments', () {
    final entry = linuxDesktopEntry(
      name: 'Demo',
      comment: 'c',
      exe: '/opt/my app/run',
      args: [r'a"b$c', '100%'],
      workDir: '/opt/my app',
    );
    expect(entry, contains(r'Exec="/opt/my app/run" "a\\"b\\$c" "100%%"'));
    expect(entry, contains('Path=/opt/my app'));
  });
}
