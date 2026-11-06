import 'dart:io';

import 'package:codenfast_updater/admin/deb_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory out;
  setUp(() async => out = await Directory.systemTemp.createTemp('deb_fetch'));
  tearDown(() => out.delete(recursive: true));

  test('runs docker with packages as positional args and returns the .deb files', () async {
    late List<String> args;
    final fetcher = DebFetcher(
      runner: (exe, a, onLine) async {
        expect(exe, 'docker');
        args = a;
        onLine('Get:1 libfoo1');
        await File('${out.path}/b.deb').writeAsString('x');
        await File('${out.path}/a.deb').writeAsString('x');
        await File('${out.path}/notes.txt').writeAsString('x');
        return 0;
      },
    );
    final lines = <String>[];
    final debs = await fetcher.fetch(packages: ['libfoo1', 'libbar2'], image: 'ubuntu:22.04', out: out, log: lines.add);

    expect(debs.map((f) => f.path.split('/').last), ['a.deb', 'b.deb']);
    expect(lines, ['Get:1 libfoo1']);
    expect(args, containsAllInOrder(['run', '--rm', 'ubuntu:22.04', 'bash', '-c']));
    expect(args.sublist(args.length - 3), ['_', 'libfoo1', 'libbar2']);
    expect(args.join(' '), contains(':/out'));
    expect(args[args.indexOf('-c') + 1], isNot(contains('libfoo1'))); // betiğe gömülmez
  });

  test('rejects option-like image and package names without running docker', () async {
    final fetcher = DebFetcher(runner: (_, _, _) async => fail('çalışmamalı'));
    expect(() => fetcher.fetch(packages: ['a'], image: '--privileged', out: out), throwsException);
    expect(() => fetcher.fetch(packages: ['-oAPT::x'], image: 'ubuntu:22.04', out: out), throwsException);
    expect(() => fetcher.fetch(packages: [], image: 'ubuntu:22.04', out: out), throwsException);
    expect(DebFetcher.isValidImage('ubuntu:22.04'), isTrue);
    expect(DebFetcher.isValidImage('ghcr.io/x/y@sha256:abc'), isTrue);
  });

  test('fails on docker error or when nothing was downloaded', () async {
    await expectLater(
      DebFetcher(
        runner: (_, _, onLine) async {
          onLine('permission denied');
          return 100;
        },
      ).fetch(packages: ['a'], image: 'ubuntu:22.04', out: out),
      throwsA(predicate((e) => '$e'.contains('çıkış kodu 100): permission denied'))),
    );
    await expectLater(
      DebFetcher(runner: (_, _, _) async => 0).fetch(packages: ['a'], image: 'ubuntu:22.04', out: out),
      throwsA(predicate((e) => '$e'.contains('Hiç .deb'))),
    );
  });

  test('terminal script lists only valid package names', () {
    final script = DebFetcher.terminalScript(['libccid', 'pcscd', '-oAPT::x', 'a;rm']);
    expect(script, contains('apt-cache policy libccid pcscd\n'));
    expect(script, contains('apt-get download \$(apt-cache depends --recurse'));
    expect(script, contains("  libccid pcscd | grep '^\\w' | sort -u)"));
    expect(script, isNot(contains('rm')));
    expect(script, isNot(contains('-oAPT')));
  });

  test('sanitizeNames fixes apt epoch encoding and other unsafe characters, leaves safe names alone', () async {
    await File('${out.path}/gawk_1%3a5.3.2-1ubuntu1.1_amd64.deb').writeAsString('x');
    await File('${out.path}/libstdc++6_14~rc1_amd64.deb').writeAsString('x');
    await File('${out.path}/ok_1.0_amd64.deb').writeAsString('x');
    await File('${out.path}/notes%.txt').writeAsString('x'); // .deb değil: dokunulmaz

    final renamed = await DebFetcher.sanitizeNames(out);
    expect(
      renamed.map((r) => r.$2),
      unorderedEquals(['gawk_1_3a5.3.2-1ubuntu1.1_amd64.deb', 'libstdc__6_14_rc1_amd64.deb']),
    );
    final names = out.listSync().map((e) => e.path.split('/').last).toList()..sort();
    expect(names, [
      'gawk_1_3a5.3.2-1ubuntu1.1_amd64.deb',
      'libstdc__6_14_rc1_amd64.deb',
      'notes%.txt',
      'ok_1.0_amd64.deb',
    ]);
    expect(await DebFetcher.sanitizeNames(out), isEmpty); // ikinci çalıştırma: değişiklik yok
  });

  test('sanitizeNames refuses to overwrite an existing file', () async {
    await File('${out.path}/a%3ab.deb').writeAsString('x');
    await File('${out.path}/a_3ab.deb').writeAsString('y');
    await expectLater(DebFetcher.sanitizeNames(out), throwsA(predicate((e) => '$e'.contains('zaten var'))));
  });
}
