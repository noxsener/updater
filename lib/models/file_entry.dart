class FileEntry {
  final String name;
  final int fileSize;
  final String path;
  final String url;

  FileEntry({
    required this.name,
    required this.fileSize,
    required this.path,
    required this.url,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'],
      fileSize: json['fileSize'],
      path: json['path'],
      url: json['url'],
    );
  }
}