import 'dart:io';

import 'deb_fetcher.dart';

typedef RunCommand = Future<ProcessResult> Function(String exe, List<String> args);

Future<ProcessResult> defaultRunCommand(String exe, List<String> args) => Process.run(exe, args);

class ScanResult {
  /// Hedefte eksik olabilecek apt paketleri (sıralı).
  final List<String> packages;

  /// Hiçbir pakete bağlanamayan kütüphane yolları.
  final List<String> unresolved;

  /// `ldd` bu makinede bulamadığı için "not found" dediği kütüphane adları.
  final List<String> missing;

  /// Taranan ELF dosyası sayısı.
  final int scannedFiles;

  /// false: temiz imajla karşılaştırılamadı, liste temel sistemdekileri de içerir.
  final bool filtered;

  const ScanResult({
    required this.packages,
    required this.unresolved,
    required this.missing,
    required this.scannedFiles,
    required this.filtered,
  });
}

/// Uygulama klasöründeki ELF dosyalarının `ldd` ile bulunan kütüphanelerini
/// `dpkg -S` ile paketlere çevirir, temiz bir imajda zaten kurulu olanları eler.
///
/// Not: `ldd` incelenen dosyayı çalıştırabilir; yalnızca güvendiğin uygulamayı tara.
class LibScanner {
  static final _resolved = RegExp(r'^\s*\S+ => (/\S+) \(0x[0-9a-f]+\)', multiLine: true);
  static final _notFound = RegExp(r'^\s*(\S+) => not found', multiLine: true);
  static final _dpkgLine = RegExp(r'^(.+): (/.*)$');

  final RunCommand _run;

  LibScanner({RunCommand? runner}) : _run = runner ?? defaultRunCommand;

  Future<ScanResult> scan(Directory dir, {required String image, void Function(String)? log}) async {
    if (!DebFetcher.isValidImage(image)) throw Exception('Geçersiz Docker imajı: "$image"');
    if (!await dir.exists()) throw Exception('Klasör bulunamadı: ${dir.path}');
    final root = dir.resolveSymbolicLinksSync();

    final elves = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && await _isElf(e)) elves.add(e);
    }
    log?.call('${elves.length} ELF dosyası bulundu; ldd çalışıyor...');

    final libs = <String>{};
    final missing = <String>{};
    for (final f in elves) {
      final r = await _run('ldd', [f.path]);
      final out = '${r.stdout}';
      for (final m in _resolved.allMatches(out)) {
        final path = m.group(1)!;
        if (!path.startsWith('$root/')) libs.add(path); // klasörde taşınanlar pakete dahildir
      }
      missing.addAll(_notFound.allMatches(out).map((m) => m.group(1)!));
    }
    log?.call('${libs.length} sistem kütüphanesi; paketler aranıyor...');

    final byPath = await _owners(libs.toList());
    final unresolved = [
      for (final l in libs)
        if (!byPath.containsKey(l)) l,
    ]..sort();
    var packages = {for (final p in byPath.values) ...p};

    var filtered = true;
    try {
      final base = await _basePackages(image);
      log?.call('Temel sistemde ($image) ${base.length} paket var; elenecek.');
      packages = packages.difference(base);
    } catch (e) {
      filtered = false;
      log?.call('⚠ Temiz imajla karşılaştırılamadı, liste süzülmedi: $e');
    }

    return ScanResult(
      packages: packages.toList()..sort(),
      unresolved: unresolved,
      missing: missing.toList()..sort(),
      scannedFiles: elves.length,
      filtered: filtered,
    );
  }

  static Future<bool> _isElf(File f) async {
    try {
      final raf = await f.open();
      try {
        final head = await raf.read(4);
        return head.length == 4 && head[0] == 0x7f && head[1] == 0x45 && head[2] == 0x4c && head[3] == 0x46;
      } finally {
        await raf.close();
      }
    } on FileSystemException {
      return false;
    }
  }

  /// Her kütüphane yolu için sahibi olan paketler. Sembolik bağlantı hedefi de denenir.
  Future<Map<String, Set<String>>> _owners(List<String> libs) async {
    final realOf = <String, String>{}; // ldd yolu -> sembolik bağlantısız yol
    final queries = <String>{};
    for (final l in libs) {
      queries.add(l);
      try {
        final r = File(l).resolveSymbolicLinksSync();
        queries.add(r);
        realOf[l] = r;
      } on FileSystemException {
        // bulunamayan yol dpkg tarafından zaten bildirilir
      }
    }
    final owners = <String, Set<String>>{};
    final list = queries.toList();
    for (var i = 0; i < list.length; i += 200) {
      final chunk = list.sublist(i, i + 200 > list.length ? list.length : i + 200);
      // Bulunamayan yollar stderr'e yazılır ve çıkış kodunu bozar; yalnızca stdout okunur.
      final r = await _run('dpkg', ['-S', '--', ...chunk]);
      for (final line in '${r.stdout}'.split('\n')) {
        final m = _dpkgLine.firstMatch(line.trim());
        if (m == null) continue;
        final names = m.group(1)!.split(',').map((s) => s.trim().split(':').first).where((s) => s.isNotEmpty);
        owners.putIfAbsent(m.group(2)!, () => {}).addAll(names);
      }
    }
    // Sonuçları ldd'nin verdiği özgün yollara bağla.
    return {
      for (final l in libs)
        if ((owners[l] ?? owners[realOf[l]]) case final pkgs?) l: pkgs,
    };
  }

  Future<Set<String>> _basePackages(String image) => basePackagesOf(_run, image);
}

/// Temiz bir Docker imajında kurulu paketler (hedefte zaten var sayılanlar).
Future<Set<String>> basePackagesOf(RunCommand run, String image) async {
  final r = await run('docker', ['run', '--rm', image, 'dpkg-query', '-W', '-f=\${Package}\n']);
  if (r.exitCode != 0) {
    final err = '${r.stderr}'.trim();
    throw Exception('docker çıkış kodu ${r.exitCode}${err.isEmpty ? '' : ': ${err.split('\n').last}'}');
  }
  return '${r.stdout}'.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
}
