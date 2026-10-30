import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

// Saf Dart (Flutter bağımlılığı yok): hem `dart run bin/generate.dart` hem de
// uygulamanın `--generate` modu bu dosyayı kullanır.

class GeneratorArgs {
  final List<String> ignorePatterns;
  final String outputPath;
  final String baseUrl;
  final String? osOverride;
  final String? rootDir;
  final String? version;

  const GeneratorArgs({
    required this.ignorePatterns,
    required this.outputPath,
    required this.baseUrl,
    required this.osOverride,
    required this.rootDir,
    required this.version,
  });

  factory GeneratorArgs.parse(List<String> args) {
    final ignorePatterns = <String>[];
    var outputPath = 'files.json';
    var baseUrl = 'https://media.codenfast.com/app';
    String? osOverride;
    String? rootDir;
    String? version;

    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--ignore':
          if (i + 1 < args.length) {
            ignorePatterns.addAll(
              args[++i].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
            );
          }
          break;
        case '--output':
          if (i + 1 < args.length) outputPath = args[++i];
          break;
        case '--base-url':
          if (i + 1 < args.length) {
            baseUrl = args[++i].replaceAll(RegExp(r'/$'), '');
          }
          break;
        case '--os':
          if (i + 1 < args.length) osOverride = args[++i];
          break;
        case '--root':
          if (i + 1 < args.length) rootDir = args[++i];
          break;
        case '--version':
          if (i + 1 < args.length) version = args[++i];
          break;
      }
    }

    return GeneratorArgs(
      ignorePatterns: ignorePatterns,
      outputPath: outputPath,
      baseUrl: baseUrl,
      osOverride: osOverride,
      rootDir: rootDir,
      version: version,
    );
  }
}

class GeneratedFile {
  final String rel; // `/` ayraçlı, kök dizine göre
  final int size;
  final String sha256;

  const GeneratedFile(this.rel, this.size, this.sha256);
}

class GeneratedManifest {
  final Map<String, dynamic> json;
  final List<GeneratedFile> files;
  final int ignored;

  const GeneratedManifest(this.json, this.files, this.ignored);

  int get totalSize => files.fold(0, (a, f) => a + f.size);
}

/// Dizini tarar ve manifest üretir; hiçbir şey yazmaz. CLI ve yönetim ekranı
/// aynı fonksiyonu kullanır.
Future<GeneratedManifest> generateManifest(
  GeneratorArgs parsed, {
  void Function(String line)? log,
}) async {
  final matcher = _IgnoreMatcher(['.DS_Store', '_CodeSignature', ...parsed.ignorePatterns]);
  final osLabel = parsed.osOverride ?? _detectOs();
  final root = parsed.rootDir != null ? Directory(parsed.rootDir!) : Directory.current;
  final rootPrefix = '${root.path.replaceAll('\\', '/')}/';
  final outputRel = parsed.outputPath.replaceAll('\\', '/');

  final entries = <GeneratedFile>[];
  var ignored = 0;

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = entity.path.replaceAll('\\', '/').replaceFirst(rootPrefix, '');

    if (rel == outputRel) {
      ignored++;
      continue;
    }
    if (matcher.matches(rel)) {
      log?.call('  SKIP  $rel');
      ignored++;
      continue;
    }

    final size = (await entity.stat()).size;
    final digest = await sha256.bind(entity.openRead()).first;
    entries.add(GeneratedFile(rel, size, digest.toString()));
    log?.call('  ADD   $rel  (${_formatSize(size)})');
  }

  // Aynı girdide aynı manifest çıksın (güncelleme tespiti manifest hash'ine bağlı).
  entries.sort((a, b) => a.rel.compareTo(b.rel));

  final fileList = [
    for (final e in entries)
      {
        'name': e.rel.split('/').last,
        'fileSize': e.size,
        'sha256': e.sha256,
        'path': e.rel.contains('/') ? e.rel.substring(0, e.rel.lastIndexOf('/')) : '',
        'url': '${parsed.baseUrl}/${e.rel}',
      },
  ];

  return GeneratedManifest(
    {
      if (parsed.version != null) 'version': parsed.version,
      'osFileList': [
        {'os': osLabel, 'fileList': fileList},
      ],
    },
    entries,
    ignored,
  );
}

Future<void> runGenerator(List<String> rawArgs) async {
  final parsed = GeneratorArgs.parse(rawArgs);
  final root = parsed.rootDir != null ? Directory(parsed.rootDir!) : Directory.current;

  _log('');
  _log('  Root dir : ${root.path}');
  _log('  OS label : ${parsed.osOverride ?? _detectOs()}');
  _log('  Base URL : ${parsed.baseUrl}');
  _log('  Output   : ${parsed.outputPath}');
  if (parsed.version != null) _log('  Version  : ${parsed.version}');
  if (parsed.ignorePatterns.isNotEmpty) {
    _log('  Ignoring : ${parsed.ignorePatterns.join(', ')}');
  }
  _log('');

  final result = await generateManifest(parsed, log: _log);

  _log('');
  _log('  Scanned : ${result.files.length} file(s)');
  _log('  Ignored : ${result.ignored} file(s)');
  _log('');

  final outFile = File(parsed.outputPath);
  if (!await outFile.parent.exists()) await outFile.parent.create(recursive: true);
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(result.json));

  _log('  ✓ Written → ${outFile.path}');
  _log('');
}

class _IgnoreMatcher {
  final List<String> _patterns;

  _IgnoreMatcher(List<String> patterns)
      : _patterns = patterns.map(_normalise).toList();

  static String _normalise(String p) => p.replaceAll('\\', '/').trim();

  bool matches(String relativePath) {
    final rel = relativePath.replaceAll('\\', '/');
    final name = rel.split('/').last;

    for (final pattern in _patterns) {
      if (!pattern.contains('*') && !pattern.contains('?')) {
        final clean = pattern.replaceAll('/', '');
        if (rel.split('/').contains(clean)) return true;
        if (rel == pattern || rel.startsWith('$pattern/')) return true;
        if (name == pattern) return true;
        continue;
      }
      if (pattern.startsWith('**/')) {
        final suffix = pattern.substring(3);
        if (_globMatch(suffix, name)) return true;
        for (final segment in rel.split('/')) {
          if (_globMatch(suffix, segment)) return true;
        }
        continue;
      }
      if (!pattern.contains('/')) {
        if (_globMatch(pattern, name)) return true;
        continue;
      }
      if (_globMatch(pattern, rel)) return true;
    }
    return false;
  }

  static bool _globMatch(String pattern, String input) {
    final regexStr = pattern.split('').map((c) {
      switch (c) {
        case '*':
          return '[^/]*';
        case '?':
          return '[^/]';
        case '.':
          return r'\.';
        case r'$':
          return r'\$';
        default:
          return RegExp.escape(c);
      }
    }).join();
    return RegExp('^$regexStr\$').hasMatch(input);
  }
}

String _detectOs() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  return 'unknown';
}

void _log(String msg) => stdout.writeln(msg);

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}