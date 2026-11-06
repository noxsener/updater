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

  List<Map<String, dynamic>> get dependencies =>
      ((raw['dependencies'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? dependency(String id) {
    for (final d in dependencies) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  /// Bağımlılık hâlâ kullanılıyorsa, kullanan uygulamaların kimlikleri.
  List<String> dependents(String depId) => [
    for (final a in apps)
      if (((a['requires'] as List?) ?? const []).contains(depId)) a['id'] as String,
  ];

  /// Yalnızca katalogdan çıkarır; kullanan uygulama varsa reddeder.
  bool removeDependency(String id) {
    final users = dependents(id);
    if (users.isNotEmpty) {
      throw Exception('"$id" bağımlılığını şu uygulamalar kullanıyor: ${users.join(', ')}');
    }
    final list = raw['dependencies'] as List?;
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((d) => (d as Map)['id'] == id);
    return list.length != before;
  }

  /// Boş [requires] alanı kaldırır; sıra korunur.
  void setRequires(String appId, List<String> requires) {
    final a = app(appId)!;
    if (requires.isEmpty) {
      a.remove('requires');
    } else {
      a['requires'] = requires;
    }
  }

  /// Bağımlılık kaydını (yoksa oluşturup) ad/açıklamasıyla günceller; `desktop` haritasını döndürür.
  Map<String, dynamic> _dependencyDesktop(String id, String name, String? description) {
    final list = (raw.putIfAbsent('dependencies', () => <dynamic>[]) as List);
    var d = dependency(id);
    if (d == null) {
      d = <String, dynamic>{'id': id};
      list.add(d);
    }
    d['name'] = name;
    if (description == null || description.trim().isEmpty) {
      d.remove('description');
    } else {
      d['description'] = description.trim();
    }
    return (d.putIfAbsent('desktop', () => <String, dynamic>{}) as Map).cast<String, dynamic>();
  }

  /// Linux `apt` hedefi. [offlineManifestUrl] null ise mevcut çevrimdışı adres korunur.
  void upsertAptTarget({
    required String id,
    required String name,
    String? description,
    required List<String> packages,
    String? offlineManifestUrl,
  }) {
    final desktop = _dependencyDesktop(id, name, description);
    final existing = ((desktop['linux'] as Map?)?['apt'] as Map?)?['offlineManifestUrl'];
    desktop['linux'] = {
      'apt': {'packages': packages, 'offlineManifestUrl': ?(offlineManifestUrl ?? existing)},
    };
  }

  void upsertDependencyTarget({
    required String id,
    required String name,
    String? description,
    required String os,
    required String manifestUrl,
    required String exe,
    required List<String> args,
    String? registryKey,
    String? registryValue,
    String? equals,
    String? file,
  }) {
    final desktop = _dependencyDesktop(id, name, description);
    String? t(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final detect = <String, dynamic>{
      'registryKey': ?t(registryKey),
      if (t(registryKey) != null) 'registryValue': ?t(registryValue),
      if (t(registryKey) != null) 'equals': ?t(equals),
      'file': ?t(file),
    };
    final target = <String, dynamic>{
      ...?(desktop[os] as Map?)?.cast<String, dynamic>(), // successCodes gibi alanlar korunur
      'manifestUrl': manifestUrl,
      'run': {'exe': exe, if (args.isNotEmpty) 'args': args},
    };
    if (detect.isEmpty) {
      target.remove('detect');
    } else {
      target['detect'] = detect;
    }
    desktop[os] = target;
  }

  Map<String, dynamic>? variant(String appId, String variantId) {
    final list = (app(appId)?['variants'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    for (final v in list) {
      if (v['id'] == variantId) return v;
    }
    return null;
  }

  // ── İndirilebilir dosyalar (ISO) ───────────────────────────────────────────

  List<Map<String, dynamic>> get downloads => ((raw['downloads'] as List?) ?? const []).cast<Map<String, dynamic>>();

  Map<String, dynamic>? download(String id) {
    for (final d in downloads) {
      if (d['id'] == id) return d;
    }
    return null;
  }

  /// Kaydın bilgilerini günceller (yoksa oluşturur); dosyalar ve bilinmeyen alanlar korunur.
  /// Boş değer isteğe bağlı alanı kaldırır.
  void upsertDownload({
    required String id,
    required String name,
    String? description,
    String? category,
    String? logoUrl,
    String? version,
  }) {
    final list = raw.putIfAbsent('downloads', () => <dynamic>[]) as List;
    var d = download(id);
    if (d == null) {
      d = <String, dynamic>{'id': id, 'files': <dynamic>[]};
      list.add(d);
    }
    d['name'] = name;
    for (final e in {
      'description': description,
      'category': category,
      'logoUrl': logoUrl,
      'version': version,
    }.entries) {
      if (e.value == null || e.value!.trim().isEmpty) {
        d.remove(e.key);
      } else {
        d[e.key] = e.value!.trim();
      }
    }
    d.putIfAbsent('files', () => <dynamic>[]);
  }

  /// Dosyayı `fileName`'e göre ekler ya da günceller.
  void upsertDownloadFile({
    required String id,
    required String name,
    required String fileName,
    required String url,
    required String sha256,
    int? size,
  }) {
    final files = (download(id)!['files'] as List).cast<Map<String, dynamic>>();
    var f = files.where((x) => x['fileName'] == fileName).firstOrNull;
    if (f == null) {
      f = <String, dynamic>{'fileName': fileName};
      files.add(f);
    }
    f['name'] = name;
    f['url'] = url;
    f['sha256'] = sha256.toLowerCase();
    if (size == null) {
      f.remove('size');
    } else {
      f['size'] = size;
    }
  }

  bool removeDownloadFile(String id, String fileName) {
    final files = download(id)?['files'] as List?;
    if (files == null) return false;
    final before = files.length;
    files.removeWhere((f) => (f as Map)['fileName'] == fileName);
    return files.length != before;
  }

  /// Yalnızca katalogdan çıkarır; sunucudaki dosyalara dokunmaz.
  bool removeDownload(String id) {
    final list = raw['downloads'] as List?;
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((d) => (d as Map)['id'] == id);
    return list.length != before;
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
    InstallerSpec? installer,
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
    final target = existing is Map ? existing.cast<String, dynamic>() : <String, dynamic>{};
    target['manifestUrl'] = manifestUrl;
    target['launch'] = launch;
    if (installer == null) {
      target.remove('installer'); // portable'a dönüş
    } else {
      target['installer'] = {
        'type': installer.type,
        'file': installer.file,
        'displayName': installer.displayName,
        if (installer.args.isNotEmpty) 'args': installer.args,
      };
    }
    desktop[os] = target;
  }

  /// Kayıt öncesi: istemcinin okuyacağı biçimle uyumlu mu?
  void validate() => Catalog.fromJson(raw);

  String encode() => '${const JsonEncoder.withIndent('  ').convert(raw)}\n';
}
