import 'dart:io';

import '../models/catalog.dart';
import 'lib_scanner.dart';

class InstalledPackage {
  final String name;
  final String version;
  final String summary;

  const InstalledPackage(this.name, this.version, this.summary);

  /// Paket adı kütüphane gibi görünüyor mu? (`libssl3`, `libgtk-3-0`...)
  bool get isLibrary => name.startsWith('lib');
}

class InstalledResult {
  final List<InstalledPackage> packages;

  /// false: temiz imajla karşılaştırılamadı, liste temel sistemdekileri de içerir.
  final bool filtered;

  const InstalledResult(this.packages, {required this.filtered});
}

/// Bu makinede elle kurulmuş (`apt-mark showmanual`) paketleri listeler ve temiz bir
/// imajda zaten bulunanları eler; kalanlar bağımlılık adayıdır.
class InstalledPackages {
  final RunCommand _run;

  InstalledPackages({RunCommand? runner}) : _run = runner ?? defaultRunCommand;

  Future<InstalledResult> list({required String image, void Function(String)? log}) async {
    final ProcessResult manual;
    try {
      manual = await _run('apt-mark', ['showmanual']);
    } on ProcessException {
      throw Exception('apt-mark bulunamadı; bu araç yalnızca Debian/Ubuntu için.');
    }
    if (manual.exitCode != 0) throw Exception('apt-mark çalışmadı; bu araç yalnızca Debian/Ubuntu için.');
    var names = {
      for (final l in '${manual.stdout}'.split('\n'))
        if (AptSpec.isValidName(l.trim())) l.trim(),
    };
    log?.call('${names.length} elle kurulmuş paket bulundu.');

    var filtered = true;
    try {
      final base = await basePackagesOf(_run, image);
      names = names.difference(base);
      log?.call('Temel sistemde ($image) olanlar elendi; ${names.length} aday kaldı.');
    } catch (e) {
      filtered = false;
      log?.call('⚠ Temiz imajla karşılaştırılamadı, liste süzülmedi: $e');
    }

    final sorted = names.toList()..sort();
    final info = <String, (String, String)>{};
    for (var i = 0; i < sorted.length; i += 200) {
      final chunk = sorted.sublist(i, i + 200 > sorted.length ? sorted.length : i + 200);
      final r = await _run('dpkg-query', ['-W', '-f=\${Package}\t\${Version}\t\${binary:Summary}\n', '--', ...chunk]);
      for (final line in '${r.stdout}'.split('\n')) {
        final parts = line.split('\t');
        if (parts.length >= 3) info[parts[0]] = (parts[1], parts.sublist(2).join('\t'));
      }
    }
    return InstalledResult([
      for (final n in sorted) InstalledPackage(n, info[n]?.$1 ?? '', info[n]?.$2 ?? ''),
    ], filtered: filtered);
  }
}
