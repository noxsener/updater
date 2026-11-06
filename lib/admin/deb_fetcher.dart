import 'dart:convert';
import 'dart:io';

import '../models/catalog.dart';

/// Süreci çalıştırır, her çıktı satırını [onLine]'a verir, çıkış kodunu döndürür.
typedef StreamingRunner = Future<int> Function(String exe, List<String> args, void Function(String) onLine);

Future<int> _defaultRunner(String exe, List<String> args, void Function(String) onLine) async {
  final p = await Process.start(exe, args);
  void pipe(Stream<List<int>> s) => s.transform(utf8.decoder).transform(const LineSplitter()).listen(onLine);
  pipe(p.stdout);
  pipe(p.stderr);
  return p.exitCode;
}

/// Paket listesinin bağımlılıklarıyla birlikte `.deb` dosyalarını, temiz bir Docker
/// konteynerinde `apt-get --download-only` ile indirir. Konteyner temiz olduğu için
/// hedefte eksik olabilecek her şey iner.
class DebFetcher {
  static final _image = RegExp(r'^[a-z0-9][a-z0-9._/:@-]*$');

  final StreamingRunner _run;

  DebFetcher({StreamingRunner? runner}) : _run = runner ?? _defaultRunner;

  static final _unsafe = RegExp(r'[^A-Za-z0-9._-]');

  /// `.deb` dosya adlarındaki URL/uzak kabuk için güvensiz karakterleri (`%3a` sürüm eki,
  /// `+`, `~`...) `_` yapar. Ad kurulumu etkilemez; `dpkg` paketin içindeki üstbilgiyi okur.
  /// Yeniden adlandırılanları (eski, yeni) olarak döndürür.
  static Future<List<(String, String)>> sanitizeNames(Directory dir) async {
    final renamed = <(String, String)>[];
    final files = [
      await for (final e in dir.list(recursive: true, followLinks: false))
        if (e is File && e.path.endsWith('.deb')) e,
    ];
    for (final f in files) {
      final sep = f.path.lastIndexOf(Platform.pathSeparator);
      final name = f.path.substring(sep + 1);
      final clean = name.replaceAll(_unsafe, '_');
      if (clean == name) continue;
      final target = '${f.path.substring(0, sep + 1)}$clean';
      if (await File(target).exists()) throw Exception('"$name" yeniden adlandırılamadı; "$clean" zaten var.');
      await f.rename(target);
      renamed.add((name, clean));
    }
    return renamed;
  }

  /// Docker'sız yol: kendi Debian/Ubuntu makinesinde çalıştırılacak betik. Paketler ve
  /// bağımlılık ağacı `~/debs` klasörüne iner. Geçersiz adlar betiğe girmez.
  static String terminalScript(List<String> packages) {
    final names = packages.where(AptSpec.isValidName).toList();
    final list = names.join(' ');
    return [
      '# 1) Hangi paketler depoda? (Candidate: (none) ise depoda yoktur; .deb dosyasını elle ekleyin)',
      'apt-cache policy $list',
      '',
      '# 2) Paketleri bağımlılıklarıyla ~/debs klasörüne indir',
      'mkdir -p ~/debs && cd ~/debs',
      'apt-get download \$(apt-cache depends --recurse --no-recommends --no-suggests \\',
      '  --no-conflicts --no-breaks --no-replaces --no-enhances \\',
      "  $list | grep '^\\w' | sort -u)",
    ].join('\n');
  }

  /// Docker imajı adı geçerli mi? (`-` ile başlayıp seçenek sayılamaz.)
  static bool isValidImage(String image) => _image.hasMatch(image);

  /// [out] içine indirilen `.deb` dosyalarını döndürür.
  Future<List<File>> fetch({
    required List<String> packages,
    required String image,
    required Directory out,
    void Function(String)? log,
  }) async {
    if (!isValidImage(image)) throw Exception('Geçersiz Docker imajı: "$image"');
    for (final p in packages) {
      if (!AptSpec.isValidName(p)) throw Exception('Geçersiz paket adı: $p');
    }
    if (packages.isEmpty) throw Exception('Paket listesi boş.');
    await out.create(recursive: true);

    // Paket adları betiğe değil, konumsal argüman olarak gider (kabuk enjeksiyonu yok).
    // --reinstall: imajda zaten kurulu olsa bile istenen paketin kendisi de iner.
    const script =
        'set -e; apt-get update; '
        'apt-get install -y --download-only --reinstall -- "\$@"; '
        'cp /var/cache/apt/archives/*.deb /out/; '
        'if [ -n "\$HOST_UID" ]; then chown "\$HOST_UID:\$HOST_GID" /out/*.deb; fi';
    String last = '';
    final owner = await _owner();
    final code =
        await _run(
          'docker',
          [
            'run',
            '--rm',
            '-v',
            '${out.absolute.path}:/out',
            if (owner != null) ...['-e', 'HOST_UID=${owner.$1}', '-e', 'HOST_GID=${owner.$2}'],
            image,
            'bash',
            '-c',
            script,
            '_',
            ...packages,
          ],
          (line) {
            if (line.trim().isNotEmpty) last = line.trim();
            log?.call(line);
          },
        ).onError<ProcessException>(
          (e, _) => throw Exception('docker çalıştırılamadı; kurulu ve çalışır olmalı. (${e.message})'),
        );
    if (code != 0) throw Exception('İndirme başarısız (docker çıkış kodu $code)${last.isEmpty ? '' : ': $last'}');

    await sanitizeNames(out);
    final debs = [
      for (final f in out.listSync())
        if (f is File && f.path.endsWith('.deb')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    if (debs.isEmpty) throw Exception('Hiç .deb indirilmedi (paketler imajda zaten güncel olabilir).');
    return debs;
  }

  /// Dosyaların sahibi root olmasın diye geçerli kullanıcı (yalnızca Linux/macOS).
  Future<(String, String)?> _owner() async {
    if (Platform.isWindows) return null;
    try {
      final uid = (await Process.run('id', ['-u'])).stdout.toString().trim();
      final gid = (await Process.run('id', ['-g'])).stdout.toString().trim();
      return uid.isEmpty || gid.isEmpty ? null : (uid, gid);
    } catch (_) {
      return null;
    }
  }
}
