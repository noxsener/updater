import 'os_files.dart';

/// Ürün başına `files.json` manifesti.
class RootContext {
  /// Opsiyonel, kullanıcıya gösterilir.
  final String? version;
  final List<OsFiles> osFileList;

  const RootContext({this.version, required this.osFileList});

  factory RootContext.fromJson(Map<String, dynamic> json) => RootContext(
    version: json['version'] as String?,
    osFileList: (json['osFileList'] as List)
        .map((i) => OsFiles.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
}
