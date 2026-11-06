import 'dart:io';

import 'package:codenfast_updater/admin/lib_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory app;
  late List<String> calls;

  setUp(() async {
    app = await Directory.systemTemp.createTemp('scan_app');
    calls = [];
    await File('${app.path}/myapp').writeAsBytes([0x7f, 0x45, 0x4c, 0x46, 2, 1, 1]);
    await Directory('${app.path}/lib').create();
    await File('${app.path}/lib/libown.so').writeAsBytes([0x7f, 0x45, 0x4c, 0x46, 2]);
    await File('${app.path}/readme.txt').writeAsString('not elf');
  });
  tearDown(() => app.delete(recursive: true));

  Future<ProcessResult> fake(String exe, List<String> args) async {
    calls.add('$exe ${args.join(' ')}');
    switch (exe) {
      case 'ldd':
        final root = app.resolveSymbolicLinksSync();
        return ProcessResult(0, 0, '''
	linux-vdso.so.1 (0x00007ffc)
	libgtk-3.so.0 => /usr/lib/x86_64-linux-gnu/libgtk-3.so.0 (0x00007f1)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f2)
	libown.so => $root/lib/libown.so (0x00007f3)
	libweird.so.1 => /opt/weird/libweird.so.1 (0x00007f4)
	libgone.so.2 => not found
''', '');
      case 'dpkg':
        return ProcessResult(0, 1, '''
libgtk-3-0:amd64: /usr/lib/x86_64-linux-gnu/libgtk-3.so.0
libc6:amd64: /lib/x86_64-linux-gnu/libc.so.6
''', 'dpkg-query: no path found matching pattern /opt/weird/libweird.so.1');
      case 'docker':
        return ProcessResult(0, 0, 'libc6\nbash\n', '');
    }
    throw StateError(exe);
  }

  test('maps libraries to packages, drops bundled and base ones, reports leftovers', () async {
    final r = await LibScanner(runner: fake).scan(app, image: 'ubuntu:22.04');
    expect(r.scannedFiles, 2);
    expect(r.packages, ['libgtk-3-0']); // libc6 temel sistemde, libown klasörde
    expect(r.unresolved, ['/opt/weird/libweird.so.1']);
    expect(r.missing, ['libgone.so.2']);
    expect(r.filtered, isTrue);
    expect(calls.where((c) => c.startsWith('ldd')), hasLength(2));
    expect(calls.where((c) => c.startsWith('dpkg -S -- ')), hasLength(1));
  });

  test('without docker the list is returned unfiltered with a warning', () async {
    final logs = <String>[];
    final r = await LibScanner(
      runner: (exe, args) =>
          exe == 'docker' ? Future.value(ProcessResult(0, 125, '', 'permission denied')) : fake(exe, args),
    ).scan(app, image: 'ubuntu:22.04', log: logs.add);
    expect(r.packages, ['libc6', 'libgtk-3-0']);
    expect(r.filtered, isFalse);
    expect(logs.any((l) => l.contains('permission denied')), isTrue);
  });

  test('rejects an option-like image name', () {
    expect(() => LibScanner(runner: fake).scan(app, image: '--privileged'), throwsException);
  });
}
