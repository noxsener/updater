import 'dart:convert';

import '../models/catalog.dart';

/// catalog.json'u ham `Map` olarak düzenler; bilmediğimiz alanlar (başka bir
/// araçla eklenmiş olsalar bile) korunur.
class CatalogDoc {
  final Map<String, dynamic> raw;

  CatalogDoc(this.raw);

  factory CatalogDoc.empty() => CatalogDoc({'apps': <dynamic>[]});

  factory CatalogDoc.parse(String source) {
    final decoded = json.decode(source) as Map<String, dynamic>;
    decoded.putIfAbsent('apps', () => <dynamic>[]);
    return CatalogDoc(decoded);
  }

  List<Map<String, dynamic>> get apps => (raw['apps'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic>? app(String id) {
    for (final a in apps) {
      if (a['id'] == id) return a;
    }
    return null;
  }

  Map<String, dynamic>? variant(String appId, String variantId) {
    final list = (app(appId)?['variants'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final v in list) {
      if (v['id'] == variantId) return v;
    }
    return null;
  }

  /// Yalnızca katalogdan çıkarır; sunucudaki dosyalara dokunmaz.
  bool removeApp(String id) {
    final before = apps.length;
    (raw['apps'] as List).removeWhere((a) => (a as Map)['id'] == id);
    return apps.length != before;
  }

  Map<String, dynamic> _addApp(String id) {
    final a = <String, dynamic>{'id': id};
    apps.add(a);
    return a;
  }

  /// Boş değer, isteğe bağlı alanı katalogdan kaldırır.
  void upsertApp({
    required String id,
    required String name,
    String? category,
    String? description,
    String? logoUrl,
    String? android,
    String? ios,
  }) {
    final a = app(id) ?? _addApp(id);
    a['name'] = name;
    void opt(String key, String? v) {
      if (v == null || v.trim().isEmpty) {
        a.remove(key);
      } else {
        a[key] = v.trim();
      }
    }

    opt('category', category);
    opt('description', description);
    opt('logoUrl', logoUrl);

    final mobile = <String, dynamic>{...(a['mobile'] as Map?)?.cast<String, dynamic>() ?? {}};
    for (final e in {'android': android, 'ios': ios}.entries) {
      if (e.value == null || e.value!.trim().isEmpty) {
        mobile.remove(e.key);
      } else {
        mobile[e.key] = e.value!.trim();
      }
    }
    if (mobile.isEmpty) {
      a.remove('mobile');
    } else {
      a['mobile'] = mobile;
    }
    a.putIfAbsent('variants', () => <dynamic>[]);
  }

  void upsertDesktopTarget({
    required String appId,
    required String variantId,
    required String variantName,
    required String os,
    required String manifestUrl,
    required String exe,
    required List<String> args,
  }) {
    final a = app(appId)!;
    final variants = (a['variants'] as List).cast<Map<String, dynamic>>();
    var v = variant(appId, variantId);
    if (v == null) {
      v = <String, dynamic>{'id': variantId};
      variants.add(v);
    }
    v['name'] = variantName;
    final desktop = (v.putIfAbsent('desktop', () => <String, dynamic>{}) as Map).cast<String, dynamic>();
    // Var olan hedefin bilinmeyen alanları korunur.
    final launch = {'exe': exe, if (args.isNotEmpty) 'args': args};
    final existing = desktop[os];
    if (existing is Map) {
      existing['manifestUrl'] = manifestUrl;
      existing['launch'] = launch;
    } else {
      desktop[os] = {'manifestUrl': manifestUrl, 'launch': launch};
    }
  }

  /// Kayıt öncesi: istemcinin okuyacağı biçimle uyumlu mu?
  void validate() => Catalog.fromJson(raw);

  String encode() => '${const JsonEncoder.withIndent('  ').convert(raw)}\n';
}
