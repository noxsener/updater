import 'dart:io';

class AppLogger {
  final IOSink? _sink;
  final String path;

  AppLogger._(this._sink, this.path);

  static Future<AppLogger> open(Directory dir) async {
    try {
      final logFile = File('${dir.path}/updater.log');
      final sink = logFile.openWrite(mode: FileMode.append);
      sink.writeln('');
      sink.writeln('══════════════════════════════════════════════════');
      sink.writeln(
        'Session: ${DateTime.now().toIso8601String()}  |  OS: ${Platform.operatingSystem}',
      );
      sink.writeln('WorkDir: ${dir.path}');
      sink.writeln('══════════════════════════════════════════════════');
      return AppLogger._(sink, logFile.path);
    } catch (_) {
      // Log dosyası açılamazsa işleme devam et.
      return AppLogger._(null, '');
    }
  }

  void write(String message) {
    _sink?.writeln('[${DateTime.now().toIso8601String()}] $message');
  }

  Future<void> flush() async => _sink?.flush();

  Future<void> close() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
