import 'file_entry.dart';

class OsFiles {
  final String os;
  final List<FileEntry> fileList;
  final List<String> runCommands;

  OsFiles({
    required this.os,
    required this.fileList,
    required this.runCommands,
  });

  factory OsFiles.fromJson(Map<String, dynamic> json) {
    return OsFiles(
      os: json['os'],
      fileList: (json['fileList'] as List)
          .map((i) => FileEntry.fromJson(i))
          .toList(),
      runCommands: List<String>.from(json['runCommands']),
    );
  }
}