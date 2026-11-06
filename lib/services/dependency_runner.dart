import 'dart:io';

import '../models/catalog.dart';

typedef ProcessRunner = Future<ProcessResult> Function(String exe, List<String> args);

Future<ProcessResult> _defaultRunner(String exe, List<String> args) => Process.run(exe, args);

/// Bağımlılığın makinede kurulu olup olmadığını denetler ve kurucusunu çalıştırır.
class DependencyRunner {
  final ProcessRunner _run;
  final Map<String, String> _env;
  final bool _windows;
  final bool? _hasApt;

  DependencyRunner({ProcessRunner? runner, Map<String, String>? env, bool? isWindows, bool? hasApt})
    : _run = runner ?? _defaultRunner,
      _hasApt = hasApt,
      _env = env ?? Platform.environment,
      _windows = isWindows ?? Platform.isWindows;

  /// [rule] içindeki tüm ölçütler sağlanıyorsa true.
  Future<bool> isInstalled(DetectRule rule) async {
    final file = rule.file;
    if (file != null && !await File(_expandEnv(file)).exists()) return false;
    final key = rule.registryKey;
    if (key != null && !await _registryMatches(key, rule.registryValue, rule.equals)) return false;
    return file != null || key != null;
  }

  Future<bool> _registryMatches(String key, String? value, String? equals) async {
    if (!_windows) return false;
    final r = await _run('reg', [
      'query',
      key,
      if (value != null) ...['/v', value],
    ]);
    if (r.exitCode != 0) return false;
    if (value == null || equals == null) return true;
    final data = parseRegValue('${r.stdout}', value);
    return data != null && data.toLowerCase() == equals.trim().toLowerCase();
  }

  /// `reg query` çıktısından [value] verisini okur; REG_DWORD (`0x1`) ondalığa çevrilir.
  static String? parseRegValue(String output, String value) {
    final line = RegExp(
      '^\\s+${RegExp.escape(value)}\\s+(REG_\\w+)\\s+(.*?)\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(output);
    if (line == null) return null;
    final data = line.group(2)!;
    if (line.group(1)!.toUpperCase() == 'REG_DWORD' && data.toLowerCase().startsWith('0x')) {
      return int.tryParse(data.substring(2), radix: 16)?.toString() ?? data;
    }
    return data;
  }

  String _expandEnv(String path) =>
      path.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => _env[m[1]!] ?? _env[m[1]!.toUpperCase()] ?? m[0]!);

  /// `Start-Process` dizi öğelerini tırnaklamaz; boşluklu yol/değerler çift tırnağa alınır.
  static String _winArg(String a) => RegExp(r'\s').hasMatch(a) && !a.startsWith('"') ? '"$a"' : a;

  /// Kurucuyu çalıştırıp çıkış kodunu döndürür. Windows'ta yönetici izniyle
  /// (UAC) başlatılır; kullanıcı reddederse istisna fırlatır.
  Future<int> run(File exe, List<String> args, Directory workDir) async {
    if (!_windows) {
      await Process.run('chmod', ['+x', exe.path]);
      return (await _run(exe.path, args)).exitCode;
    }
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final script = StringBuffer()
      ..write('\$ErrorActionPreference = "Stop"; ')
      ..write('\$p = Start-Process -FilePath ${q(exe.path)} ')
      ..write(args.isEmpty ? '' : '-ArgumentList @(${args.map(_winArg).map(q).join(',')}) ')
      ..write('-WorkingDirectory ${q(workDir.path)} -Verb RunAs -Wait -PassThru; ')
      ..write('exit \$p.ExitCode');
    final r = await _run('powershell', ['-NoProfile', '-NonInteractive', '-Command', script.toString()]);
    if (r.exitCode != 0 && '${r.stderr}'.trim().isNotEmpty) {
      throw Exception('Kurucu başlatılamadı: ${'${r.stderr}'.trim().split('\n').first}');
    }
    return r.exitCode;
  }

  // ── apt / dpkg (Debian, Ubuntu) ────────────────────────────────────────────

  /// `apt-get` bu makinede var mı? Yoksa apt bağımlılıkları atlanır.
  bool get hasApt => _hasApt ?? File('/usr/bin/apt-get').existsSync();

  /// [packages] içinden kurulu olmayanlar (`dpkg-query` ile).
  Future<List<String>> missingPackages(List<String> packages) async {
    final missing = <String>[];
    for (final p in packages) {
      final r = await _run('dpkg-query', ['-W', '-f=\${Status}', p]);
      if (r.exitCode != 0 || !'${r.stdout}'.contains('install ok installed')) missing.add(p);
    }
    return missing;
  }

  /// İnternet varken: `apt-get install -y`. `--` paket adının seçenek sayılmasını önler.
  Future<({int code, String error})> aptInstall(List<String> packages) =>
      _privileged(['env', 'DEBIAN_FRONTEND=noninteractive', 'apt-get', 'install', '-y', '--', ...packages]);

  /// İnternet yokken: yerel `.deb` dosyaları, tek `dpkg -i` çağrısıyla (ağa çıkmaz).
  Future<({int code, String error})> dpkgInstall(List<File> debs) =>
      _privileged(['dpkg', '-i', '--', ...debs.map((f) => f.absolute.path)]);

  /// root değilsek `pkexec` ile parola penceresi açılır.
  Future<({int code, String error})> _privileged(List<String> command) async {
    final root = '${(await _run('id', ['-u'])).stdout}'.trim() == '0';
    final r = root ? await _run(command.first, command.sublist(1)) : await _run('pkexec', command);
    final err = '${r.stderr}'.trim();
    return (code: r.exitCode, error: err.isEmpty ? '' : err.split('\n').last);
  }
}
