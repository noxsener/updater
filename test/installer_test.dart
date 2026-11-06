import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/models/catalog.dart';
import 'package:codenfast_updater/models/installed_store.dart';
import 'package:codenfast_updater/services/app_logger.dart';
import 'package:codenfast_updater/services/dependency_runner.dart';
import 'package:codenfast_updater/services/update_service.dart';
import 'package:codenfast_updater/services/windows_programs.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _manifestUrl = 'https://example.com/flykobi/std/windows/files.json';
final _payload = utf8.encode('setup-bytes');

String _manifest(String version, String fileName) => json.encode({
  'version': version,
  'osFileList': [
    {
      'os': 'windows',
      'fileList': [
        {
          'name': fileName,
          'fileSize': _payload.length,
          'sha256': sha256.convert(_payload).toString(),
          'path': '',
          'url': 'https://example.com/flykobi/std/windows/$fileName',
        },
      ],
    },
  ],
});

AppEntry _app(String type, String file) => AppEntry(
  id: 'flykobi',
  name: 'Flykobi',
  description: '',
  logoUrl: null,
  mobile: const {},
  variants: [
    Variant(
      id: 'std',
      name: 'Standart',
      desktop: {
        'windows': DesktopTarget(
          manifestUrl: _manifestUrl,
          launch: const LaunchConfig(executable: r'%ProgramFiles%\Flykobi\flykobi.exe'),
          installer: InstallerSpec(type: type, file: file, displayName: 'Flykobi', args: const ['ALLUSERS=1']),
        ),
      },
    ),
  ],
);

/// Kurucu çalışınca kayıt defterine program ekleyen sahte Windows.
class _FakeWindows extends DependencyRunner {
  final List<String> ran = [];
  final List<Map<String, dynamic>> registry = [];
  int exitCode = 0;
  Map<String, dynamic>? installs; // çalıştırılınca eklenecek program
  bool uninstallRemoves = true;

  _FakeWindows() : super(isWindows: false);

  @override
  Future<int> run(File exe, List<String> args, Directory workDir) async {
    ran.add('${exe.path.split('/').last} ${args.join(' ')}');
    if (exitCode == 0 || exitCode == 3010) {
      if (args.contains('/x') || exe.path.toLowerCase().contains('unins')) {
        if (uninstallRemoves) registry.clear();
      } else if (installs != null) {
        registry
          ..clear()
          ..add(installs!);
      }
    }
    return exitCode;
  }
}

/// Kayıtlar listeleri referansla karşılaştırdığından açılarak denetlenir.
void expectCommand((String, List<String>) actual, String exe, List<String> args) {
  expect(actual.$1, exe);
  expect(actual.$2, args);
}

void main() {
  late Directory tmp;
  late _FakeWindows win;
  late String manifestVersion;
  late String manifestFile;

  Future<UpdateService> build() async {
    final client = MockClient((req) async {
      if (req.url.toString() == _manifestUrl) return http.Response(_manifest(manifestVersion, manifestFile), 200);
      return http.Response.bytes(_payload, 200);
    });
    return UpdateService(
      baseDir: tmp,
      store: await InstalledStore.load(tmp),
      log: await AppLogger.open(tmp),
      client: client,
      dependencyRunner: win,
      programs: WindowsPrograms(
        isWindows: true,
        ttl: Duration.zero,
        runner: (exe, args) async => ProcessResult(0, 0, json.encode(win.registry), ''),
      ),
    );
  }

  Map<String, dynamic> program(String version, {String? quiet, String? uninstall, String key = 'Flykobi_is1'}) => {
    'DisplayName': 'Flykobi 2',
    'DisplayVersion': version,
    'UninstallString': uninstall ?? r'"C:\Program Files\Flykobi\unins000.exe"',
    'QuietUninstallString': ?quiet,
    'InstallLocation': r'C:\Program Files\Flykobi\',
    'PSChildName': key,
  };

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('installer_test');
    win = _FakeWindows();
    manifestVersion = '1.2.0';
    manifestFile = 'FlykobiSetup.exe';
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<void> install(UpdateService s, AppEntry app) => s.install(app, app.variants.single, 'windows', (_, _, _) {});

  test('inno: installs silently, records the registry version and removes the setup files', () async {
    win.installs = program('1.2.0');
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    await install(s, app);

    expect(win.ran.single, endsWith('FlykobiSetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- ALLUSERS=1'));
    expect(s.store.get('flykobi', 'std')!.version, '1.2.0');
    expect(Directory('${tmp.path}/apps/flykobi/std').existsSync(), isFalse);
    final info = await s.inspect(app, app.variants.single, 'windows');
    expect(info.status, AppStatus.upToDate);
    expect(info.installedVersion, '1.2.0');
  });

  test('msi: runs msiexec /i with the downloaded file', () async {
    manifestFile = 'Flykobi.msi';
    win.installs = program('1.2.0', key: '{11111111-2222-3333-4444-555555555555}');
    final s = await build();
    await install(s, _app('msi', 'Flykobi.msi'));
    expect(win.ran.single, startsWith('msiexec.exe /i '));
    expect(win.ran.single, endsWith('Flykobi.msi /qn /norestart ALLUSERS=1'));
  });

  test('upgrade over an existing install: newer manifest version -> updateAvailable; 1.2 equals 1.2.0', () async {
    win.registry.add(program('1.1.0'));
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    expect((await s.inspect(app, app.variants.single, 'windows')).status, AppStatus.updateAvailable);

    win.installs = program('1.2.0');
    await install(s, app); // üstüne kurulur
    manifestVersion = '1.2';
    expect((await s.inspect(app, app.variants.single, 'windows')).status, AppStatus.upToDate);
    manifestVersion = '1.3.0';
    expect((await s.inspect(app, app.variants.single, 'windows')).status, AppStatus.updateAvailable);
  });

  test('not installed -> notInstalled without touching the network', () async {
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    final info = await s.inspect(app, app.variants.single, 'windows');
    expect(info.status, AppStatus.notInstalled);
  });

  test('installer failure or missing registry entry is reported and nothing is recorded', () async {
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    win.exitCode = 1603;
    await expectLater(install(s, app), throwsA(predicate((e) => '$e'.contains('çıkış kodu 1603'))));
    win.exitCode = 0; // kurucu "başarılı" ama programlar listesinde yok
    await expectLater(install(s, app), throwsA(predicate((e) => '$e'.contains('displayName'))));
    expect(s.store.get('flykobi', 'std'), isNull);
  });

  test('installer type is refused on other platforms', () async {
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    await expectLater(s.install(app, app.variants.single, 'linux', (_, _, _) {}), throwsException);
  });

  test('uninstall runs the quiet uninstaller from the registry and clears the record', () async {
    win.installs = program('1.2.0', quiet: r'"C:\Program Files\Flykobi\unins000.exe" /SILENT');
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    await install(s, app);
    win.ran.clear();
    await s.uninstall(app, app.variants.single, os: 'windows');
    expect(win.ran.single, r'C:\Program Files\Flykobi\unins000.exe /SILENT');
    expect(s.store.get('flykobi', 'std'), isNull);
    expect(win.registry, isEmpty);
  });

  test('uninstall fails if the program is still listed (user cancelled)', () async {
    win.installs = program('1.2.0');
    final s = await build();
    final app = _app('inno', 'FlykobiSetup.exe');
    await install(s, app);
    win.uninstallRemoves = false;
    await expectLater(
      s.uninstall(app, app.variants.single, os: 'windows'),
      throwsA(predicate((e) => '$e'.contains('hâlâ kurulu'))),
    );
    expect(s.store.get('flykobi', 'std'), isNotNull);
  });

  group('WindowsPrograms', () {
    test('parses single object and array output', () {
      final one = WindowsPrograms.parse(json.encode(program('1.0')));
      expect(one.single.version, '1.0');
      expect(WindowsPrograms.parse('[${json.encode(program('1.0'))},${json.encode(program('2.0'))}]'), hasLength(2));
      expect(WindowsPrograms.parse(''), isEmpty);
    });

    test('find is case-insensitive prefix match preferring the shortest name', () async {
      final wp = WindowsPrograms(
        isWindows: true,
        runner: (_, _) async => ProcessResult(
          0,
          0,
          json.encode([
            {...program('1.0'), 'DisplayName': 'Flykobi Tools'},
            {...program('2.0'), 'DisplayName': 'Flykobi'},
            {...program('3.0'), 'DisplayName': 'Other'},
          ]),
          '',
        ),
      );
      expect((await wp.find('flykobi'))!.version, '2.0');
      expect(await wp.find('nothing'), isNull);
    });

    test('uninstall command: msi guid, quiet string, plain inno string', () {
      final msi = InstalledProgram(
        name: 'X',
        uninstallString: 'MsiExec.exe /I{11111111-2222-3333-4444-555555555555}',
        keyName: '{11111111-2222-3333-4444-555555555555}',
      );
      expectCommand(WindowsPrograms.uninstallCommand(msi, 'msi'), 'msiexec.exe', [
        '/x',
        '{11111111-2222-3333-4444-555555555555}',
        '/qn',
        '/norestart',
      ]);
      final inno = InstalledProgram(name: 'X', uninstallString: r'"C:\A B\unins000.exe"');
      expectCommand(WindowsPrograms.uninstallCommand(inno, 'inno'), r'C:\A B\unins000.exe', [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
      ]);
      expectCommand(WindowsPrograms.splitCommand(r'C:\Tools\un.exe /S /D=C:\x'), r'C:\Tools\un.exe', [
        '/S',
        r'/D=C:\x',
      ]);
    });

    test('env expansion and absolute path detection', () {
      expect(expandEnv(r'%ProgramFiles%\A\a.exe', {'ProgramFiles': r'C:\Program Files'}), r'C:\Program Files\A\a.exe');
      expect(isAbsoluteWindowsPath(r'C:\a.exe'), isTrue);
      expect(isAbsoluteWindowsPath('bin/a.exe'), isFalse);
    });
  });

  test('catalog parses installer and rejects unknown types', () {
    Map<String, dynamic> cat(String type) => {
      'apps': [
        {
          'id': 'a',
          'name': 'A',
          'variants': [
            {
              'id': 'v',
              'name': 'V',
              'desktop': {
                'windows': {
                  'manifestUrl': 'https://x/files.json',
                  'launch': {'exe': 'a.exe'},
                  'installer': {'type': type, 'file': 's.msi', 'displayName': 'A'},
                },
              },
            },
          ],
        },
      ],
    };
    final t = Catalog.fromJson(cat('msi')).apps.single.variants.single.desktop['windows']!;
    expectCommand(t.installer!.installCommand(r'C:\s.msi'), 'msiexec.exe', ['/i', r'C:\s.msi', '/qn', '/norestart']);
    expect(() => Catalog.fromJson(cat('nsis')), throwsFormatException);
  });

  test('windows installer arguments with spaces are quoted for Start-Process', () async {
    final calls = <String>[];
    final r = DependencyRunner(
      isWindows: true,
      runner: (e, a) async {
        calls.add(a.last);
        return ProcessResult(0, 0, '', '');
      },
    );
    await r.run(File('msiexec.exe'), ['/i', r'C:\Users\Ali Veli\s.msi', '/qn'], Directory('.'));
    expect(calls.single, contains('-ArgumentList @(\'/i\',\'"C:\\Users\\Ali Veli\\s.msi"\',\'/qn\')'));
  });
}
