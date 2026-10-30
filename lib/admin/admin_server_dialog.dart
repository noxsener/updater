import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'admin_config.dart';

/// Sunucu (SSH/SCP) ayarları penceresi. Kaydedilecek ayarı döndürür.
/// [onTest], bağlantıyı dener ve hata durumunda istisna fırlatır.
Future<AdminConfig?> showServerDialog(
  BuildContext context,
  AdminConfig initial, {
  required Future<void> Function(AdminConfig) onTest,
}) => showDialog<AdminConfig>(
  context: context,
  builder: (_) => _ServerDialog(initial: initial, onTest: onTest),
);

class _ServerDialog extends StatefulWidget {
  final AdminConfig initial;
  final Future<void> Function(AdminConfig) onTest;

  const _ServerDialog({required this.initial, required this.onTest});

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final _host = TextEditingController(text: widget.initial.host);
  late final _port = TextEditingController(text: '${widget.initial.port}');
  late final _user = TextEditingController(text: widget.initial.user);
  late final _key = TextEditingController(text: widget.initial.keyPath);
  late final _remoteRoot = TextEditingController(text: widget.initial.remoteRoot);
  late final _publicUrl = TextEditingController(text: widget.initial.publicBaseUrl);
  String? _status;
  bool _ok = false;
  bool _testing = false;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _key, _remoteRoot, _publicUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  AdminConfig get _config => AdminConfig(
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    user: _user.text.trim(),
    keyPath: _key.text.trim(),
    remoteRoot: _remoteRoot.text.trim().replaceAll(RegExp(r'/+$'), ''),
    publicBaseUrl: _publicUrl.text.trim(),
  );

  Future<void> _test() async {
    final errors = _config.validate();
    if (errors.isNotEmpty) {
      setState(() {
        _ok = false;
        _status = errors.join(' ');
      });
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      await widget.onTest(_config);
      _ok = true;
      _status = 'Bağlantı başarılı.';
    } catch (e) {
      _ok = false;
      _status = e.toString().replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _testing = false);
  }

  void _save() {
    final errors = _config.validate();
    if (errors.isNotEmpty) {
      setState(() {
        _ok = false;
        _status = errors.join(' ');
      });
      return;
    }
    Navigator.pop(context, _config);
  }

  Future<void> _pickKey() async {
    final picked = await FilePicker.pickFiles();
    final path = picked.isEmpty ? null : picked.first.path;
    if (path != null) setState(() => _key.text = path);
  }

  Widget _field(String label, TextEditingController c, {String? hint, Widget? suffix}) => TextField(
    controller: c,
    decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, suffixIcon: suffix),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Sunucu ayarları'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Expanded(flex: 3, child: _field('Sunucu adresi', _host)),
              const SizedBox(width: 10),
              Expanded(child: _field('Port', _port)),
            ]),
            const SizedBox(height: 12),
            _field('Kullanıcı', _user),
            const SizedBox(height: 12),
            _field(
              'SSH anahtar dosyası (boşsa ssh-agent/varsayılan)',
              _key,
              suffix: IconButton(icon: const Icon(Icons.folder_open, size: 18), onPressed: _pickKey),
            ),
            const SizedBox(height: 12),
            _field('Uzak kök dizin', _remoteRoot, hint: '/home/KULLANICI/media'),
            const SizedBox(height: 12),
            _field('Herkese açık adres', _publicUrl, hint: 'https://media.codenfast.com'),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status!,
                  style: TextStyle(color: _ok ? const Color(0xFF69F0AE) : const Color(0xFFFF8A80), fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _testing ? null : _test,
        child: Text(_testing ? 'DENENİYOR...' : 'BAĞLANTIYI TEST ET'),
      ),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('VAZGEÇ')),
      TextButton(onPressed: _save, child: const Text('KAYDET')),
    ],
  );
}
