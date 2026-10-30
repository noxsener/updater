import 'dart:io';

import '../models/catalog.dart';
import 'app_logger.dart';

/// Linux .desktop `Exec` değeri için tek argüman: çift tırnak + kaçışlar
/// (spesifikasyon: tırnak içinde `"` `` ` `` `$` `\` kaçışlanır, ardından
/// dosya seviyesinde ters bölü bir daha ikilenir; `%` → `%%`).
String desktopExecArg(String arg) {
  final b = StringBuffer('"');
  for (final c in arg.split('')) {
    if (c == r'\') {
      b.write(r'\\\\');
    } else if (c == '"' || c == '`' || c == r'$') {
      b.write('\\\\$c');
    } else if (c == '%') {
      b.write('%%');
    } else {
      b.write(c);
    }
  }
  return (b..write('"')).toString();
}

String linuxDesktopEntry({
  required String name,
  required String comment,
  required String exe,
  required List<String> args,
  required String workDir,
  String? icon,
}) {
  String line(String s) => s.replaceAll(RegExp(r'[\r\n]'), ' ');
  return [
    '[Desktop Entry]',
    'Type=Application',
    'Name=${line(name)}',
    'Comment=${line(comment)}',
    'Exec=${[exe, ...args].map(desktopExecArg).join(' ')}',
    'Path=${line(workDir)}',
    if (icon != null) 'Icon=${line(icon)}',
    'Terminal=false',
    'Categories=Utility;',
    '',
  ].join('\n');
}

/// Kurulan uygulamayı işletim sisteminin uygulama menüsüne ekler/kaldırır.
/// Linux: `~/.local/share/applications/*.desktop`
/// macOS: `~/Applications/<Ad>.app`
/// Windows: Başlat menüsü > Programlar > `<Ad>.lnk`
class ShortcutService {
  final AppLogger log;

  ShortcutService(this.log);

  static String displayName(AppEntry app, Variant variant) =>
      app.variants.length > 1 ? '${app.name} (${variant.name})' : app.name;

  String _fileSafe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');

  Future<void> create({
    required AppEntry app,
    required Variant variant,
    required String exePath,
    required List<String> args,
    required String workDir,
    String? iconPath,
  }) async {
    try {
      final name = displayName(app, variant);
      if (Platform.isLinux) {
        final file = File(_linuxFile(app, variant));
        await file.parent.create(recursive: true);
        await file.writeAsString(
          linuxDesktopEntry(
            name: name,
            comment: app.description,
            exe: exePath,
            args: args,
            workDir: workDir,
            icon: iconPath,
          ),
        );
        await Process.run('chmod', ['+x', file.path]);
        // Menünün yeni girdiyi hemen görmesi için; araç yoksa sessizce geçilir.
        await Process.run('update-desktop-database', [file.parent.path]).catchError(
          (_) => ProcessResult(0, 1, '', ''),
        );
      } else if (Platform.isMacOS) {
        await _createMacApp(app, variant, name, exePath, args, workDir);
      } else if (Platform.isWindows) {
        await _createWindowsLink(name, exePath, args, workDir);
      }
      log.write('Kısayol oluşturuldu: $name');
    } catch (e) {
      // Kısayol başarısız olsa da kurulum geçerli sayılır.
      log.write('Kısayol oluşturulamadı: $e');
    }
  }

  Future<void> remove(AppEntry app, Variant variant) async {
    try {
      final name = displayName(app, variant);
      if (Platform.isLinux) {
        final f = File(_linuxFile(app, variant));
        if (await f.exists()) await f.delete();
      } else if (Platform.isMacOS) {
        final d = Directory('${_home()}/Applications/${_fileSafe(name)}.app');
        if (await d.exists()) await d.delete(recursive: true);
      } else if (Platform.isWindows) {
        final f = File(_windowsLink(name));
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      log.write('Kısayol kaldırılamadı: $e');
    }
  }

  String _home() => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  String _linuxFile(AppEntry app, Variant variant) {
    final data = Platform.environment['XDG_DATA_HOME'] ?? '${_home()}/.local/share';
    return '$data/applications/codenfast-${app.id}-${variant.id}.desktop';
  }

  String _windowsLink(String name) =>
      '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\${_fileSafe(name)}.lnk';

  Future<void> _createMacApp(
    AppEntry app,
    Variant variant,
    String name,
    String exePath,
    List<String> args,
    String workDir,
  ) async {
    final bundle = Directory('${_home()}/Applications/${_fileSafe(name)}.app');
    if (await bundle.exists()) await bundle.delete(recursive: true);
    final macos = Directory('${bundle.path}/Contents/MacOS');
    await macos.create(recursive: true);

    String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
    final script = File('${macos.path}/launcher');
    await script.writeAsString(
      '#!/bin/bash\ncd ${q(workDir)}\nexec ${[exePath, ...args].map(q).join(' ')}\n',
    );
    await Process.run('chmod', ['+x', script.path]);

    String x(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
    await File('${bundle.path}/Contents/Info.plist').writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>launcher</string>
<key>CFBundleName</key><string>${x(name)}</string>
<key>CFBundleIdentifier</key><string>com.codenfast.shortcut.${app.id}.${variant.id}</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
''');
  }

  Future<void> _createWindowsLink(
    String name,
    String exePath,
    List<String> args,
    String workDir,
  ) async {
    final lnk = _windowsLink(name);
    await Directory(File(lnk).parent.path).create(recursive: true);
    // Değerler ortam değişkeniyle geçilir; komut metnine gömülmez.
    final result = await Process.run(
      'powershell',
      [
        '-NoProfile',
        '-Command',
        r'$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:CF_LNK);'
            r'$s.TargetPath=$env:CF_TARGET;$s.Arguments=$env:CF_ARGS;'
            r'$s.WorkingDirectory=$env:CF_WD;$s.Save()',
      ],
      environment: {
        'CF_LNK': lnk,
        'CF_TARGET': exePath,
        'CF_ARGS': args.map((a) => '"${a.replaceAll('"', r'\"')}"').join(' '),
        'CF_WD': workDir,
      },
    );
    if (result.exitCode != 0) throw Exception('${result.stderr}');
  }
}
