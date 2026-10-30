import 'file_entry.dart';

class OsFiles {
  final String os;
  final List<FileEntry> fileList;

  const OsFiles({required this.os, required this.fileList});

  factory OsFiles.fromJson(Map<String, dynamic> json) => OsFiles(
    os: json['os'] as String,
    fileList: (json['fileList'] as List)
        .map((i) => FileEntry.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
}
