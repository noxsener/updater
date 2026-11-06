import 'dart:convert';
import 'dart:io';

import 'dependency_runner.dart';

/// "Programlar ve Özellikler"deki bir kayıt (Uninstall anahtarı).
class InstalledProgram {
  final String name;
  final String? version;
  final String? uninstallString;
  final String? quietUninstallString;
  final String? installLocation;

  /// Kayıt defteri alt anahtarı; MSI için ürün kodudur (`{GUID}`).
  final String? keyName;

  const InstalledProgram({
    required this.name,
    this.version,
    this.uninstallString,
    this.quietUninstallString,
    this.installLocation,
    this.keyName,
  });
}

final _guid = RegExp(r'\{[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}');

/// Windows kayıt defterindeki kurulu programları okur. PowerShell çağrısı yavaş olduğundan
/// sonuç kısa süre önbelleğe alınır; kurulum/kaldırma sonrası [invalidate] çağrılmalıdır.
class WindowsPrograms {
  static const _script =
      r"$p='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',"
      r"'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',"
      r"'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; "
      r'Get-ItemProperty $p -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | '
      r'Select-Object DisplayName,DisplayVersion,UninstallString,QuietUninstallString,InstallLocation,PSChildName | '
      r'ConvertTo-Json -Compress';

  final ProcessRunner _run;
  final bool _windows;
  final Duration _ttl;
  List<InstalledProgram>? _cache;
  DateTime? _at;

  WindowsPrograms({ProcessRunner? runner, bool? isWindows, Duration ttl = const Duration(seconds: 15)})
    : _run = runner ?? ((exe, args) => Process.run(exe, args)),
      _windows = isWindows ?? Platform.isWindows,
      _ttl = ttl;

  void invalidate() => _cache = null;

  Future<List<InstalledProgram>> list() async {
    if (!_windows) return const [];
    final cached = _cache;
    if (cached != null && DateTime.now().difference(_at!) < _ttl) return cached;
    final r = await _run('powershell', ['-NoProfile', '-NonInteractive', '-Command', _script]);
    if (r.exitCode != 0) throw Exception('Kurulu programlar okunamadı: ${'${r.stderr}'.trim()}');
    _at = DateTime.now();
    return _cache = parse('${r.stdout}');
  }

  /// [namePrefix] ile başlayan program (büyük/küçük harf duyarsız); tam eşleşme önceliklidir.
  Future<InstalledProgram?> find(String namePrefix) async {
    final key = namePrefix.trim().toLowerCase();
    final all = (await list()).where((p) => p.name.toLowerCase().startsWith(key)).toList();
    if (all.isEmpty) return null;
    all.sort((a, b) => a.name.length.compareTo(b.name.length)); // tam ad en kısa olandır
    return all.first;
  }

  /// `ConvertTo-Json` tek kayıtta nesne, çoklu kayıtta dizi döndürür.
  static List<InstalledProgram> parse(String output) {
    final text = output.trim();
    if (text.isEmpty) return const [];
    final decoded = json.decode(text);
    final items = decoded is List ? decoded : [decoded];
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    return [
      for (final m in items.cast<Map<String, dynamic>>())
        InstalledProgram(
          name: m['DisplayName'] as String,
          version: s(m['DisplayVersion']),
          uninstallString: s(m['UninstallString']),
          quietUninstallString: s(m['QuietUninstallString']),
          installLocation: s(m['InstallLocation']),
          keyName: s(m['PSChildName']),
        ),
    ];
  }

  /// Programı sessiz kaldıracak komut (exe, argümanlar).
  static (String, List<String>) uninstallCommand(InstalledProgram p, String type) {
    final u = p.uninstallString ?? '';
    final guid = _guid.firstMatch(u)?.group(0) ?? (type == 'msi' ? _guid.firstMatch(p.keyName ?? '')?.group(0) : null);
    if (guid != null && (u.toLowerCase().contains('msiexec') || type == 'msi')) {
      return ('msiexec.exe', ['/x', guid, '/qn', '/norestart']);
    }
    if (p.quietUninstallString != null) return splitCommand(p.quietUninstallString!);
    if (u.isEmpty) throw Exception('${p.name} için kaldırma komutu bulunamadı.');
    final (exe, args) = splitCommand(u);
    return (
      exe,
      [
        ...args,
        if (type == 'inno') ...['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      ],
    );
  }

  /// `"C:\Program Files\X\unins000.exe" /SILENT` → (exe, [/SILENT]).
  static (String, List<String>) splitCommand(String command) {
    final c = command.trim();
    String exe;
    String rest;
    if (c.startsWith('"')) {
      final end = c.indexOf('"', 1);
      if (end < 0) throw Exception('Geçersiz komut: $command');
      exe = c.substring(1, end);
      rest = c.substring(end + 1);
    } else {
      final m = RegExp(r'^(.*?\.exe)(?:\s+(.*))?$', caseSensitive: false).firstMatch(c);
      if (m == null) throw Exception('Geçersiz komut: $command');
      exe = m.group(1)!;
      rest = m.group(2) ?? '';
    }
    final args = [for (final t in RegExp(r'"[^"]*"|\S+').allMatches(rest)) t.group(0)!.replaceAll('"', '')];
    return (exe, args);
  }
}

/// `%ProgramFiles%` gibi değişkenleri açar; tanımsızsa olduğu gibi bırakır.
String expandEnv(String path, Map<String, String> env) =>
    path.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => env[m[1]!] ?? env[m[1]!.toUpperCase()] ?? m[0]!);

bool isAbsoluteWindowsPath(String p) => RegExp(r'^([A-Za-z]:[\\/]|\\\\)').hasMatch(p);
