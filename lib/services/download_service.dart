import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/catalog.dart';
import 'app_logger.dart';
import 'url_guard.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();

  @override
  String toString() => 'İndirme durduruldu; devam etmek için tekrar İndir\'e basın.';
}

typedef DownloadProgress = void Function(int received, int? total);

/// Büyük dosyaları (ISO) indirir: yarım kalan `.part` dosyasından devam eder,
/// sha256 doğrulamasından geçmeden son adı vermez.
class DownloadService {
  final Directory directory;
  final AppLogger log;
  final http.Client _client;

  DownloadService({required this.directory, required this.log, http.Client? client})
    : _client = client ?? http.Client();

  File targetOf(DownloadFile f) => File('${directory.path}/${f.fileName}');

  /// Hızlı denetim (boyut): dosya daha önce indirilmiş görünüyor mu?
  Future<bool> looksDownloaded(DownloadFile f) async {
    final file = targetOf(f);
    return await file.exists() && (f.size == null || await file.length() == f.size);
  }

  Future<File> download(DownloadFile f, {required DownloadProgress onProgress, bool Function()? isCancelled}) async {
    await directory.create(recursive: true);
    final target = targetOf(f);
    final part = File('${target.path}.part');

    if (await looksDownloaded(f) && await _sha256Of(target) == f.sha256) {
      log.write('Zaten indirilmiş ve doğru: ${target.path}');
      return target;
    }

    var offset = await part.exists() ? await part.length() : 0;
    var response = await _open(f, offset);
    if (response.statusCode == 416) {
      // Yarım dosya sunucudakiyle uyuşmuyor; baştan başla.
      await response.stream.drain<void>();
      await part.delete();
      offset = 0;
      response = await _open(f, 0);
    }
    final resumed = response.statusCode == 206 && offset > 0;
    if (response.statusCode != 200 && !resumed) {
      await response.stream.drain<void>();
      throw Exception('${f.fileName} indirilemedi (HTTP ${response.statusCode}).');
    }
    if (!resumed) offset = 0; // sunucu Range'i yok saydı: baştan yazılır
    final total = response.contentLength == null ? f.size : response.contentLength! + offset;

    log.write('İndiriliyor: ${f.url} → ${target.path} (${resumed ? 'devam, $offset bayttan' : 'baştan'})');
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var received = offset;
    try {
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        if (isCancelled?.call() ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close(); // .part kalır: iptal/kopmada devam edilebilir
    }

    if (f.size != null && await part.length() != f.size) {
      final got = await part.length();
      await part.delete();
      throw Exception('${f.fileName} boyut uyuşmazlığı. Beklenen: ${f.size}, Alınan: $got');
    }
    if (await _sha256Of(part) != f.sha256) {
      await part.delete();
      throw Exception('${f.fileName} sağlama toplamı (sha256) uyuşmuyor; dosya silindi, tekrar deneyin.');
    }
    await part.rename(target.path);
    log.write('İndirme tamamlandı: ${target.path}');
    return target;
  }

  Future<http.StreamedResponse> _open(DownloadFile f, int offset) {
    final request = http.Request('GET', requireSecureUri(f.url));
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    return _client.send(request).timeout(const Duration(seconds: 30));
  }

  Future<String> _sha256Of(File file) async => (await sha256.bind(file.openRead()).first).toString();
}
