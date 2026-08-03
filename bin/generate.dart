import 'dart:convert';
import 'dart:io';

// Standalone CLI generator — no Flutter imports so `dart run bin/generate.dart` works.

Future<void> main(List<String> args) async {
  final parsed = _GeneratorArgs.parse(args);
  final allIgnores = ['.DS_Store', '_CodeSignature', ...parsed.ignorePatterns];
  final matcher = _IgnoreMatcher(allIgnores);
  final osLabel = parsed.osOverride ?? _detectOs();
  final root = parsed.rootDir != null ? Directory(parsed.rootDir!) : Directory.current;

  _log('');
  _log('╔══════════════════════════════════════════════╗');
  _log('║   Codenfast Updater — JSON Generator         ║');
  _log('╚══════════════════════════════════════════════╝');
  _log('');
  _log('  Root dir : ${root.path}');
  _log('  OS label : $osLabel');
  _log('  Base URL : ${parsed.baseUrl}');
  _log('  Output   : ${parsed.outputPath}');
  if (parsed.ignorePatterns.isNotEmpty) {
    _log('  Ignoring : ${parsed.ignorePatterns.join(', ')}');
  }
  if (parsed.runCommands.isNotEmpty) {
    _log('  Commands : ${parsed.runCommands.join(' | ')}');
  }
  _log('');

  final fileEntries = <Map<String, dynamic>>[];
  int scanned = 0;
  int ignored = 0;

  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;

    final rel = entity.path
        .replaceAll('\\', '/')
        .replaceFirst('${root.path.replaceAll('\\', '/')}/', '');

    if (rel == parsed.outputPath.replaceAll('\\', '/')) {
      ignored++;
      continue;
    }

    if (matcher.matches(rel)) {
      _log('  SKIP  $rel');
      ignored++;
      continue;
    }

    final stat = await entity.stat();
    final fileSize = stat.size;

    final segments = rel.split('/');
    final name = segments.last;
    final dir = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join('/')
        : '';

    final url = '${parsed.baseUrl}/$rel';

    fileEntries.add({
      'name': name,
      'fileSize': fileSize,
      'path': dir,
      'url': url,
    });

    scanned++;
    _log('  ADD   $rel  (${_formatSize(fileSize)})');
  }

  _log('');
  _log('  Scanned : $scanned file(s)');
  _log('  Ignored : $ignored file(s)');
  _log('');

  final rootContextJson = {
    'osFileList': [
      {
        'os': osLabel,
        'fileList': fileEntries,
        'runCommands': parsed.runCommands,
      },
    ],
  };

  final outFile = File(parsed.outputPath);
  final parent = outFile.parent;
  if (!await parent.exists()) await parent.create(recursive: true);

  const encoder = JsonEncoder.withIndent('  ');
  await outFile.writeAsString(encoder.convert(rootContextJson));

  _log('  ✓ Written → ${outFile.path}');
  _log('');
  exit(0);
}

// ─────────────────────────────────────────────────────────────────────────────

class _GeneratorArgs {
  final List<String> ignorePatterns;
  final String outputPath;
  final String baseUrl;
  final List<String> runCommands;
  final String? osOverride;
  final String? rootDir;

  const _GeneratorArgs({
    required this.ignorePatterns,
    required this.outputPath,
    required this.baseUrl,
    required this.runCommands,
    required this.osOverride,
    required this.rootDir,
  });

  factory _GeneratorArgs.parse(List<String> args) {
    final ignorePatterns = <String>[];
    var outputPath = 'files.json';
    var baseUrl = 'http://app.codenfast.com/app';
    final runCommands = <String>[];
    String? osOverride;
    String? rootDir;

    for (int i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--ignore':
          if (i + 1 < args.length) {
            final raw = args[++i];
            ignorePatterns.addAll(
              raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
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
        case '--run':
          if (i + 1 < args.length) runCommands.add(args[++i]);
          break;
        case '--os':
          if (i + 1 < args.length) osOverride = args[++i];
          break;
        case '--root':
          if (i + 1 < args.length) rootDir = args[++i];
          break;
      }
    }

    return _GeneratorArgs(
      ignorePatterns: ignorePatterns,
      outputPath: outputPath,
      baseUrl: baseUrl,
      runCommands: runCommands,
      osOverride: osOverride,
      rootDir: rootDir,
    );
  }
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