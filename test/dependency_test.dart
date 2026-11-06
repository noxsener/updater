import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/models/catalog.dart';
import 'package:codenfast_updater/models/installed_store.dart';
import 'package:codenfast_updater/services/app_logger.dart';
import 'package:codenfast_updater/services/dependency_runner.dart';
import 'package:codenfast_updater/services/update_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _appManifest = 'https://example.com/app/linux/files.json';
const _depManifest = 'https://example.com/_deps/vc/linux/files.json';
final _payload = utf8.encode('payload');

String _manifest(String url) => json.encode({
  'version': '1',
  'osFileList': [
    {
      'os': 'linux',
      'fileList': [
        {
          'name': 'setup.sh',
          'fileSize': _payload.length,
          'sha256': sha256.convert(_payload).toString(),
          'path': '',
          'url': url,
        },
      ],
    },
  ],
});

Map<String, dynamic> _catalogJson({List<String> requires = const ['vc']}) => {
  'dependencies': [
    {
      'id': 'vc',
      'name': 'VC++ Redist',
      'desktop': {
        'linux': {
          'manifestUrl': _depManifest,
          'run': {
            'exe': 'setup.sh',
            'args': ['/quiet'],
          },
          'detect': {'file': '%HOME%/vc-installed'},
        },
      },
    },
  ],
  'apps': [
    {
      'id': 'demo',
      'name': 'Demo',
      'requires': requires,
      'variants': [
        {
          'id': 'std',
          'name': 'Standart',
          'desktop': {
            'linux': {
              'manifestUrl': _appManifest,
              'launch': {'exe': 'setup.sh'},
            },
          },
        },
      ],
    },
  ],
};

void main() {
  aptTests();
  late Directory tmp;
  late List<String> ran;
  late int exitCode;
  late bool detected;

  Future<UpdateService> build() async {
    final client = MockClient((req) async {
      final u = req.url.toString();
      if (u == _appManifest) return http.Response(_manifest('https://example.com/app/setup.sh'), 200);
      if (u == _depManifest) return http.Response(_manifest('https://example.com/_deps/vc/setup.sh'), 200);
      return http.Response.bytes(_payload, 200);
    });
    return UpdateService(
      baseDir: tmp,
      store: await InstalledStore.load(tmp),
      log: await AppLogger.open(tmp),
      client: client,
      dependencyRunner: _FakeRunner(ran, () => exitCode, () => detected),
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('dep_test');
    ran = [];
    exitCode = 0;
    detected = false;
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<void> install(UpdateService s, AppEntry app) => s.install(app, app.variants.single, 'linux', (_, _, _) {});

  test('catalog resolves requires and rejects unknown dependencies', () {
    final app = Catalog.fromJson(_catalogJson()).apps.single;
    expect(app.requires.single.desktop['linux']!.run!.args, ['/quiet']);
    expect(app.requires.single.desktop['linux']!.successCodes, contains(3010));
    expect(() => Catalog.fromJson(_catalogJson(requires: ['yok'])), throwsFormatException);
  });

  test('catalog without dependencies still parses', () {
    final c = Catalog.fromJson({'apps': []});
    expect(c.dependencies, isEmpty);
  });

  test('missing dependency is installed before the app', () async {
    final s = await build();
    final app = Catalog.fromJson(_catalogJson()).apps.single;
    await install(s, app);
    expect(ran, ['setup.sh /quiet']);
    expect(File('${tmp.path}/apps/demo/std/setup.sh').existsSync(), isTrue);
    expect(s.store.get('_dep', 'vc'), isNotNull);
  });

  test('already detected dependency is skipped', () async {
    detected = true;
    final s = await build();
    await install(s, Catalog.fromJson(_catalogJson()).apps.single);
    expect(ran, isEmpty);
    expect(File('${tmp.path}/apps/demo/std/setup.sh').existsSync(), isTrue);
  });

  test('failing installer aborts the app install', () async {
    exitCode = 5;
    final s = await build();
    final app = Catalog.fromJson(_catalogJson()).apps.single;
    await expectLater(install(s, app), throwsA(predicate((e) => '$e'.contains('çıkış kodu 5'))));
    expect(File('${tmp.path}/apps/demo/std/setup.sh').existsSync(), isFalse);
    expect(s.store.get('_dep', 'vc'), isNull);
    expect(s.store.get('demo', 'std'), isNull);
  });

  test('reboot-required exit code (3010) counts as success', () async {
    exitCode = 3010;
    final s = await build();
    await install(s, Catalog.fromJson(_catalogJson()).apps.single);
    expect(s.store.get('demo', 'std'), isNotNull);
  });

  test('registry output parsing', () {
    const out =
        '\r\nHKEY_LOCAL_MACHINE\\SOFTWARE\\X\r\n    Installed    REG_DWORD    0x1\r\n    Version    REG_SZ    v14.38.33135.00\r\n';
    expect(DependencyRunner.parseRegValue(out, 'Installed'), '1');
    expect(DependencyRunner.parseRegValue(out, 'Version'), 'v14.38.33135.00');
    expect(DependencyRunner.parseRegValue(out, 'Yok'), isNull);
  });

  test('registry detection compares value (windows)', () async {
    DependencyRunner runner(int code, String out) =>
        DependencyRunner(isWindows: true, runner: (exe, args) async => ProcessResult(0, code, out, ''));
    const rule = DetectRule(registryKey: r'HKLM\SOFTWARE\X', registryValue: 'Installed', equals: '1');
    const out = '    Installed    REG_DWORD    0x1\r\n';
    expect(await runner(0, out).isInstalled(rule), isTrue);
    expect(await runner(0, '    Installed    REG_DWORD    0x0\r\n').isInstalled(rule), isFalse);
    expect(await runner(1, '').isInstalled(rule), isFalse);
  });

  test('windows installer is launched elevated with quoted arguments', () async {
    final calls = <List<String>>[];
    final r = DependencyRunner(
      isWindows: true,
      runner: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, 3010, '', '');
      },
    );
    final code = await r.run(File(r"C:\x\it's.exe"), ['/quiet', '/norestart'], Directory(r'C:\x'));
    expect(code, 3010);
    final script = calls.single.last;
    expect(calls.single.first, 'powershell');
    expect(script, contains("-FilePath 'C:\\x\\it''s.exe'"));
    expect(script, contains("-ArgumentList @('/quiet','/norestart')"));
    expect(script, contains('-Verb RunAs'));
  });
}

Map<String, dynamic> _aptCatalog({bool offline = true, List<String> packages = const ['libfoo1', 'libbar2']}) => {
  'dependencies': [
    {
      'id': 'libs',
      'name': 'Kütüphaneler',
      'desktop': {
        'linux': {
          'apt': {'packages': packages, if (offline) 'offlineManifestUrl': _debManifest},
        },
      },
    },
  ],
  'apps': [
    {
      'id': 'demo',
      'name': 'Demo',
      'requires': ['libs'],
      'variants': [
        {
          'id': 'std',
          'name': 'Standart',
          'desktop': {
            'linux': {
              'manifestUrl': _appManifest,
              'launch': {'exe': 'setup.sh'},
            },
          },
        },
      ],
    },
  ],
};

const _debManifest = 'https://example.com/_deps/libs/linux/files.json';

void aptTests() {
  group('apt', () {
    late Directory tmp;
    late List<String> cmds;
    late Set<String> installed;
    late bool online;

    Future<UpdateService> build({bool hasApt = true}) async {
      final client = MockClient((req) async {
        final u = req.url.toString();
        if (u == UpdateService.onlineCheckUrl) {
          return online ? http.Response('203.0.113.7\n', 200) : throw const SocketException('offline');
        }
        if (u == _appManifest) return http.Response(_manifest('https://example.com/app/setup.sh'), 200);
        if (u == _debManifest) {
          return http.Response(
            _manifest('https://example.com/_deps/libs/setup.sh').replaceAll('setup.sh"', 'foo.deb"'),
            200,
          );
        }
        return http.Response.bytes(_payload, 200);
      });
      final runner = DependencyRunner(
        hasApt: hasApt,
        runner: (exe, args) async {
          cmds.add([exe, ...args].join(' '));
          if (exe == 'dpkg-query') {
            return ProcessResult(
              0,
              installed.contains(args.last) ? 0 : 1,
              installed.contains(args.last) ? 'install ok installed' : '',
              '',
            );
          }
          if (exe == 'id') return ProcessResult(0, 0, '1000\n', '');
          return ProcessResult(0, 0, '', '');
        },
      );
      return UpdateService(
        baseDir: tmp,
        store: await InstalledStore.load(tmp),
        log: await AppLogger.open(tmp),
        client: client,
        dependencyRunner: runner,
      );
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('apt_test');
      cmds = [];
      installed = {};
      online = true;
    });
    tearDown(() => tmp.delete(recursive: true));

    Future<void> install(UpdateService s, Map<String, dynamic> cat) {
      final app = Catalog.fromJson(cat).apps.single;
      return s.install(app, app.variants.single, 'linux', (_, _, _) {});
    }

    test('online: installs only missing packages with apt-get via pkexec', () async {
      installed = {'libfoo1'};
      final s = await build();
      await install(s, _aptCatalog());
      expect(cmds.last, 'pkexec env DEBIAN_FRONTEND=noninteractive apt-get install -y -- libbar2');
      expect(cmds.any((c) => c.contains('dpkg -i')), isFalse);
    });

    test('all packages present: nothing is run', () async {
      installed = {'libfoo1', 'libbar2'};
      final s = await build();
      await install(s, _aptCatalog());
      expect(cmds.any((c) => c.startsWith('pkexec')), isFalse);
    });

    test('offline: downloads .deb files and installs them with dpkg', () async {
      online = false;
      final s = await build();
      await install(s, _aptCatalog());
      final last = cmds.last;
      expect(last, startsWith('pkexec dpkg -i -- '));
      expect(last, contains('${tmp.path}/deps/libs/linux/foo.deb'));
      expect(File('${tmp.path}/deps/libs/linux/foo.deb').existsSync(), isTrue);
      expect(cmds.any((c) => c.contains('apt-get')), isFalse);
    });

    test('offline without offline package fails and app is not installed', () async {
      online = false;
      final s = await build();
      await expectLater(
        install(s, _aptCatalog(offline: false)),
        throwsA(predicate((e) => '$e'.contains('internet gerekiyor'))),
      );
      expect(s.store.get('demo', 'std'), isNull);
    });

    test('invalid package names are rejected by the catalog', () {
      expect(() => Catalog.fromJson(_aptCatalog(packages: ['-oAPT::x'])), throwsFormatException);
      expect(() => Catalog.fromJson(_aptCatalog(packages: ['a b'])), throwsFormatException);
      expect(() => Catalog.fromJson(_aptCatalog(packages: [])), throwsFormatException);
    });

    test('system without apt skips the dependency', () async {
      final s = await build(hasApt: false);
      await install(s, _aptCatalog());
      expect(cmds, isEmpty);
      expect(s.store.get('demo', 'std'), isNotNull);
    });
  });
}

class _FakeRunner extends DependencyRunner {
  final List<String> ran;
  final int Function() code;
  final bool Function() detected;

  _FakeRunner(this.ran, this.code, this.detected);

  @override
  Future<bool> isInstalled(DetectRule rule) async => detected();

  @override
  Future<int> run(File exe, List<String> args, Directory workDir) async {
    ran.add('${exe.path.split('/').last} ${args.join(' ')}');
    return code();
  }
}
