import 'package:flutter/foundation.dart';

import '../models/catalog.dart';
import 'download_controller.dart';
import 'download_service.dart';
import 'update_service.dart';

/// Tek bir ürünün (seçili varyantıyla) ekran durumu. Kartlar, detay sayfası ve
/// sekmeler aynı nesneyi dinler.
class AppController extends ChangeNotifier {
  final AppEntry app;
  final UpdateService service;
  final String os = UpdateService.currentOs();

  Variant? variant;
  AppInfo? info; // null: kontrol ediliyor
  bool busy = false;
  String message = '';
  double total = 0;
  double file = 0;
  String? error;
  int _generation = 0;


  AppController(this.app, this.service) {
    final v = app.variants;
    variant = v.isEmpty
        ? null
        : v.firstWhere(
            (x) => service.store.get(app.id, x.id) != null,
            orElse: () => v.first,
          );
  }

  DesktopTarget? get target => variant?.desktop[os];
  AppStatus? get status => info?.status;
  bool get isInstalled =>
      status == AppStatus.upToDate ||
      status == AppStatus.updateAvailable ||
      status == AppStatus.offline;
  bool get hasUpdate => status == AppStatus.updateAvailable;

  Future<void> refresh({bool needInfo = false}) async {
    final v = variant;
    if (!UpdateService.isDesktop || v == null || target == null) return;
    final gen = ++_generation;
    info = null;
    notifyListeners();
    final result = await service.inspect(app, v, os, needManifest: needInfo);
    if (gen != _generation) return; // başka bir yenileme/varyant seçimi geçti
    info = result;
    notifyListeners();
  }

  void selectVariant(Variant v, {bool needInfo = false}) {
    variant = v;
    error = null;
    refresh(needInfo: needInfo);
  }

  Future<void> install() async {
    final v = variant;
    if (v == null || busy) return;
    busy = true;
    error = null;
    total = 0;
    file = 0;
    notifyListeners();
    try {
      await service.install(app, v, os, (msg, t, f) {
        service.log.write(msg);
        message = msg;
        total = t;
        file = f;
        notifyListeners();
      });
      info = AppInfo(
        status: AppStatus.upToDate,
        installedVersion: service.store.get(app.id, v.id)?.version,
        availableVersion: info?.availableVersion,
        sizeBytes: info?.sizeBytes,
      );
    } catch (e) {
      service.log.write('HATA (${app.id}): $e');
      error = _clean(e);
    } finally {
      await service.log.flush();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> open() async {
    try {
      await service.launch(app, variant!, os);
    } catch (e) {
      error = _clean(e);
      notifyListeners();
    }
  }

  Future<void> uninstall() async {
    final v = variant;
    if (v == null || busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await service.uninstall(app, v);
      info = const AppInfo(status: AppStatus.notInstalled);
    } catch (e) {
      error = _clean(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');
}

class StoreController extends ChangeNotifier {
  final List<AppController> apps;
  final List<DownloadController> downloads;
  bool updatingAll = false;

  StoreController(Catalog catalog, UpdateService service, {DownloadService? downloadService})
    : apps = [for (final a in catalog.apps) AppController(a, service)],
      downloads = [
        if (downloadService != null) for (final d in catalog.downloads) DownloadController(d, downloadService),
      ] {
    for (final d in downloads) {
      d.addListener(notifyListeners);
    }
    for (final c in apps) {
      c.addListener(notifyListeners);
    }
  }

  List<String> get categories =>
      ({for (final c in apps) if (c.app.category != null) c.app.category!}.toList()..sort());

  int get updateCount => apps.where((c) => c.hasUpdate).length;

  Future<void> refreshAll() => Future.wait(apps.map((c) => c.refresh()));

  /// Güncellemeleri sırayla uygular (disk/ağ yükünü tek akışta tutar).
  Future<void> updateAll() async {
    if (updatingAll) return;
    updatingAll = true;
    notifyListeners();
    try {
      for (final c in apps.where((c) => c.hasUpdate && !c.busy).toList()) {
        await c.install();
      }
    } finally {
      updatingAll = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final d in downloads) {
      d.removeListener(notifyListeners);
      d.dispose();
    }
    for (final c in apps) {
      c.removeListener(notifyListeners);
      c.dispose();
    }
    super.dispose();
  }
}
