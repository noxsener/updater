import 'dart:io';

import 'package:codenfast_updater/admin/installed_packages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProcessResult> fake(String exe, List<String> args) async {
    switch (exe) {
      case 'apt-mark':
        return ProcessResult(0, 0, 'bash\nlibgtk-3-0\nvim\n-evil\nBad Name\n\n', '');
      case 'docker':
        return ProcessResult(0, 0, 'bash\ncoreutils\n', '');
      case 'dpkg-query':
        return ProcessResult(
          0,
          0,
          'libgtk-3-0\t3.24.41\tGTK graphical user interface library\nvim\t9.1\tVi IMproved\n',
          '',
        );
    }
    throw StateError(exe);
  }

  test('lists manual packages minus the clean image, with versions and summaries', () async {
    final r = await InstalledPackages(runner: fake).list(image: 'ubuntu:26.04');
    expect(r.filtered, isTrue);
    expect(r.packages.map((p) => p.name), ['libgtk-3-0', 'vim']); // bash temel sistemde; geçersiz adlar atıldı
    expect(r.packages.first.version, '3.24.41');
    expect(r.packages.first.summary, contains('GTK'));
    expect(r.packages.first.isLibrary, isTrue);
    expect(r.packages.last.isLibrary, isFalse);
  });

  test('without docker the list is unfiltered but still returned', () async {
    final logs = <String>[];
    final r = await InstalledPackages(
      runner: (e, a) => e == 'docker' ? Future.value(ProcessResult(0, 125, '', 'permission denied')) : fake(e, a),
    ).list(image: 'ubuntu:26.04', log: logs.add);
    expect(r.filtered, isFalse);
    expect(r.packages.map((p) => p.name), ['bash', 'libgtk-3-0', 'vim']);
    expect(logs.any((l) => l.contains('permission denied')), isTrue);
  });

  test('fails clearly when apt-mark is unavailable', () async {
    await expectLater(
      InstalledPackages(runner: (_, _) async => ProcessResult(0, 127, '', '')).list(image: 'ubuntu:26.04'),
      throwsA(predicate((e) => '$e'.contains('Debian/Ubuntu'))),
    );
  });
}
