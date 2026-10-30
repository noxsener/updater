import 'dart:convert';
import 'dart:io';

import '../services/url_guard.dart';

/// Yayın sunucusu ayarları. Parola/anahtar içeriği tutulmaz; yalnızca anahtar
/// dosyasının yolu saklanır (parolalı anahtarlar için ssh-agent kullanın).
class AdminConfig {
  String host;
  int port;
  String user;
  String keyPath;
  String remoteRoot; // örn. /home/KULLANICI/media
  String publicBaseUrl; // örn. https://media.codenfast.com

  AdminConfig({
    this.host = '',
    this.port = 22,
    this.user = '',
    this.keyPath = '',
    this.remoteRoot = '',
    this.publicBaseUrl = '',
  });

  String get catalogRemotePath => '$remoteRoot/catalog.json';

  factory AdminConfig.fromJson(Map<String, dynamic> j) => AdminConfig(
    host: j['host'] as String? ?? '',
    port: j['port'] as int? ?? 22,
    user: j['user'] as String? ?? '',
    keyPath: j['keyPath'] as String? ?? '',
    remoteRoot: j['remoteRoot'] as String? ?? '',
    publicBaseUrl: j['publicBaseUrl'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'user': user,
    'keyPath': keyPath,
    'remoteRoot': remoteRoot,
    'publicBaseUrl': publicBaseUrl,
  };

  /// Boşsa geçerli; aksi halde kullanıcıya gösterilecek hata listesi.
  List<String> validate() {
    final errors = <String>[];
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(host)) errors.add('Sunucu adresi geçersiz.');
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(user)) errors.add('Kullanıcı adı geçersiz.');
    if (port < 1 || port > 65535) errors.add('Port geçersiz.');
    if (!RegExp(r'^/[A-Za-z0-9._/-]*$').hasMatch(remoteRoot) ||
        remoteRoot.split('/').contains('..')) {
      errors.add('Uzak kök dizin mutlak yol olmalı (harf, rakam, . _ - /).');
    }
    try {
      requireSecureUri(publicBaseUrl);
    } catch (_) {
      errors.add('Herkese açık adres https:// ile başlamalı.');
    }
    return errors;
  }

  static File _file(Directory dir) => File('${dir.path}/admin_config.json');

  static Future<AdminConfig> load(Directory dir) async {
    try {
      final f = _file(dir);
      if (await f.exists()) {
        return AdminConfig.fromJson(json.decode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {}
    return AdminConfig();
  }

  Future<void> save(Directory dir) =>
      _file(dir).writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
}
