import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/update_service.dart';
import '../theme.dart';
import '../ui/format.dart';
import 'catalog_doc.dart';
import 'deb_fetcher.dart';
import 'installed_packages.dart';
import 'lib_scanner.dart';
import 'package_picker.dart';
import 'publisher.dart';

/// Ortak bağımlılıkları (VC++ Redist, DirectX...) yayınlar: klasör → manifest →
/// `<kök>/_deps/<id>/<os>/` → catalog.json'daki `dependencies`.
class AdminDependenciesPage extends StatefulWidget {
  final Publisher publisher;
  final CatalogDoc catalog;
  final ValueChanged<CatalogDoc> onCatalog;

  const AdminDependenciesPage({super.key, required this.publisher, required this.catalog, required this.onCatalog});

  @override
  State<AdminDependenciesPage> createState() => _AdminDependenciesPageState();
}

/// Bir işletim sisteminin sekmesindeki alanlar ve son tarama sonucu.
class _OsForm {
  final folder = TextEditingController();
  final version = TextEditingController();
  final ignore = TextEditingController();
  final exe = TextEditingController();
  final args = TextEditingController();
  final regKey = TextEditingController();
  final regValue = TextEditingController();
  final equals = TextEditingController();
  final file = TextEditingController();
  final apt = TextEditingController();
  PublishPlan? plan;

  List<TextEditingController> get all => [folder, version, ignore, exe, args, regKey, regValue, equals, file, apt];

  /// Katalogdaki hedeften doldurur; klasör/sürüm/yoksay yayın anına özgüdür, boşaltılır.
  void load(Map? target) {
    final run = target?['run'] as Map?;
    final detect = target?['detect'] as Map?;
    folder.clear();
    version.clear();
    ignore.clear();
    exe.text = (run?['exe'] as String?) ?? '';
    args.text = ((run?['args'] as List?) ?? const []).join('\n');
    regKey.text = (detect?['registryKey'] as String?) ?? '';
    regValue.text = (detect?['registryValue'] as String?) ?? '';
    equals.text = (detect?['equals']?.toString()) ?? '';
    file.text = (detect?['file'] as String?) ?? '';
    apt.text = (((target?['apt'] as Map?)?['packages'] as List?) ?? const []).join('\n');
    plan = null;
  }

  void dispose() {
    for (final c in all) {
      c.dispose();
    }
  }
}

class _AdminDependenciesPageState extends State<AdminDependenciesPage> {
  static final _inputStyle = GoogleFonts.inter(fontSize: 13.5, color: Colors.white);
  static final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  static const _oses = ['windows', 'linux', 'macos'];
  static const _osNames = {'windows': 'Windows', 'linux': 'Linux', 'macos': 'macOS'};

  final _id = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _image = TextEditingController(text: 'ubuntu:26.04');
  final _forms = {for (final os in _oses) os: _OsForm()};
  String _os = switch (UpdateService.currentOs()) {
    'macos' => 'macos',
    'linux' => 'linux',
    _ => 'windows',
  };

  late CatalogDoc _doc = widget.catalog;
  String? _selected;
  bool _creating = false;
  bool _busy = false;
  final _log = <String>[];

  _OsForm get _cur => _forms[_os]!;
  PublishPlan? get _plan => _cur.plan;

  @override
  void dispose() {
    for (final c in [_id, _name, _description, _image]) {
      c.dispose();
    }
    for (final f in _forms.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _say(String line) {
    if (mounted) setState(() => _log.add(line));
  }

  void _select(String id) {
    final d = _doc.dependency(id);
    if (d == null) return;
    setState(() {
      _selected = id;
      _creating = false;
      _id.text = id;
      _name.text = (d['name'] as String?) ?? '';
      _description.text = (d['description'] as String?) ?? '';
      for (final os in _oses) {
        _forms[os]!.load((d['desktop'] as Map?)?[os] as Map?);
      }
    });
  }

  /// Seçili bağımlılığın bu işletim sistemi için katalogda hedefi var mı?
  bool _defined(String os) {
    final d = _selected == null ? null : _doc.dependency(_selected!);
    return (d?['desktop'] as Map?)?[os] != null;
  }

  /// Linux'ta paket listesi doluysa apt bağımlılığıdır (kurucu/denetim alanları kullanılmaz).
  bool get _aptMode => _os == 'linux' && _cur.apt.text.trim().isNotEmpty;

  List<String> get _aptPackages => _cur.apt.text.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList();

  void _new() => setState(() {
    _selected = null;
    _creating = true;
    for (final c in [_id, _name, _description]) {
      c.clear();
    }
    for (final f in _forms.values) {
      f.load(null);
    }
  });

  PublishRequest get _request => PublishRequest(
    sourceDir: Directory(_expandHome(_cur.folder.text.trim())),
    appId: _id.text.trim(),
    variantId: 'dep',
    variantName: '',
    os: _os,
    version: _cur.version.text,
    ignore: _cur.ignore.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    meta: const AppMeta(name: ''),
    launchExe: _cur.exe.text.trim(),
    launchArgs: _cur.args.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
    dependency: DependencyMeta(
      name: _name.text.trim().isEmpty ? _id.text.trim() : _name.text.trim(),
      description: _description.text,
      registryKey: _os == 'windows' ? _cur.regKey.text : null,
      registryValue: _os == 'windows' ? _cur.regValue.text : null,
      equals: _os == 'windows' ? _cur.equals.text : null,
      file: _cur.file.text,
      aptPackages: _aptMode ? _aptPackages : null,
    ),
  );

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

  Future<void> _refresh({String? select}) async {
    final doc = (await widget.publisher.fetchCatalog()).doc;
    if (!mounted) return;
    widget.onCatalog(doc);
    setState(() => _doc = doc);
    if (select != null) _select(select);
  }

  /// Dart `~` işaretini açmaz; `~/debs` gibi yazılan yollar ana dizine çevrilir.
  static String _expandHome(String path) {
    if (path != '~' && !path.startsWith('~/')) return path;
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    return home == null ? path : home + path.substring(1);
  }

  Future<void> _pickFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) setState(() => _cur.folder.text = path);
  }

  Future<void> _scan() async {
    if (!_idPattern.hasMatch(_id.text.trim())) {
      _say('HATA: Bağımlılık kimliği yalnızca A-Z a-z 0-9 . _ - içerebilir.');
      return;
    }
    await _run(() async {
      final folder = _expandHome(_cur.folder.text.trim());
      _say('Taranıyor: $folder');
      if (_aptMode && await Directory(folder).exists()) {
        for (final (from, to) in await DebFetcher.sanitizeNames(Directory(folder))) {
          _say('Ad düzeltildi: $from → $to');
        }
      }
      final plan = await widget.publisher.prepare(_request);
      setState(() => _cur.plan = plan);
      if (plan.problems.isNotEmpty) {
        for (final p in plan.problems) {
          _say('⚠ $p');
        }
      } else {
        _say(
          '✓ ${plan.manifest.files.length} dosya, ${formatBytes(plan.manifest.totalSize)}. '
          'Şimdi "$_publishLabel" düğmesine basın.',
        );
      }
    });
  }

  Future<void> _publish() async {
    final plan = _plan!;
    final id = _id.text.trim();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bağımlılık yayınlansın mı?'),
        content: Text(
          '${plan.manifest.files.length} dosya (${formatBytes(plan.manifest.totalSize)}) yüklenecek.\n\n'
          'İşletim sistemi: ${_osNames[_os]}\nHedef: ${plan.remoteDir}\nManifest: ${plan.manifestUrl}\n\n'
          '${_aptMode ? 'İnternet yoksa bu .deb dosyaları indirilip dpkg -i ile kurulur; apt paket listesi de katalogda saklanır. ' : 'Bu bağımlılığı kullanan uygulamalar kurulumda bunu çalıştırır (Windows\'ta yönetici izni ister). '}'
          'catalog.json güncellenecek.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('YAYINLA')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.publisher.publish(_request, plan, _say);
      setState(() => _cur.plan = null);
      await _refresh(select: id);
    });
  }

  /// Docker'sız yol için, mevcut paket listesinden üretilen terminal komutunu gösterir.
  Future<void> _showTerminalCommand() {
    final script = DebFetcher.terminalScript(_aptPackages);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terminal komutu (Docker\'sız)'),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Kendi Debian/Ubuntu makinenizde çalıştırın. İnen .deb dosyalarını bu sayfada '
                '"Kurulum dosyalarının klasörü" alanına (~/debs) seçip yayınlayın.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFF0B0D12),
                child: SelectableText(script, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: script));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Komut panoya kopyalandı.')));
            },
            child: const Text('KOPYALA'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('KAPAT')),
        ],
      ),
    );
  }

  /// Uygulama klasöründeki ELF dosyalarını tarar; bulunan paketleri listeye ekler.
  Future<void> _scanApp() async {
    if (!Platform.isLinux) {
      _say('HATA: Uygulama taraması yalnızca Linux (Debian/Ubuntu) makinede çalışır (ldd ve dpkg gerekir).');
      return;
    }
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    final image = _image.text.trim();
    await _run(() async {
      _say('Taranıyor: $path');
      final r = await LibScanner().scan(Directory(path), image: image, log: _say);
      final merged = {..._aptPackages, ...r.packages}.toList()..sort();
      setState(() => _cur.apt.text = merged.join('\n'));
      _say('✓ ${r.scannedFiles} dosya tarandı, ${r.packages.length} paket bulundu${r.filtered ? '' : ' (süzülmedi)'}.');
      if (r.missing.isNotEmpty) {
        _say('⚠ Bu makinede bulunamayan kütüphaneler (uygulama burada çalışmıyor olabilir): ${r.missing.join(', ')}');
      }
      if (r.unresolved.isNotEmpty) {
        _say(
          '⚠ Hiçbir apt paketine ait olmayan kütüphaneler (elle eklenmeli veya uygulamayla taşınmalı): '
          '${r.unresolved.join(', ')}',
        );
      }
    });
  }

  /// Bu makinede elle kurulmuş paketlerden seçim penceresi açar; seçilenler listeye eklenir.
  Future<void> _pickInstalled() async {
    if (!Platform.isLinux) {
      _say('HATA: Kurulu paket listesi yalnızca Linux (Debian/Ubuntu) makinede alınabilir.');
      return;
    }
    InstalledResult? result;
    await _run(() async {
      result = await InstalledPackages().list(image: _image.text.trim(), log: _say);
    });
    if (result == null || !mounted) return;
    final picked = await showPackagePicker(context, result!, alreadySelected: _aptPackages.toSet());
    if (picked == null) return;
    final merged = {..._aptPackages, ...picked}.toList()..sort();
    setState(() => _cur.apt.text = merged.join('\n'));
    _say('✓ ${picked.length} paket seçildi; listede toplam ${merged.length} paket var.');
  }

  /// Paket listesinin bağımlılıklarıyla birlikte `.deb` dosyalarını Docker'da indirir
  /// ve klasör alanına yazar; ardından "Tara ve önizle" ile devam edilir.
  Future<void> _downloadDebs() async {
    final image = _image.text.trim();
    if (!DebFetcher.isValidImage(image)) {
      _say('HATA: Geçersiz Docker imajı: "$image"');
      return;
    }
    await _run(() async {
      final out = await Directory.systemTemp.createTemp('codenfast_debs_');
      _say('Docker ($image) ile indiriliyor: ${_aptPackages.join(', ')}');
      final debs = await DebFetcher().fetch(packages: _aptPackages, image: image, out: out, log: _say);
      final size = debs.fold<int>(0, (a, f) => a + f.lengthSync());
      _say('✓ ${debs.length} .deb (${formatBytes(size)}) → ${out.path}');
      setState(() {
        _cur.folder.text = out.path;
        _cur.plan = null;
      });
    });
  }

  /// Klasör yüklemeden yalnızca apt paket listesini katalogda günceller.
  Future<void> _saveApt() async {
    final id = _id.text.trim();
    if (!_idPattern.hasMatch(id)) {
      _say('HATA: Bağımlılık kimliği yalnızca A-Z a-z 0-9 . _ - içerebilir.');
      return;
    }
    final name = _name.text.trim().isEmpty ? id : _name.text.trim();
    await _run(() async {
      await widget.publisher.updateCatalog(
        (doc) => doc.upsertAptTarget(id: id, name: name, description: _description.text, packages: _aptPackages),
        _say,
      );
      await _refresh(select: id);
    });
  }

  Future<void> _delete() async {
    final id = _selected;
    if (id == null) return;
    final users = _doc.dependents(id);
    if (users.isNotEmpty) {
      _say('HATA: "$id" şu uygulamalar tarafından kullanılıyor: ${users.join(', ')}. Önce onlardan kaldırın.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('"$id" katalogdan silinsin mi?'),
        content: const Text('Sunucudaki dosyalar silinmez; yalnızca catalog.json\'dan çıkarılır.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('SİL')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.publisher.updateCatalog((doc) => doc.removeDependency(id), _say);
      setState(() {
        _selected = null;
        _creating = false;
      });
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deps = _doc.dependencies;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bağımlılıklar'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
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
                    width: 280,
                    child: Material(
                      color: const Color(0xFF13161E),
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _new,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Yeni bağımlılık'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: deps.isEmpty
                                ? const Center(
                                    child: Text('Henüz bağımlılık yok.', style: TextStyle(color: Colors.white54)),
                                  )
                                : ListView(
                                    children: [
                                      for (final d in deps)
                                        ListTile(
                                          dense: true,
                                          selected: d['id'] == _selected && !_creating,
                                          title: Text((d['name'] as String?) ?? d['id'] as String),
                                          subtitle: Text(
                                            '${d['id']} · ${((d['desktop'] as Map?) ?? const {}).keys.join(', ')}',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          onTap: _busy ? null : () => _select(d['id'] as String),
                                        ),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _selected == null && !_creating
                        ? const Center(
                            child: Text(
                              'Soldan bir bağımlılık seçin veya "Yeni bağımlılık" ile ekleyin.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: _form()),
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

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _row([
        _f(
          'Kimlik (id)',
          _id,
          hint: 'vcredist-2022',
          enabled: _creating,
          helper: _creating ? 'Sonradan değiştirilemez.' : null,
        ),
        _f('Ad', _name, flex: 2),
      ]),
      _row([_f('Açıklama', _description)]),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final os in _oses)
            ButtonSegment(
              value: os,
              label: Text(_osNames[os]!),
              icon: _defined(os) ? const Icon(Icons.check_circle_outline, size: 16) : null,
            ),
        ],
        selected: {_os},
        onSelectionChanged: (v) => setState(() => _os = v.first),
      ),
      const SizedBox(height: 16),
      _osTab(),
      const SizedBox(height: 4),
      if (!_creating)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Bağımlılığı katalogdan sil (tüm işletim sistemleri)'),
          ),
        ),
    ],
  );

  /// Seçili işletim sisteminin sekme içeriği.
  Widget _osTab() {
    final f = _cur;
    final plan = f.plan;
    final canPublish = plan != null && plan.problems.isEmpty && !_busy;
    final windows = _os == 'windows';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(_aptMode ? '.deb dosyaları (çevrimdışı yedek, isteğe bağlı)' : 'Dosyalar'),
        _row([
          _f(
            _aptMode ? '.deb dosyalarının klasörü' : 'Kurulum dosyalarının klasörü',
            f.folder,
            flex: 4,
            helper: _aptMode
                ? 'Çevrimdışı kurulum için. "Paketlerden .deb indir" burayı doldurur.'
                : 'Kurucu (örn. vc_redist.x64.exe) ve yanındaki gerekli dosyalar bu klasörden sunucuya yüklenir.',
          ),
          OutlinedButton(onPressed: _busy ? null : _pickFolder, child: const Text('Gözat')),
        ]),
        _row([_f('Sürüm (isteğe bağlı)', f.version), _f('Yoksay (virgülle)', f.ignore, hint: '*.log', flex: 2)]),
        if (_os == 'linux') ...[
          _row([
            _f('apt paketleri (Debian/Ubuntu; her satıra bir tane)', f.apt, maxLines: 3, hint: 'libgtk-3-0\nlibssl3'),
          ]),
          _row([_f('Docker imajı (hedef dağıtımla aynı)', _image, hint: 'ubuntu:26.04'), const Spacer()]),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _scanApp,
                  icon: const Icon(Icons.radar, size: 16),
                  label: const Text('Uygulama klasörünü tara'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickInstalled,
                  icon: const Icon(Icons.checklist, size: 16),
                  label: const Text('Bu makineden seç'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || !_aptMode ? null : _downloadDebs,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('Paketlerden .deb indir'),
                ),
                OutlinedButton.icon(
                  onPressed: !_aptMode ? null : _showTerminalCommand,
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('Terminal komutu'),
                ),
              ],
            ),
          ),
          if (_aptMode)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'İnternet varsa (checkip.amazonaws.com yanıt veriyorsa) eksik paketler apt-get ile kurulur. '
                'Yoksa yukarıdaki klasördeki .deb dosyaları sunucudan indirilip dpkg -i ile kurulur; '
                'bağımlı paketlerin hepsi klasörde olmalıdır; "Paketlerden .deb indir" bunları Docker ile toplar.',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
        ],
        if (!_aptMode) ...[
          _row([
            _f(
              'Çalıştırılacak kurucu (klasöre göre yol)',
              f.exe,
              flex: 3,
              hint: windows ? 'vc_redist.x64.exe' : 'kurulum.sh',
            ),
            if (plan != null && plan.manifest.files.isNotEmpty)
              PopupMenuButton<String>(
                tooltip: 'Taranan dosyalardan seç',
                icon: const Icon(Icons.list),
                itemBuilder: (_) => [
                  for (final e in plan.manifest.files.take(200)) PopupMenuItem(value: e.rel, child: Text(e.rel)),
                ],
                onSelected: (v) => setState(() => f.exe.text = v),
              ),
          ]),
          _row([_f('Argümanlar (her satıra bir tane)', f.args, maxLines: 3, hint: '/install\n/quiet\n/norestart')]),
          _section('Kurulu mu? denetimi (isteğe bağlı, ama önerilir)'),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Ölçüt sağlanıyorsa kurucu çalıştırılmaz. Boş bırakılırsa yalnızca bu makinede daha önce '
              'kurulup kurulmadığına bakılır.',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
          if (windows) ...[
            _row([
              _f(
                'Kayıt defteri anahtarı',
                f.regKey,
                flex: 3,
                hint: r'HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
              ),
            ]),
            _row([_f('Değer adı', f.regValue, hint: 'Installed'), _f('Beklenen değer', f.equals, hint: '1')]),
          ],
          _row([
            _f(
              'Var olması gereken dosya',
              f.file,
              hint: windows ? r'%SystemRoot%\System32\vcruntime140.dll' : '/usr/local/bin/arac',
            ),
          ]),
        ],
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
              label: Text(_publishLabel),
            ),
            if (_aptMode)
              OutlinedButton.icon(
                onPressed: _busy ? null : _saveApt,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('Yalnızca paket listesini kaydet'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (plan == null)
          const Text(
            'Yayın düğmesi, önce "Tara ve önizle" çalıştırılınca açılır.',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          )
        else if (plan.problems.isNotEmpty)
          for (final p in plan.problems) Text('⚠ $p', style: const TextStyle(color: Color(0xFFFF5370), fontSize: 11)),
      ],
    );
  }

  String get _publishLabel =>
      _aptMode ? 'Çevrimdışı .deb dosyalarını yükle ve yayınla' : '${_osNames[_os]} için yayınla';

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF00E5FF))),
  );

  Widget _logPanel() => Container(
    height: 110,
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
  }) => Expanded(
    flex: flex,
    child: TextField(
      controller: c,
      enabled: enabled,
      maxLines: maxLines,
      style: _inputStyle,
      onChanged: (_) => setState(() => _cur.plan = null),
      decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, isDense: true),
    ),
  );
}
