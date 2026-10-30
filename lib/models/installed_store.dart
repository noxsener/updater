import 'dart:convert';
import 'dart:io';

class InstalledRecord {
  /// Kurulum anındaki manifest gövdesinin sha256'sı. Değişirse güncelleme vardır.
  final String fingerprint;
  final String? version;
  final DateTime updatedAt;

  const InstalledRecord({
    required this.fingerprint,
    required this.version,
    required this.updatedAt,
  });

  factory InstalledRecord.fromJson(Map<String, dynamic> json) =>
      InstalledRecord(
        fingerprint: json['fingerprint'] as String,
        version: json['version'] as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// `installed.json`: ürün/varyant başına kurulu sürüm kaydı.
class InstalledStore {
  final File _file;
  final Map<String, InstalledRecord> _records;

  InstalledStore._(this._file, this._records);

  static String key(String appId, String variantId) => '$appId/$variantId';

  static Future<InstalledStore> load(Directory baseDir) async {
    final file = File('${baseDir.path}/installed.json');
    final records = <String, InstalledRecord>{};
    try {
      if (await file.exists()) {
        final raw = json.decode(await file.readAsString()) as Map;
        raw.forEach((k, v) {
          records[k as String] = InstalledRecord.fromJson(
            v as Map<String, dynamic>,
          );
        });
      }
    } catch (_) {
      // Bozuk dosya: kayıtları sıfırla, ürünler "kurulu değil" görünür.
      records.clear();
    }
    return InstalledStore._(file, records);
  }

  InstalledRecord? get(String appId, String variantId) =>
      _records[key(appId, variantId)];

  Future<void> put(String appId, String variantId, InstalledRecord r) async {
    _records[key(appId, variantId)] = r;
    await _save();
  }

  Future<void> remove(String appId, String variantId) async {
    _records.remove(key(appId, variantId));
    await _save();
  }

  Future<void> _save() => _file.writeAsString(
    json.encode(_records.map((k, v) => MapEntry(k, v.toJson()))),
  );
}
