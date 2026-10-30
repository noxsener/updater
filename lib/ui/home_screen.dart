import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../models/installed_store.dart';
import '../services/app_logger.dart';
import '../services/catalog_service.dart';
import '../services/shortcut_service.dart';
import '../services/store_controller.dart';
import '../services/update_service.dart';
import '../theme.dart';
import 'widgets/app_card.dart';

enum _Tab { discover, installed, updates }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  UpdateService? _service;
  StoreController? _store;
  String? _error;

  _Tab _tab = _Tab.discover;
  String _query = '';
  String? _category;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      if (_service == null) {
        final baseDir = await getApplicationSupportDirectory();
        await baseDir.create(recursive: true);
        final log = await AppLogger.open(baseDir);
        _service = UpdateService(
          baseDir: baseDir,
          store: await InstalledStore.load(baseDir),
          log: log,
          shortcuts: UpdateService.isDesktop ? ShortcutService(log) : null,
        );
      }
      final catalog = await CatalogService().fetch();
      final store = StoreController(catalog, _service!);
      _store?.dispose();
      if (!mounted) return;
      setState(() => _store = store);
      store.refreshAll(); // açılışta toplu güncelleme kontrolü
    } catch (e) {
      _service?.log.write('Katalog hatası: $e');
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _openLogFolder(String logPath) {
    final dir = File(logPath).parent.path;
    Process.run(
      Platform.isWindows ? 'explorer' : (Platform.isMacOS ? 'open' : 'xdg-open'),
      [dir],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CodenfastTheme().getBody(
        SafeArea(
          child: Column(
            children: [
              _header(),
              Expanded(child: _content()),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final store = _store;
    final desktop = UpdateService.isDesktop;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/codenfast_logo_transparent_2688_1242.webp',
                height: 40,
                errorBuilder: (_, _, _) => const SizedBox(height: 40),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Uygulama ara...',
                    prefixIcon: Icon(Icons.search, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
            ],
          ),
          if (store != null && desktop) ...[
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: store,
              builder: (context, _) => Row(
                children: [
                  SegmentedButton<_Tab>(
                    showSelectedIcon: false,
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                    segments: [
                      const ButtonSegment(value: _Tab.discover, label: Text('Keşfet')),
                      const ButtonSegment(value: _Tab.installed, label: Text('Kurulu')),
                      ButtonSegment(
                        value: _Tab.updates,
                        label: Badge(
                          isLabelVisible: store.updateCount > 0,
                          label: Text('${store.updateCount}'),
                          offset: const Offset(14, -8),
                          child: const Text('Güncellemeler'),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_tab == _Tab.updates) ...[
                    IconButton(
                      tooltip: 'Güncellemeleri denetle',
                      onPressed: store.refreshAll,
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton(
                      onPressed: store.updateCount > 0 && !store.updatingAll ? store.updateAll : null,
                      child: Text(store.updatingAll ? 'Güncelleniyor...' : 'Tümünü güncelle'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _content() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFF5370))),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Yeniden dene')),
          ],
        ),
      );
    }
    final store = _store;
    if (store == null) return const Center(child: CircularProgressIndicator());

    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final tab = UpdateService.isDesktop ? _tab : _Tab.discover;
        final visible = store.apps.where((c) {
          if (tab == _Tab.installed && !c.isInstalled) return false;
          if (tab == _Tab.updates && !c.hasUpdate) return false;
          if (tab == _Tab.discover && _category != null && c.app.category != _category) return false;
          return _query.isEmpty ||
              '${c.app.name} ${c.app.description} ${c.app.category ?? ''}'.toLowerCase().contains(_query);
        }).toList();

        return Column(
          children: [
            if (tab == _Tab.discover && store.categories.isNotEmpty) _categoryChips(store),
            Expanded(
              child: visible.isEmpty
                  ? Center(
                      child: Text(
                        switch (tab) {
                          _Tab.installed => 'Kurulu uygulama yok.',
                          _Tab.updates => 'Tüm uygulamalar güncel.',
                          _Tab.discover => 'Sonuç bulunamadı.',
                        },
                        style: const TextStyle(color: Color(0xFF7A8BAA)),
                      ),
                    )
                  : _grid(visible),
            ),
          ],
        );
      },
    );
  }

  Widget _categoryChips(StoreController store) => SizedBox(
    height: 44,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      children: [
        for (final cat in [null, ...store.categories])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(cat ?? 'Tümü'),
              selected: _category == cat,
              onSelected: (_) => setState(() => _category = cat),
            ),
          ),
      ],
    ),
  );

  Widget _grid(List<AppController> apps) => LayoutBuilder(
    builder: (context, c) {
      final columns = (c.maxWidth / 340).floor().clamp(1, 4);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: [
            for (final a in apps)
              SizedBox(
                width: (c.maxWidth - 32 - 16 * (columns - 1)) / columns,
                child: AppCard(key: ValueKey(a.app.id), c: a),
              ),
          ],
        ),
      );
    },
  );

  Widget _footer() {
    final logPath = _service?.log.path ?? '';
    if (logPath.isEmpty || !UpdateService.isDesktop) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              'Log: $logPath',
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: const Color(0xFF5A7A9A), fontSize: 10),
            ),
          ),
          IconButton(
            tooltip: 'Klasörde aç',
            iconSize: 14,
            color: const Color(0xFF00E5FF),
            icon: const Icon(Icons.folder_open_outlined),
            onPressed: () => _openLogFolder(logPath),
          ),
        ],
      ),
    );
  }
}
