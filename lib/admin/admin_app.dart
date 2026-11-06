import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import '../models/catalog.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../ui/app_theme.dart';
import '../ui/format.dart';
import 'admin_app_list.dart';
import 'admin_config.dart';
import 'admin_dependencies.dart';
import 'admin_downloads.dart';
import 'admin_server_dialog.dart';
import 'catalog_doc.dart';
import 'publisher.dart';
import 'ssh_client.dart';

/// `--admin` ile açılan yönetim ekranı. Solda katalogdaki uygulamalar (arama +
/// kategori süzgeci), sağda seçili uygulama için iki sekme:
/// **Bilgiler** (yalnızca catalog.json'u günceller) ve **Yayın** (klasör seç →
/// manifest üret → SCP ile yükle → catalog.json'u güncelle).
class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Codenfast Yayın Yönetimi',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const AdminScreen(),
  );
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

enum _Section { info, publish }

class _AdminScreenState extends State<AdminScreen> {
  static final _inputStyle = GoogleFonts.inter(fontSize: 13.5, color: Colors.white);
  static final _idPattern = RegExp(r'^[A-Za-z0-9._-]+$');

  Directory? _baseDir;
  AdminConfig _config = AdminConfig();

  // Bilgiler
  final _appId = TextEditingController();
  final _appName = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _logoUrl = TextEditingController();
  final _android = TextEditingController();
  final _ios = TextEditingController();
  List<String> _requires = [];

  // Yayın
  final _folder = TextEditingController();
  final _version = TextEditingController();
  final _ignore = TextEditingController();
  final _variantId = TextEditingController(text: 'standard');
  final _variantName = TextEditingController(text: 'Standart');
  final _exe = TextEditingController();
  final _args = TextEditingController();
  final _setupFile = TextEditingController();
  final _displayName = TextEditingController();
  final _setupArgs = TextEditingController();
  String _instType = 'portable'; // portable | msi | inno (yalnızca Windows)
  String _os = switch (UpdateService.currentOs()) {
    'windows' => 'windows',
    'macos' => 'macos',
    _ => 'linux',
  };

  CatalogDoc? _catalog;
  String? _selectedId;
  bool _creating = false;
  List<String> _baseline = const [];
  _Section _section = _Section.info;
  PublishPlan? _plan;
  final _log = <String>[];
  bool _busy = false;

  List<TextEditingController> get _all => [
    _appId,
    _appName,
    _category,
    _description,
    _logoUrl,
    _android,
    _ios,
    _folder,
    _version,
    _ignore,
    _variantId,
    _variantName,
    _exe,
    _args,
    _setupFile,
    _displayName,
    _setupArgs,
  ];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    _baseDir = await getApplicationSupportDirectory();
    _config = await AdminConfig.load(_baseDir!);
    if (!mounted) return;
    if (_config.validate().isEmpty) {
      await _fetchCatalog();
    } else {
      await _editServer();
    }
  }

  Publisher get _publisher => Publisher(_config, SshClient(_config));

  // ── Form ⇄ katalog ─────────────────────────────────────────────────────────

  List<String> _metaValues() => [
    _appName.text,
    _category.text,
    _description.text,
    _logoUrl.text,
    _android.text,
    _ios.text,
    _requires.join(','),
  ].map((s) => s.trim()).toList();

  bool get _metaDirty => _creating || !listEquals(_metaValues(), _baseline);

  AppMeta get _meta => AppMeta(
    name: _appName.text.trim().isEmpty ? _appId.text.trim() : _appName.text.trim(),
    category: _category.text,
    description: _description.text,
    logoUrl: _logoUrl.text,
    android: _android.text,
    ios: _ios.text,
    requires: _requires,
  );

  void _loadApp(Map<String, dynamic> a) {
    final m = (a['mobile'] as Map?) ?? const {};
    _appId.text = a['id'] as String;
    _appName.text = (a['name'] as String?) ?? '';
    _category.text = (a['category'] as String?) ?? '';
    _description.text = (a['description'] as String?) ?? '';
    _logoUrl.text = (a['logoUrl'] as String?) ?? '';
    _android.text = (m['android'] as String?) ?? '';
    _ios.text = (m['ios'] as String?) ?? '';
    _requires = [...((a['requires'] as List?) ?? const []).cast<String>()];
    _baseline = _metaValues();
    _resetPublishForm(a);
  }

  void _resetPublishForm(Map<String, dynamic>? a) {
    _plan = null;
    _folder.clear();
    _version.clear();
    _ignore.clear();
    final variants = ((a?['variants'] as List?) ?? const []).cast<Map<String, dynamic>>();
    if (variants.isEmpty) {
      _variantId.text = 'standard';
      _variantName.text = 'Standart';
      _exe.clear();
      _args.clear();
      _loadInstaller(null);
    } else {
      _loadVariant(variants.first);
    }
  }

  void _loadVariant(Map<String, dynamic> v) {
    _variantId.text = v['id'] as String;
    _variantName.text = (v['name'] as String?) ?? '';
    final target = (v['desktop'] as Map?)?[_os] as Map?;
    final launch = target?['launch'] as Map?;
    _exe.text = launch?['exe'] as String? ?? '';
    _args.text = ((launch?['args'] as List?) ?? const []).join('\n');
    _loadInstaller(target?['installer'] as Map?);
  }

  void _loadInstaller(Map? installer) {
    _instType = _os == 'windows' ? (installer?['type'] as String? ?? 'portable') : 'portable';
    _setupFile.text = installer?['file'] as String? ?? '';
    _displayName.text = installer?['displayName'] as String? ?? '';
    _setupArgs.text = ((installer?['args'] as List?) ?? const []).join('\n');
  }

  Future<bool> _confirmDiscard() async {
    if (!_metaDirty || (_creating && _appId.text.isEmpty && _appName.text.isEmpty)) return true;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Kaydedilmemiş değişiklikler'),
            content: const Text('Bu uygulamadaki değişiklikler kaybolacak. Devam edilsin mi?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('DEVAM')),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _select(String id) async {
    if (id == _selectedId && !_creating) return;
    if (!await _confirmDiscard()) return;
    final a = _catalog?.app(id);
    if (a == null) return;
    setState(() {
      _selectedId = id;
      _creating = false;
      _loadApp(a);
    });
  }

  Future<void> _newApp() async {
    if (!await _confirmDiscard()) return;
    setState(() {
      _selectedId = null;
      _creating = true;
      for (final c in [_appId, _appName, _category, _description, _logoUrl, _android, _ios]) {
        c.clear();
      }
      _requires = [];
      _baseline = _metaValues();
      _resetPublishForm(null);
      _section = _Section.info;
    });
  }

  // ── İşler ──────────────────────────────────────────────────────────────────

  void _say(String line) {
    if (mounted) setState(() => _log.add(line));
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      _say('HATA: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editServer() async {
    final result = await showServerDialog(context, _config, onTest: (c) => SshClient(c).test());
    if (result == null) return;
    _config = result;
    await _config.save(_baseDir!);
    _say('Sunucu ayarları kaydedildi.');
    await _fetchCatalog();
  }

  Future<void> _fetchCatalog() => _run(() async {
    final errors = _config.validate();
    if (errors.isNotEmpty) throw Exception('Sunucu ayarları eksik: ${errors.join(' ')}');
    _say('Katalog çekiliyor...');
    final r = await _publisher.fetchCatalog();
    _applyCatalog(r.doc);
    _say(
      r.existed
          ? '✓ Katalog alındı: ${r.doc.apps.length} uygulama.'
          : 'Sunucuda katalog yok; ilk kayıtta oluşturulacak.',
    );
  });

  /// Yeni kataloğu yükler; seçili uygulama varsa formu (kaydedilmiş haliyle) yeniler.
  void _applyCatalog(CatalogDoc doc, {String? select}) {
    if (!mounted) return;
    setState(() {
      _catalog = doc;
      final id = select ?? (_creating ? null : _selectedId);
      final a = id == null ? null : doc.app(id);
      if (a != null) {
        _selectedId = id;
        _creating = false;
        _loadApp(a);
      } else if (!_creating) {
        _selectedId = null;
        _baseline = const [];
      }
    });
  }

  Future<void> _saveMeta() async {
    final id = _appId.text.trim();
    if (!_idPattern.hasMatch(id)) {
      _say('HATA: Uygulama kimliği yalnızca A-Z a-z 0-9 . _ - içerebilir.');
      return;
    }
    if (_creating && _catalog?.app(id) != null) {
      _say('HATA: "$id" kimliği katalogda zaten var.');
      return;
    }
    final m = _meta;
    await _run(() async {
      await _publisher.updateCatalog((doc) {
        doc.upsertApp(
          id: id,
          name: m.name,
          category: m.category,
          description: m.description,
          logoUrl: m.logoUrl,
          android: m.android,
          ios: m.ios,
        );
        doc.setRequires(id, _requires);
      }, _say);
      _applyCatalog((await _publisher.fetchCatalog()).doc, select: id);
    });
  }

  Future<void> _deleteApp() async {
    final id = _selectedId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"$id" katalogdan silinsin mi?'),
        content: const Text(
          'Uygulama katalogdan çıkar ve kullanıcılar artık görmez. '
          'Sunucudaki dosyalar silinmez. Eski katalog catalog.json.bak olarak saklanır.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SİL')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await _publisher.updateCatalog((doc) => doc.removeApp(id), _say);
      setState(() {
        _selectedId = null;
        _creating = false;
        _baseline = const [];
      });
      _applyCatalog((await _publisher.fetchCatalog()).doc);
    });
  }

  PublishRequest get _request => PublishRequest(
    sourceDir: Directory(_folder.text.trim()),
    appId: _appId.text.trim(),
    variantId: _variantId.text.trim(),
    variantName: _variantName.text.trim().isEmpty ? _variantId.text.trim() : _variantName.text.trim(),
    os: _os,
    version: _version.text,
    ignore: _ignore.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    meta: _meta,
    launchExe: _exe.text.trim(),
    launchArgs: _args.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    installer: _os == 'windows' && _instType != 'portable'
        ? InstallerSpec(
            type: _instType,
            file: _setupFile.text.trim(),
            displayName: _displayName.text.trim(),
            args: _setupArgs.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          )
        : null,
  );

  Future<void> _openDependencies() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          AdminDependenciesPage(publisher: _publisher, catalog: _catalog!, onCatalog: (doc) => _applyCatalog(doc)),
    ),
  );

  Future<void> _openDownloads() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          AdminDownloadsPage(publisher: _publisher, catalog: _catalog!, onCatalog: (doc) => _applyCatalog(doc)),
    ),
  );

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) setState(() => _folder.text = path);
  }

  Future<void> _scan() async {
    if (!_idPattern.hasMatch(_appId.text.trim())) {
      _say('HATA: Önce "Bilgiler" sekmesinde geçerli bir uygulama kimliği girin.');
      return;
    }
    await _run(() async {
      _say('Taranıyor: ${_folder.text.trim()}');
      final plan = await _publisher.prepare(_request);
      setState(() => _plan = plan);
      if (plan.problems.isNotEmpty) {
        for (final p in plan.problems) {
          _say('⚠ $p');
        }
      } else {
        _say(
          '✓ ${plan.manifest.files.length} dosya, ${formatBytes(plan.manifest.totalSize)} '
          '(${plan.manifest.ignored} yoksayıldı).',
        );
      }
    });
  }

  Future<void> _publish() async {
    final plan = _plan!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Yayınlansın mı?'),
        content: Text(
          '${plan.manifest.files.length} dosya (${formatBytes(plan.manifest.totalSize)}) yüklenecek.\n\n'
          'Sunucu: ${_config.user}@${_config.host}\n'
          'Hedef: ${plan.remoteDir}\n'
          'Manifest: ${plan.manifestUrl}\n\n'
          'catalog.json güncellenecek (eskisi catalog.json.bak olarak saklanır).'
          '${_metaDirty ? '\nBilgiler sekmesindeki değişiklikler de birlikte kaydedilecek.' : ''}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('YAYINLA')),
        ],
      ),
    );
    if (ok != true) return;
    final id = _appId.text.trim();
    await _run(() async {
      await _publisher.publish(_request, plan, _say);
      setState(() => _plan = null);
      _applyCatalog((await _publisher.fetchCatalog()).doc, select: id);
    });
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasSelection = _creating || _selectedId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yayın Yönetimi'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          IconButton(
            tooltip: 'Katalogu yenile',
            onPressed: _busy ? null : _fetchCatalog,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'İşletim sistemleri (ISO)',
            onPressed: _busy || _catalog == null ? null : _openDownloads,
            icon: const Icon(Icons.album_outlined),
          ),
          IconButton(
            tooltip: 'Bağımlılıklar (VC++ Redist, DirectX...)',
            onPressed: _busy || _catalog == null ? null : _openDependencies,
            icon: const Icon(Icons.extension_outlined),
          ),
          IconButton(
            tooltip: 'Sunucu ayarları',
            onPressed: _busy ? null : _editServer,
            icon: const Icon(Icons.dns_outlined),
          ),
        ],
      ),
      body: CodenfastTheme().getBody(
        Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: Material(
                      color: const Color(0xFF13161E),
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: AdminAppList(
                        apps: _catalog?.apps ?? const [],
                        selectedId: _selectedId,
                        creating: _creating,
                        onSelect: _select,
                        onNew: _newApp,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: hasSelection
                        ? _detail()
                        : const Center(
                            child: Text(
                              'Soldan bir uygulama seçin veya "Yeni" ile ekleyin.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            if (_log.isNotEmpty) _logPanel(),
          ],
        ),
      ),
    );
  }

  Widget _detail() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _creating ? 'Yeni uygulama' : (_appName.text.isEmpty ? _appId.text : _appName.text),
                style: GoogleFonts.inter(fontSize: 20, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SegmentedButton<_Section>(
              showSelectedIcon: false,
              selected: {_section},
              onSelectionChanged: (s) => setState(() => _section = s.first),
              segments: [
                ButtonSegment(value: _Section.info, label: Text(_metaDirty ? 'Bilgiler •' : 'Bilgiler')),
                const ButtonSegment(value: _Section.publish, label: Text('Yayın')),
              ],
            ),
          ],
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _section == _Section.info ? _infoTab() : _publishTab(),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _infoTab() {
    final variants = ((_catalog?.app(_selectedId ?? '')?['variants'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row([
          _f(
            'Uygulama kimliği (id)',
            _appId,
            hint: 'flykobi',
            enabled: _creating,
            helper: _creating ? 'Sonradan değiştirilemez.' : null,
          ),
          _f('Ad', _appName, flex: 2, onChanged: _touchMeta),
          _f('Kategori', _category, onChanged: _touchMeta),
        ]),
        _row([_f('Açıklama', _description, maxLines: 4, onChanged: _touchMeta)]),
        _row([_f('Logo URL (png/svg)', _logoUrl, onChanged: _touchMeta)]),
        _row([
          _f('Play Store linki', _android, onChanged: _touchMeta),
          _f('App Store linki', _ios, onChanged: _touchMeta),
        ]),
        if ((_catalog?.dependencies ?? const []).isNotEmpty) ...[
          Text(
            'Gerekli bağımlılıklar (uygulamadan önce, eksikse kurulur)',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF00E5FF)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final d in _catalog!.dependencies)
                FilterChip(
                  label: Text((d['name'] as String?) ?? d['id'] as String),
                  selected: _requires.contains(d['id']),
                  onSelected: (on) => setState(() {
                    on ? _requires.add(d['id'] as String) : _requires.remove(d['id']);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy || !_metaDirty ? null : _saveMeta,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(_creating ? 'Kataloğa ekle' : 'Katalogu güncelle'),
            ),
            if (!_creating && _metaDirty)
              OutlinedButton(
                onPressed: _busy ? null : () => setState(() => _loadApp(_catalog!.app(_selectedId!)!)),
                child: const Text('Değişiklikleri geri al'),
              ),
            if (!_creating)
              OutlinedButton.icon(
                onPressed: _busy ? null : _deleteApp,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Katalogdan sil'),
              ),
          ],
        ),
        if (!_creating) ...[
          const SizedBox(height: 24),
          Text('Sürümler / varyantlar', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF00E5FF))),
          const SizedBox(height: 8),
          if (variants.isEmpty)
            const Text(
              'Henüz masaüstü sürümü yok (yalnızca mağaza linki). "Yayın" sekmesinden eklenir.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          for (final v in variants)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${v['id']} · ${((v['desktop'] as Map?) ?? const {}).keys.join(', ')}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ],
    );
  }

  Widget _publishTab() {
    final plan = _plan;
    final canPublish = plan != null && plan.problems.isEmpty && !_busy;
    final variants = ((_catalog?.app(_selectedId ?? '')?['variants'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_creating)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Bu uygulama henüz katalogda yok; yayınlayınca "Bilgiler" sekmesindekilerle birlikte eklenir.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        _row([
          _f('Dosyaların bulunduğu klasör', _folder, flex: 4, onChanged: _touchPlan),
          OutlinedButton(onPressed: _busy ? null : _pickFolder, child: const Text('Gözat')),
        ]),
        _row([
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _os,
              style: _inputStyle,
              decoration: const InputDecoration(labelText: 'İşletim sistemi', isDense: true),
              dropdownColor: const Color(0xFF1B1F2B),
              items: const [
                DropdownMenuItem(value: 'windows', child: Text('Windows')),
                DropdownMenuItem(value: 'linux', child: Text('Linux')),
                DropdownMenuItem(value: 'macos', child: Text('macOS')),
              ],
              onChanged: (v) => setState(() {
                _os = v!;
                _plan = null;
                final current = _catalog?.variant(_appId.text.trim(), _variantId.text.trim());
                if (current != null) _loadVariant(current);
              }),
            ),
          ),
          _f('Sürüm (isteğe bağlı)', _version, onChanged: _touchPlan),
          _f('Yoksay (virgülle)', _ignore, hint: '*.log, secrets/', flex: 2, onChanged: _touchPlan),
        ]),
        if (variants.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Varyant:', style: TextStyle(fontSize: 11)),
                for (final v in variants)
                  ActionChip(
                    avatar: const Icon(Icons.tune, size: 14),
                    label: Text(v['id'] as String),
                    onPressed: () => setState(() {
                      _loadVariant(v);
                      _plan = null;
                    }),
                  ),
              ],
            ),
          ),
        _row([
          _f('Varyant kimliği', _variantId, onChanged: _touchPlan),
          _f('Varyant adı', _variantName, onChanged: _touchPlan),
        ]),
        if (_os == 'windows') ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Kurulum şekli', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF00E5FF))),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'portable', label: Text('Portable (dosya senkronu)')),
                ButtonSegment(value: 'msi', label: Text('MSI')),
                ButtonSegment(value: 'inno', label: Text('Inno Setup')),
              ],
              selected: {_instType},
              onSelectionChanged: (v) => setState(() {
                _instType = v.first;
                _plan = null;
              }),
            ),
          ),
          if (_instType != 'portable') ...[
            _row([
              _f(
                'Kurucu dosya (klasöre göre yol)',
                _setupFile,
                flex: 3,
                hint: _instType == 'msi' ? 'Flykobi.msi' : 'FlykobiSetup.exe',
              ),
              if (plan != null && plan.manifest.files.isNotEmpty)
                PopupMenuButton<String>(
                  tooltip: 'Taranan dosyalardan seç',
                  icon: const Icon(Icons.list),
                  itemBuilder: (_) => [
                    for (final f in plan.manifest.files.take(200)) PopupMenuItem(value: f.rel, child: Text(f.rel)),
                  ],
                  onSelected: (v) => setState(() => _setupFile.text = v),
                ),
            ]),
            _row([
              _f(
                'Kurulu program adı (Programlar ve Özellikler)',
                _displayName,
                flex: 3,
                hint: 'Flykobi',
                helper:
                    'Kurulu mu / sürüm / kaldırma buna bakar (önek eşleşir). MSI ürün kodu sürümle değiştiği için ad kullanılır.',
              ),
            ]),
            _row([
              _f(
                'Ek kurucu parametreleri (her satıra bir tane)',
                _setupArgs,
                maxLines: 2,
                hint: _instType == 'msi' ? 'ALLUSERS=1' : '/TASKS=desktopicon',
                helper:
                    'Sessiz parametreler otomatik eklenir: ${_instType == 'msi' ? '/qn /norestart' : '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART'}',
              ),
            ]),
          ],
        ],
        _row([
          _f(
            _os == 'windows' && _instType != 'portable'
                ? 'Kurulu uygulamanın yolu'
                : 'Çalıştırılacak dosya (klasöre göre yol)',
            _exe,
            flex: 3,
            hint: _os == 'windows' && _instType != 'portable' ? r'%ProgramFiles%\Flykobi\flykobi.exe' : 'bin/uygulama',
            helper: _os == 'windows' && _instType != 'portable'
                ? 'Ortam değişkenleri açılır; göreliyse kayıt defterindeki kurulum klasörüne göre çözülür.'
                : null,
          ),
          if (_instType == 'portable' && plan != null && plan.manifest.files.isNotEmpty)
            PopupMenuButton<String>(
              tooltip: 'Taranan dosyalardan seç',
              icon: const Icon(Icons.list),
              itemBuilder: (_) => [
                for (final f in plan.manifest.files.take(200)) PopupMenuItem(value: f.rel, child: Text(f.rel)),
              ],
              onSelected: (v) => setState(() => _exe.text = v),
            ),
        ]),
        _row([_f('Argümanlar (her satıra bir tane)', _args, maxLines: 3)]),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Tara ve önizle'),
            ),
            FilledButton.icon(
              onPressed: canPublish ? _publish : null,
              icon: const Icon(Icons.cloud_upload_outlined, size: 16),
              label: const Text('Sunucuya yükle ve yayınla'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _logPanel() => Container(
    height: 130,
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
    color: const Color(0xFF0B0D12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SingleChildScrollView(
            reverse: true,
            child: SelectableText(
              _log.join('\n'),
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFCCDDEE)),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Günlüğü temizle',
          iconSize: 16,
          onPressed: () => setState(_log.clear),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  void _touchMeta(String _) => setState(() {});
  void _touchPlan(String _) => setState(() => _plan = null);

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), children[i]],
      ],
    ),
  );

  Widget _f(
    String label,
    TextEditingController c, {
    String? hint,
    String? helper,
    int maxLines = 1,
    int flex = 1,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) => Expanded(
    flex: flex,
    child: TextField(
      controller: c,
      enabled: enabled,
      maxLines: maxLines,
      style: _inputStyle,
      onChanged: onChanged ?? _touchPlan,
      decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, isDense: true),
    ),
  );
}
