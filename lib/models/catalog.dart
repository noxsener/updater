/// Sunucudan gelen kimlikler dosya yolunda kullanıldığı için kısıtlanır.
String _safeId(Object? raw) {
  final id = raw as String;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(id) || id.contains('..')) {
    throw FormatException('Geçersiz kimlik: $id');
  }
  return id;
}

class LaunchConfig {
  /// Kurulum dizinine göre göreli yol; `/` ve `\` ikisi de kabul edilir.
  final String executable;
  final List<String> args;

  const LaunchConfig({required this.executable, this.args = const []});

  factory LaunchConfig.fromJson(Map<String, dynamic> json) => LaunchConfig(
    executable: json['exe'] as String,
    args: ((json['args'] as List?) ?? const []).cast<String>(),
  );
}

/// Bir varyantın tek bir masaüstü işletim sistemindeki karşılığı.
class DesktopTarget {
  final String manifestUrl;
  final LaunchConfig launch;

  const DesktopTarget({required this.manifestUrl, required this.launch});

  factory DesktopTarget.fromJson(Map<String, dynamic> json) => DesktopTarget(
    manifestUrl: json['manifestUrl'] as String,
    launch: LaunchConfig.fromJson(json['launch'] as Map<String, dynamic>),
  );
}

class Variant {
  final String id;
  final String name;

  /// Anahtar: `windows` | `linux` | `macos`.
  final Map<String, DesktopTarget> desktop;

  const Variant({required this.id, required this.name, required this.desktop});

  factory Variant.fromJson(Map<String, dynamic> json) => Variant(
    id: _safeId(json['id']),
    name: json['name'] as String,
    desktop: ((json['desktop'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(
        k as String,
        DesktopTarget.fromJson(v as Map<String, dynamic>),
      ),
    ),
  );
}

class AppEntry {
  final String id;
  final String name;
  final String description;
  final String? category;
  final String? logoUrl;

  /// Anahtar: `android` | `ios`. Değer mağaza URL'si.
  final Map<String, String> mobile;
  final List<Variant> variants;

  const AppEntry({
    required this.id,
    required this.name,
    required this.description,
    this.category,
    required this.logoUrl,
    required this.mobile,
    required this.variants,
  });

  factory AppEntry.fromJson(Map<String, dynamic> json) => AppEntry(
    id: _safeId(json['id']),
    name: json['name'] as String,
    category: json['category'] as String?,
    description: (json['description'] as String?) ?? '',
    logoUrl: json['logoUrl'] as String?,
    mobile: ((json['mobile'] as Map?) ?? const {}).cast<String, String>(),
    variants: ((json['variants'] as List?) ?? const [])
        .map((v) => Variant.fromJson(v as Map<String, dynamic>))
        .toList(),
  );
}

class Catalog {
  final List<AppEntry> apps;

  const Catalog({required this.apps});

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
    apps: (json['apps'] as List)
        .map((a) => AppEntry.fromJson(a as Map<String, dynamic>))
        .toList(),
  );
}
