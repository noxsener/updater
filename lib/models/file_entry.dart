class FileEntry {
  final String name;
  final int fileSize;
  final String path;
  final String url;

  /// Opsiyonel. Yoksa yalnızca boyut kontrolü yapılır (eski files.json uyumu).
  final String? sha256;

  const FileEntry({
    required this.name,
    required this.fileSize,
    required this.path,
    required this.url,
    this.sha256,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String,
    fileSize: json['fileSize'] as int,
    path: json['path'] as String,
    url: json['url'] as String,
    sha256: (json['sha256'] as String?)?.toLowerCase(),
  );
}
