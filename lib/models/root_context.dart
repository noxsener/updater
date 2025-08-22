import 'os_files.dart';

class RootContext {
  final List<OsFiles> osFileList;

  RootContext({required this.osFileList});

  factory RootContext.fromJson(Map<String, dynamic> json) {
    return RootContext(
      osFileList: (json['osFileList'] as List)
          .map((i) => OsFiles.fromJson(i))
          .toList(),
    );
  }
}