import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';
import '../models/file_entry.dart';
import '../models/os_files.dart';
import 'api_service.dart';

class FileService {
  final ApiService _apiService = ApiService();

  String getOperatingSystem() {
    if (Platform.isWindows) {
      return 'windows';
    } else if (Platform.isLinux) {
      return 'linux';
    } else if (Platform.isMacOS) {
      return 'macos';
    }
    return 'unsupported';
  }

  Future<void> startUpdateProcess(Function(String, double) onProgress) async {
    try {
      onProgress('Determining OS...', 0.0);
      final osType = getOperatingSystem();
      if (osType == 'unsupported') {
        onProgress('Unsupported OS.', 0.0);
        return;
      }
      onProgress('OS: $osType', 0.0);

      onProgress('Fetching configuration...', 0.05);
      final config = await _apiService.fetchJsonConfig();
      final osFiles = config.osFileList.firstWhere((f) => f.os == osType);

      onProgress('Configuration loaded.', 0.1);

      final appDir = await getApplicationDocumentsDirectory();
      int filesProcessed = 0;

      for (final entry in osFiles.fileList) {
        onProgress(
            'Checking: ${entry.name}', filesProcessed / osFiles.fileList.length);
        final localPath = '${appDir.path}/${entry.path}';
        final filePath = '$localPath/${entry.name}';
        final file = File(filePath);

        bool downloadRequired = true;
        if (await file.exists()) {
          final fileLength = await file.length();
          if (fileLength == entry.fileSize) {
            downloadRequired = false;
          }
        }

        if (downloadRequired) {
          onProgress('Downloading: ${entry.name}',
              filesProcessed / osFiles.fileList.length);
          await Directory(localPath).create(recursive: true);
          await _apiService.downloadFile(entry.url, filePath);
        }
        filesProcessed++;
      }

      onProgress('All files processed.', 1.0);
      await _executeRunCommands(osFiles.runCommands);
      onProgress('Application launched!', 1.0);
    } catch (e) {
      onProgress('Error: ${e.toString()}', 0.0);
    }
  }

  Future<void> _executeRunCommands(List<String> commands) async {
    var shell = Shell();
    for (final command in commands) {
      await shell.run(command);
    }
  }
}