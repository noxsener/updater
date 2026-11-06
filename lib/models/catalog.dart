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

  factory LaunchConfig.fromJson(Map<String, dynamic> json) =>
      LaunchConfig(executable: json['exe'] as String, args: ((json['args'] as List?) ?? const []).cast<String>());
}

/// Windows'ta dosya senkronu yerine bir kurucu (MSI / Inno Setup) çalıştırarak kurulan
/// uygulama. Kurulu mu ve sürüm bilgisi kayıt defterindeki programlar listesinden okunur.
class InstallerSpec {
  static const types = {'msi', 'inno'};

  /// `msi` | `inno`; sessiz kurulum parametrelerini belirler.
  final String type;

  /// Kurucu dosya (manifest klasörüne göre yol), örn. `FlykobiSetup.exe`.
  final String file;

  /// "Programlar ve Özellikler"deki ad (büyük/küçük harf duyarsız, önek eşleşmesi).
  /// MSI ürün kodu her sürümde değiştiği için sabit kod yerine ad kullanılır.
  final String displayName;

  /// Sessiz parametrelere eklenenler (örn. `ALLUSERS=1`, `/DIR=...`).
  final List<String> args;

  const InstallerSpec({required this.type, required this.file, required this.displayName, this.args = const []});

  factory InstallerSpec.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    if (!types.contains(type)) throw FormatException('Geçersiz kurucu tipi: $type');
    final name = (json['displayName'] as String).trim();
    if (name.isEmpty) throw const FormatException('Kurucu için displayName gerekli.');
    return InstallerSpec(
      type: type,
      file: json['file'] as String,
      displayName: name,
      args: ((json['args'] as List?) ?? const []).cast<String>(),
    );
  }

  /// Kurucuyu sessiz çalıştıran komut; [filePath] indirilen kurucunun tam yolu.
  (String, List<String>) installCommand(String filePath) => type == 'msi'
      ? ('msiexec.exe', ['/i', filePath, '/qn', '/norestart', ...args])
      : (filePath, ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', ...args]);
}

/// Bir varyantın tek bir masaüstü işletim sistemindeki karşılığı.
class DesktopTarget {
  final String manifestUrl;
  final LaunchConfig launch;

  /// Doluysa (yalnızca Windows) uygulama dosya senkronu yerine kurucuyla kurulur;
  /// [launch] kurulu uygulamanın yoludur (ortam değişkenleri açılır, göreliyse
  /// kurulum klasörüne göre).
  final InstallerSpec? installer;

  const DesktopTarget({required this.manifestUrl, required this.launch, this.installer});

  factory DesktopTarget.fromJson(Map<String, dynamic> json) => DesktopTarget(
    manifestUrl: json['manifestUrl'] as String,
    launch: LaunchConfig.fromJson(json['launch'] as Map<String, dynamic>),
    installer: json['installer'] == null ? null : InstallerSpec.fromJson(json['installer'] as Map<String, dynamic>),
  );
}

/// Bağımlılığın "bu makinede zaten kurulu mu?" sorusunu yanıtlayan ölçüt.
/// Biri verilmelidir; ikisi de verilirse ikisi de sağlanmalıdır.
class DetectRule {
  /// Yalnızca Windows. Örn. `HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64`.
  final String? registryKey;

  /// Okunacak değer adı; yoksa anahtarın varlığı yeterlidir.
  final String? registryValue;

  /// Verilirse değer bununla eşleşmelidir (büyük/küçük harf duyarsız).
  final String? equals;

  /// Var olması gereken dosya; `%ProgramFiles%` gibi ortam değişkenleri açılır.
  final String? file;

  const DetectRule({this.registryKey, this.registryValue, this.equals, this.file});

  factory DetectRule.fromJson(Map<String, dynamic> json) => DetectRule(
    registryKey: json['registryKey'] as String?,
    registryValue: json['registryValue'] as String?,
    equals: json['equals']?.toString(),
    file: json['file'] as String?,
  );
}

/// Debian/Ubuntu paket bağımlılığı. İnternet varsa [packages] `apt-get` ile,
/// yoksa [offlineManifestUrl]'deki `.deb` dosyaları `dpkg -i` ile kurulur.
class AptSpec {
  static final _name = RegExp(r'^[a-z0-9][a-z0-9+.:_-]*$');

  static bool isValidName(String p) => _name.hasMatch(p);

  final List<String> packages;

  /// `.deb` dosyalarının `files.json` adresi; yoksa çevrimdışı kurulum yapılamaz.
  final String? offlineManifestUrl;

  const AptSpec({required this.packages, this.offlineManifestUrl});

  factory AptSpec.fromJson(Map<String, dynamic> json) {
    final packages = ((json['packages'] as List?) ?? const []).cast<String>();
    if (packages.isEmpty) throw const FormatException('apt paket listesi boş.');
    for (final p in packages) {
      if (!isValidName(p)) throw FormatException('Geçersiz paket adı: $p');
    }
    return AptSpec(packages: packages, offlineManifestUrl: json['offlineManifestUrl'] as String?);
  }
}

/// Bir bağımlılığın tek bir işletim sistemindeki karşılığı. Ya [apt] (yalnızca
/// Linux) ya da [manifestUrl] + [run]: dosyalar uygulamalar gibi `files.json` ile
/// dağıtılır, indirilince [run] çalıştırılır.
class DependencyTarget {
  final String? manifestUrl;
  final LaunchConfig? run;
  final DetectRule? detect;
  final AptSpec? apt;

  /// Başarı sayılan çıkış kodları. 3010 (yeniden başlatma gerekli), 1638 (daha
  /// yenisi kurulu) ve 1641 yaygın MSI/Redist kodlarıdır.
  final List<int> successCodes;

  const DependencyTarget({
    this.manifestUrl,
    this.run,
    this.detect,
    this.apt,
    this.successCodes = const [0, 1638, 1641, 3010],
  });

  factory DependencyTarget.fromJson(Map<String, dynamic> json) {
    final successCodes = json['successCodes'] == null
        ? const [0, 1638, 1641, 3010]
        : (json['successCodes'] as List).cast<int>();
    if (json['apt'] != null) {
      return DependencyTarget(apt: AptSpec.fromJson(json['apt'] as Map<String, dynamic>), successCodes: successCodes);
    }
    return DependencyTarget(
      manifestUrl: json['manifestUrl'] as String,
      run: LaunchConfig.fromJson(json['run'] as Map<String, dynamic>),
      detect: json['detect'] == null ? null : DetectRule.fromJson(json['detect'] as Map<String, dynamic>),
      successCodes: successCodes,
    );
  }
}

/// Uygulamaların `requires` ile başvurduğu ortak kurulum bileşeni (VC++ Redist,
/// DirectX, .NET çalışma zamanı...). Uygulamadan önce, yalnızca eksikse kurulur.
class Dependency {
  final String id;
  final String name;
  final String description;

  /// Anahtar: `windows` | `linux` | `macos`. Hedefi olmayan işletim sisteminde atlanır.
  final Map<String, DependencyTarget> desktop;

  const Dependency({required this.id, required this.name, this.description = '', required this.desktop});

  factory Dependency.fromJson(Map<String, dynamic> json) => Dependency(
    id: _safeId(json['id']),
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    desktop: ((json['desktop'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, DependencyTarget.fromJson(v as Map<String, dynamic>)),
    ),
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
      (k, v) => MapEntry(k as String, DesktopTarget.fromJson(v as Map<String, dynamic>)),
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

  /// Uygulamadan önce kurulması gereken bağımlılıklar (katalogdaki sıraya göre).
  final List<Dependency> requires;

  const AppEntry({
    required this.id,
    required this.name,
    required this.description,
    this.category,
    required this.logoUrl,
    required this.mobile,
    required this.variants,
    this.requires = const [],
  });

  factory AppEntry.fromJson(Map<String, dynamic> json, [Map<String, Dependency> dependencies = const {}]) => AppEntry(
    id: _safeId(json['id']),
    name: json['name'] as String,
    category: json['category'] as String?,
    description: (json['description'] as String?) ?? '',
    logoUrl: json['logoUrl'] as String?,
    mobile: ((json['mobile'] as Map?) ?? const {}).cast<String, String>(),
    variants: ((json['variants'] as List?) ?? const [])
        .map((v) => Variant.fromJson(v as Map<String, dynamic>))
        .toList(),
    requires: [
      for (final id in (json['requires'] as List?) ?? const [])
        dependencies[id] ?? (throw FormatException('Bilinmeyen bağımlılık: $id (${json['id']})')),
    ],
  );
}

/// İndirilebilir tek bir dosya (örn. bir ISO sürümü). Kurulmaz; kullanıcının
/// İndirilenler klasörüne iner ve sha256 ile doğrulanır.
class DownloadFile {
  /// Kullanıcıya gösterilen ad, örn. "Desktop (amd64)".
  final String name;

  /// Diske yazılacak ad; yol ayracı içeremez.
  final String fileName;

  /// Kendi sunucumuz ya da harici yansı; https olmalıdır.
  final String url;
  final String sha256;
  final int? size;

  const DownloadFile({required this.name, required this.fileName, required this.url, required this.sha256, this.size});

  factory DownloadFile.fromJson(Map<String, dynamic> json) {
    final fileName = _safeId(json['fileName']);
    final sha = (json['sha256'] as String).toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw FormatException('Geçersiz sha256: $fileName');
    }
    return DownloadFile(
      name: (json['name'] as String?) ?? fileName,
      fileName: fileName,
      url: json['url'] as String,
      sha256: sha,
      size: json['size'] as int?,
    );
  }
}

/// "İşletim Sistemleri" sekmesindeki bir kayıt: aynı ürünün bir veya birkaç dosyası
/// (mimari/sürüm seçenekleri).
class DownloadEntry {
  final String id;
  final String name;
  final String description;
  final String? category;
  final String? logoUrl;
  final String? version;
  final List<DownloadFile> files;

  const DownloadEntry({
    required this.id,
    required this.name,
    this.description = '',
    this.category,
    this.logoUrl,
    this.version,
    required this.files,
  });

  factory DownloadEntry.fromJson(Map<String, dynamic> json) => DownloadEntry(
    id: _safeId(json['id']),
    name: json['name'] as String,
    description: (json['description'] as String?) ?? '',
    category: json['category'] as String?,
    logoUrl: json['logoUrl'] as String?,
    version: json['version'] as String?,
    files: [for (final f in (json['files'] as List?) ?? const []) DownloadFile.fromJson(f as Map<String, dynamic>)],
  );
}

class Catalog {
  final List<AppEntry> apps;
  final List<Dependency> dependencies;
  final List<DownloadEntry> downloads;

  const Catalog({required this.apps, this.dependencies = const [], this.downloads = const []});

  factory Catalog.fromJson(Map<String, dynamic> json) {
    final dependencies = [
      for (final d in (json['dependencies'] as List?) ?? const []) Dependency.fromJson(d as Map<String, dynamic>),
    ];
    final byId = {for (final d in dependencies) d.id: d};
    return Catalog(
      apps: (json['apps'] as List).map((a) => AppEntry.fromJson(a as Map<String, dynamic>, byId)).toList(),
      dependencies: dependencies,
      downloads: [
        for (final d in (json['downloads'] as List?) ?? const []) DownloadEntry.fromJson(d as Map<String, dynamic>),
      ],
    );
  }
}
