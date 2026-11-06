import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';
import '../ui/format.dart';
import 'catalog_doc.dart';
import 'publisher.dart';

/// "İşletim Sistemleri" sekmesindeki indirilebilir dosyaları (ISO) yönetir. Dosya ya
/// sunucuya yüklenir (`<kök>/_files/<id>/`) ya da harici bir yansının https adresi girilir.
class AdminDownloadsPage extends StatefulWidget {
  final Publisher publisher;
  final CatalogDoc catalog;
  final ValueChanged<CatalogDoc> onCatalog;

  const AdminDownloadsPage({super.key, required this.publisher, required this.catalog, required this.onCatalog});

  @override
  State<AdminDownloadsPage> createState() => _AdminDownloadsPageState();
}

class _AdminDownloadsPageState extends State<AdminDownloadsPage> {
  static final _inputStyle = GoogleFonts.inter(fontSize: 13.5, color: Colors.white);
  static final _idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

  final _id = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _category = TextEditingController();
  final _logoUrl = TextEditingController();
  final _version = TextEditingController();

  final _fileLabel = TextEditingController();
  final _fileName = TextEditingController();
  final _localPath = TextEditingController();
  final _url = TextEditingController();
  final _sha = TextEditingController();
  final _size = TextEditingController();
  bool _upload = true;

  late CatalogDoc _doc = widget.catalog;
  String? _selected;
  bool _creating = false;
  bool _busy = false;
  final _log = <String>[];

  List<TextEditingController> get _info => [_id, _name, _description, _category, _logoUrl, _version];
  List<TextEditingController> get _file => [_fileLabel, _fileName, _localPath, _url, _sha, _size];

  @override
  void dispose() {
    for (final c in [..._info, ..._file]) {
      c.dispose();
    }
    super.dispose();
  }

  void _say(String line) {
    if (mounted) setState(() => _log.add(line));
  }

  void _select(String id) {
    final d = _doc.download(id);
    if (d == null) return;
    setState(() {
      _selected = id;
      _creating = false;
      _id.text = id;
      _name.text = (d['name'] as String?) ?? '';
      _description.text = (d['description'] as String?) ?? '';
      _category.text = (d['category'] as String?) ?? '';
      _logoUrl.text = (d['logoUrl'] as String?) ?? '';
      _version.text = (d['version'] as String?) ?? '';
      for (final c in _file) {
        c.clear();
      }
    });
  }

  void _new() => setState(() {
    _selected = null;
    _creating = true;
    for (final c in [..._info, ..._file]) {
      c.clear();
    }
    _category.text = 'İşletim Sistemleri';
  });

  /// Listeden bir dosyayı düzenlemek için forma yükler.
  void _editFile(Map<String, dynamic> f) => setState(() {
    _fileLabel.text = (f['name'] as String?) ?? '';
    _fileName.text = (f['fileName'] as String?) ?? '';
    _upload = false;
    _localPath.clear();
    _url.text = (f['url'] as String?) ?? '';
    _sha.text = (f['sha256'] as String?) ?? '';
    _size.text = f['size']?.toString() ?? '';
  });

  DownloadMeta get _meta => DownloadMeta(
    name: _name.text.trim().isEmpty ? _id.text.trim() : _name.text.trim(),
    description: _description.text,
    category: _category.text,
    logoUrl: _logoUrl.text,
    version: _version.text,
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

  bool get _idOk {
    final ok = _idPattern.hasMatch(_id.text.trim());
    if (!ok) _say('HATA: Kimlik yalnızca A-Z a-z 0-9 . _ - içerebilir.');
    return ok;
  }

  Future<void> _pickLocal() async {
    final r = await FilePicker.pickFiles();
    final path = r.isEmpty ? null : r.first.path;
    if (path == null) return;
    setState(() {
      _localPath.text = path;
      // Boşluk/özel karakterler URL ve uzak kabuk için güvensiz: önerilen ad temizlenir.
      final base = path.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      _fileName.text = base.replaceFirst(RegExp(r'^[^A-Za-z0-9]+'), '');
      if (_fileLabel.text.isEmpty) _fileLabel.text = _fileName.text;
    });
  }

  /// Seçili dosyanın sha256 ve boyutunu hesaplar (büyük dosyada dakikalar sürebilir).
  Future<void> _hashLocal() => _run(() async {
    _say('sha256 hesaplanıyor...');
    final h = await Publisher.hashFile(File(_localPath.text.trim()));
    _say('✓ sha256 ${h.sha256} (${formatBytes(h.size)})');
  });

  Future<void> _saveInfo() async {
    if (!_idOk) return;
    final m = _meta;
    final id = _id.text.trim();
    await _run(() async {
      await widget.publisher.updateCatalog(
        (doc) => doc.upsertDownload(
          id: id,
          name: m.name,
          description: m.description,
          category: m.category,
          logoUrl: m.logoUrl,
          version: m.version,
        ),
        _say,
      );
      await _refresh(select: id);
    });
  }

  DownloadPublishRequest get _request => DownloadPublishRequest(
    id: _id.text.trim(),
    meta: _meta,
    fileLabel: _fileLabel.text.trim().isEmpty ? _fileName.text.trim() : _fileLabel.text.trim(),
    fileName: _fileName.text.trim(),
    local: _upload ? File(_localPath.text.trim()) : null,
    url: _upload ? null : _url.text.trim(),
    sha256: _upload ? null : _sha.text.trim(),
    size: int.tryParse(_size.text.trim()),
  );

  Future<void> _publishFile() async {
    if (!_idOk) return;
    final req = _request;
    final problems = await widget.publisher.prepareDownload(req);
    if (problems.isNotEmpty) {
      for (final p in problems) {
        _say('⚠ $p');
      }
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dosya yayınlansın mı?'),
        content: Text(
          req.local != null
              ? '${req.fileName} sunucuya yüklenecek (${formatBytes(req.local!.lengthSync())}); büyük dosyalarda uzun sürebilir '
                    've yarıda kesilirse baştan başlar.\n\nAdres: ${widget.publisher.downloadPublicUrl(req)}'
              : 'Katalogda şu adres kaydedilecek (dosya yüklenmez):\n${req.url}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('VAZGEÇ')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('YAYINLA')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.publisher.publishDownload(req, _say);
      await _refresh(select: req.id);
    });
  }

  Future<void> _removeFile(String fileName) async {
    final id = _selected!;
    await _run(() async {
      await widget.publisher.updateCatalog((doc) => doc.removeDownloadFile(id, fileName), _say);
      await _refresh(select: id);
    });
  }

  Future<void> _delete() async {
    final id = _selected;
    if (id == null) return;
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
      await widget.publisher.updateCatalog((doc) => doc.removeDownload(id), _say);
      setState(() {
        _selected = null;
        _creating = false;
      });
      await _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _doc.downloads;
    return Scaffold(
      appBar: AppBar(
        title: const Text('İşletim Sistemleri (ISO)'),
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
                                label: const Text('Yeni kayıt'),
                              ),
                            ),
                          ),
                          Expanded(
                            child: items.isEmpty
                                ? const Center(
                                    child: Text('Henüz kayıt yok.', style: TextStyle(color: Colors.white54)),
                                  )
                                : ListView(
                                    children: [
                                      for (final d in items)
                                        ListTile(
                                          dense: true,
                                          selected: d['id'] == _selected && !_creating,
                                          title: Text((d['name'] as String?) ?? d['id'] as String),
                                          subtitle: Text(
                                            '${d['id']} · ${((d['files'] as List?) ?? const []).length} dosya',
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
                              'Soldan bir kayıt seçin veya "Yeni kayıt" ile ekleyin.',
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

  Widget _form() {
    final files = ((_selected == null ? null : _doc.download(_selected!)?['files']) as List? ?? const [])
        .cast<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row([
          _f(
            'Kimlik (id)',
            _id,
            hint: 'ubuntu',
            enabled: _creating,
            helper: _creating ? 'Sonradan değiştirilemez.' : null,
          ),
          _f('Ad', _name, flex: 2, hint: 'Ubuntu Desktop'),
          _f('Sürüm', _version, hint: '26.04'),
        ]),
        _row([_f('Açıklama', _description, maxLines: 3)]),
        _row([_f('Kategori', _category), _f('Logo URL (png/svg)', _logoUrl, flex: 2)]),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _saveInfo,
              icon: const Icon(Icons.save_outlined, size: 16),
              label: Text(_creating ? 'Kaydı oluştur' : 'Bilgileri kaydet'),
            ),
            if (!_creating)
              OutlinedButton.icon(
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Katalogdan sil'),
              ),
          ],
        ),
        if (!_creating) ...[
          _section('Dosyalar (sürüm / mimari seçenekleri)'),
          if (files.isEmpty)
            const Text('Henüz dosya yok. Aşağıdan ekleyin.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          for (final f in files)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${f['name']}  ·  ${f['fileName']}'),
              subtitle: Text(
                [
                  if (f['size'] is int) formatBytes(f['size'] as int),
                  'sha256 ${(f['sha256'] as String? ?? '').substring(0, 12)}…',
                  f['url'],
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () => _editFile(f),
              trailing: IconButton(
                tooltip: 'Dosyayı katalogdan çıkar',
                icon: const Icon(Icons.close, size: 18),
                onPressed: _busy ? null : () => _removeFile(f['fileName'] as String),
              ),
            ),
          _section('Dosya ekle / güncelle'),
          _row([
            _f('Görünen ad', _fileLabel, hint: 'Desktop (amd64)'),
            _f('Dosya adı', _fileName, hint: 'ubuntu-26.04.iso'),
          ]),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Sunucuya yükle'), icon: Icon(Icons.cloud_upload_outlined)),
              ButtonSegment(value: false, label: Text('Harici URL'), icon: Icon(Icons.link)),
            ],
            selected: {_upload},
            onSelectionChanged: (v) => setState(() => _upload = v.first),
          ),
          const SizedBox(height: 12),
          if (_upload) ...[
            _row([
              _f('Yerel dosya', _localPath, flex: 4, helper: 'sha256 ve boyut yayın sırasında hesaplanır.'),
              OutlinedButton(onPressed: _busy ? null : _pickLocal, child: const Text('Gözat')),
              OutlinedButton(
                onPressed: _busy || _localPath.text.trim().isEmpty ? null : _hashLocal,
                child: const Text('sha256 hesapla'),
              ),
            ]),
          ] else ...[
            _row([_f('Dosyanın https adresi', _url, flex: 3, hint: 'https://releases.ubuntu.com/…/ubuntu.iso')]),
            _row([
              _f('sha256 (64 hane)', _sha, flex: 3, helper: 'Yayıncının sayfasındaki SHA256SUMS değeri.'),
              _f('Boyut (bayt, isteğe bağlı)', _size),
            ]),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _publishFile,
            icon: Icon(_upload ? Icons.cloud_upload_outlined : Icons.playlist_add, size: 16),
            label: Text(_upload ? 'Yükle ve yayınla' : 'Kataloga ekle'),
          ),
        ],
      ],
    );
  }

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
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
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, hintText: hint, helperText: helper, isDense: true),
    ),
  );
}
