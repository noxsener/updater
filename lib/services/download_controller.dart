import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/catalog.dart';
import 'download_service.dart';

enum DownloadState { idle, downloading, done, error }

/// "İşletim Sistemleri" sekmesindeki bir kaydın ekran durumu.
class DownloadController extends ChangeNotifier {
  final DownloadEntry entry;
  final DownloadService service;

  DownloadFile? file;
  DownloadState state = DownloadState.idle;
  int received = 0;
  int? total;
  String? error;
  File? saved;
  bool _cancel = false;

  DownloadController(this.entry, this.service) : file = entry.files.isEmpty ? null : entry.files.first {
    refreshStatus();
  }

  bool get busy => state == DownloadState.downloading;
  double? get progress => total == null || total == 0 ? null : (received / total!).clamp(0, 1).toDouble();

  void select(DownloadFile f) {
    if (busy) return;
    file = f;
    error = null;
    refreshStatus();
  }

  /// Seçili dosya daha önce indirilmişse "indirildi" göster.
  Future<void> refreshStatus() async {
    final f = file;
    if (f == null || busy) return;
    final done = await service.looksDownloaded(f);
    if (file != f || busy) return;
    state = done ? DownloadState.done : DownloadState.idle;
    saved = done ? service.targetOf(f) : null;
    notifyListeners();
  }

  Future<void> start() async {
    final f = file;
    if (f == null || busy) return;
    _cancel = false;
    state = DownloadState.downloading;
    error = null;
    received = 0;
    total = f.size;
    notifyListeners();
    try {
      saved = await service.download(
        f,
        isCancelled: () => _cancel,
        onProgress: (r, t) {
          received = r;
          total = t;
          notifyListeners();
        },
      );
      state = DownloadState.done;
    } on DownloadCancelled catch (e) {
      state = DownloadState.idle;
      error = e.toString();
    } catch (e) {
      service.log.write('HATA (${entry.id}): $e');
      state = DownloadState.error;
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      await service.log.flush();
      notifyListeners();
    }
  }

  /// Yarım dosya diskte kalır; sonraki İndir kaldığı yerden sürer.
  void cancel() => _cancel = true;

  /// Dosyayı dosya yöneticisinde gösterir.
  void reveal() {
    final path = saved?.path ?? file?.fileName;
    if (path == null) return;
    if (Platform.isWindows) {
      Process.run('explorer', ['/select,', path.replaceAll('/', '\\')]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', path]);
    } else {
      Process.run('xdg-open', [File(path).parent.path]);
    }
  }
}
