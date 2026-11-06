import 'dart:io';

import 'package:codenfast_updater/models/catalog.dart';
import 'package:codenfast_updater/services/app_logger.dart';
import 'package:codenfast_updater/services/download_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _data = List<int>.generate(10000, (i) => i % 251);
final _sha = sha256.convert(_data).toString();

DownloadFile _file({String? sha, int? size}) => DownloadFile(
  name: 'Desktop',
  fileName: 'demo.iso',
  url: 'https://example.com/demo.iso',
  sha256: sha ?? _sha,
  size: size ?? _data.length,
);

void main() {
  Directory? tmp;
  late List<String?> ranges;

  Future<DownloadService> build(Future<http.StreamedResponse> Function(http.BaseRequest) handler) async {
    tmp = await Directory.systemTemp.createTemp('dl_test');
    ranges = [];
    return DownloadService(
      directory: Directory('${tmp!.path}/Downloads'),
      log: await AppLogger.open(tmp!),
      client: MockClient.streaming((req, _) {
        ranges.add(req.headers['Range']);
        return handler(req);
      }),
    );
  }

  http.StreamedResponse full() => http.StreamedResponse(Stream.value(_data), 200, contentLength: _data.length);

  tearDown(() async {
    await tmp?.delete(recursive: true);
    tmp = null;
  });

  test('downloads, verifies sha256 and leaves no .part', () async {
    final s = await build((_) async => full());
    final seen = <int>[];
    final f = await s.download(_file(), onProgress: (r, t) => seen.add(r));
    expect(await f.readAsBytes(), _data);
    expect(File('${f.path}.part').existsSync(), isFalse);
    expect(seen.last, _data.length);
    expect(await s.looksDownloaded(_file()), isTrue);
  });

  test('resumes a partial download with a Range request', () async {
    final s = await build((req) async {
      final from = int.parse(req.headers['Range']!.replaceAll(RegExp(r'[^0-9]'), ''));
      return http.StreamedResponse(Stream.value(_data.sublist(from)), 206, contentLength: _data.length - from);
    });
    await Directory('${tmp!.path}/Downloads').create(recursive: true);
    await File('${tmp!.path}/Downloads/demo.iso.part').writeAsBytes(_data.sublist(0, 4000));
    final f = await s.download(_file(), onProgress: (_, _) {});
    expect(ranges.single, 'bytes=4000-');
    expect(await f.readAsBytes(), _data);
  });

  test('server ignoring Range (200) restarts from scratch', () async {
    final s = await build((_) async => full());
    await Directory('${tmp!.path}/Downloads').create(recursive: true);
    await File('${tmp!.path}/Downloads/demo.iso.part').writeAsBytes([1, 2, 3]);
    final f = await s.download(_file(), onProgress: (_, _) {});
    expect(await f.readAsBytes(), _data);
  });

  test('sha256 mismatch deletes the file and fails', () async {
    final s = await build((_) async => full());
    await expectLater(
      s.download(_file(sha: 'a' * 64), onProgress: (_, _) {}),
      throwsA(predicate((e) => '$e'.contains('sha256'))),
    );
    expect(Directory('${tmp!.path}/Downloads').listSync(), isEmpty);
  });

  test('cancel keeps the .part so the next attempt can resume', () async {
    final s = await build(
      (_) async => http.StreamedResponse(
        Stream.fromIterable([_data.sublist(0, 3000), _data.sublist(3000)]),
        200,
        contentLength: _data.length,
      ),
    );
    var cancel = false;
    await expectLater(
      s.download(_file(), onProgress: (_, _) => cancel = true, isCancelled: () => cancel),
      throwsA(isA<DownloadCancelled>()),
    );
    final part = File('${tmp!.path}/Downloads/demo.iso.part');
    expect(part.existsSync(), isTrue);
    expect(part.lengthSync(), 3000);
    expect(File('${tmp!.path}/Downloads/demo.iso').existsSync(), isFalse);
  });

  test('already downloaded and valid file is not fetched again', () async {
    final s = await build((_) async => throw StateError('ağa çıkılmamalı'));
    await Directory('${tmp!.path}/Downloads').create(recursive: true);
    await File('${tmp!.path}/Downloads/demo.iso').writeAsBytes(_data);
    await s.download(_file(), onProgress: (_, _) {});
    expect(ranges, isEmpty);
  });

  test('non-https url is rejected', () async {
    final s = await build((_) async => full());
    final bad = DownloadFile(name: 'x', fileName: 'x.iso', url: 'http://evil.example/x.iso', sha256: _sha);
    await expectLater(s.download(bad, onProgress: (_, _) {}), throwsException);
  });

  test('catalog parses downloads and rejects bad sha256 / unsafe file names', () {
    Map<String, dynamic> cat(Map<String, dynamic> file) => {
      'apps': [],
      'downloads': [
        {
          'id': 'ubuntu',
          'name': 'Ubuntu',
          'version': '26.04',
          'files': [file],
        },
      ],
    };
    final ok = Catalog.fromJson(
      cat({'fileName': 'u.iso', 'url': 'https://x/u.iso', 'sha256': _sha.toUpperCase(), 'size': 5}),
    );
    expect(ok.downloads.single.files.single.sha256, _sha);
    expect(
      () => Catalog.fromJson(cat({'fileName': 'u.iso', 'url': 'https://x', 'sha256': 'abc'})),
      throwsFormatException,
    );
    expect(
      () => Catalog.fromJson(cat({'fileName': '../u.iso', 'url': 'https://x', 'sha256': _sha})),
      throwsFormatException,
    );
    expect(Catalog.fromJson({'apps': []}).downloads, isEmpty);
  });
}
