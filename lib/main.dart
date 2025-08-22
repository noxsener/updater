import 'dart:convert';
import 'dart:io';

import 'package:codenfast_updater/theme.dart';
import 'package:codenfast_updater/ui/widgets/progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:process_run/shell.dart';

// --- DATA MODELS ---
// It's better practice to have these in their own files (e.g., in a 'models' folder)
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
    var list = json['fileList'] as List;
    List<FileEntry> fileList = list.map((i) => FileEntry.fromJson(i)).toList();
    return OsFiles(
      os: json['os'],
      fileList: fileList,
      runCommands: List<String>.from(json['runCommands']),
    );
  }
}

class RootContext {
  final List<OsFiles> osFileList;

  RootContext({required this.osFileList});

  factory RootContext.fromJson(Map<String, dynamic> json) {
    var list = json['osFileList'] as List;
    List<OsFiles> osFilesList = list.map((i) => OsFiles.fromJson(i)).toList();
    return RootContext(osFileList: osFilesList);
  }
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    CodenfastTheme theme = CodenfastTheme();
    return MaterialApp(
      title: "Codenfast Upgrader",
      theme: ThemeData(
        useMaterial3: true,
        canvasColor: Colors.black,
        primarySwatch: theme.blackTransparent,
        textTheme: theme.textTheme(),
        primaryTextTheme: theme.textTheme(),
        colorScheme: theme.colorScheme(),
        iconTheme: theme.iconTheme(),
        inputDecorationTheme: theme.inputDecorationTheme(),
        snackBarTheme: SnackBarThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: Colors.black,
        ),
        dialogTheme: DialogThemeData(
          contentTextStyle: theme.textTheme().bodySmall,
          backgroundColor: const Color(0xFF222222),
          iconColor: Colors.white,
          titleTextStyle: theme.textTheme().titleSmall,
          elevation: 2,
          alignment: Alignment.center,
          actionsPadding: const EdgeInsets.all(20),
        ),
        focusColor: Colors.cyan,
        appBarTheme: AppBarTheme(
          backgroundColor: theme.cyanTransparent,
          foregroundColor: Colors.white,
          iconTheme: theme.iconTheme(),
          titleTextStyle: theme.textTheme().titleLarge,
          toolbarTextStyle: theme.textTheme().bodySmall,
          centerTitle: true,
        ),
        bannerTheme: MaterialBannerThemeData(
          backgroundColor: theme.blackTransparent,
        ),
      ),
      debugShowCheckedModeBanner: false,
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CodenfastTheme theme = CodenfastTheme();
  String _statusMessage = 'Initializing...';
  double _progress = 0.0;
  final String _imageUrl = 'https://codenfast.com/images/012021/Icon-144.webp';
  static const String _jsonUrl =
      'http://app.codenfast.com/wirecutterbot/files.json';

  @override
  void initState() {
    super.initState();
    // Start the update process shortly after the UI is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startUpdateProcess();
    });
  }

  String _getOperatingSystem() {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    return 'unsupported';
  }

  Future<void> _showErrorDialog(String message) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: SingleChildScrollView(
            child: ListBody(children: <Widget>[Text(message)]),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                // Optionally exit the app on critical error
                exit(1);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _startUpdateProcess() async {
    try {
      // 1. Determine OS
      setState(() {
        _statusMessage = 'Determining OS...';
      });
      final osType = _getOperatingSystem();
      if (osType == 'unsupported') {
        throw Exception('Unsupported Operating System.');
      }
      setState(() {
        _statusMessage = 'OS Detected: $osType';
      });

      // 2. Fetch Configuration
      setState(() {
        _statusMessage = 'Fetching configuration...';
        _progress = 0.05;
      });
      final response = await http.get(Uri.parse(_jsonUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch configuration from server.');
      }
      final config = RootContext.fromJson(json.decode(response.body));
      final osFiles = config.osFileList.firstWhere(
        (f) => f.os == osType,
        orElse: () => throw Exception('No configuration found for $osType.'),
      );

      setState(() {
        _statusMessage = 'Configuration loaded.';
        _progress = 0.1;
      });

      // 3. Process Files
      final appDir = await getApplicationDocumentsDirectory();
      int filesProcessed = 0;
      for (final entry in osFiles.fileList) {
        final localDir = Directory('${appDir.path}/${entry.path}');
        if (!await localDir.exists()) {
          await localDir.create(recursive: true);
        }

        final filePath = '${localDir.path}/${entry.name}';
        final file = File(filePath);
        bool downloadRequired = true;

        if (await file.exists()) {
          if (await file.length() == entry.fileSize) {
            setState(() {
              _statusMessage = '${entry.name} is up to date.';
              downloadRequired = false;
            });
          }
        }

        if (downloadRequired) {
          setState(() {
            _statusMessage = 'Downloading: ${entry.name}';
          });
          final downloadResponse = await http.get(Uri.parse(entry.url));
          if (downloadResponse.statusCode == 200) {
            await file.writeAsBytes(downloadResponse.bodyBytes);
            if (await file.length() != entry.fileSize) {
              throw Exception(
                'Size mismatch for ${entry.name} after download.',
              );
            }
          } else {
            throw Exception('Failed to download ${entry.name}.');
          }
        }
        filesProcessed++;
        setState(() {
          _progress = 0.1 + (0.8 * (filesProcessed / osFiles.fileList.length));
        });
      }

      // 4. Execute Commands
      setState(() {
        _statusMessage = 'All files are up to date.';
        _progress = 0.9;
      });
      if (osFiles.runCommands.isNotEmpty) {
        setState(() {
          _statusMessage = 'Executing post-update commands...';
        });
        var shell = Shell(workingDirectory: appDir.path);
        for (int i = 0; i < osFiles.runCommands.length ; i++) {
          final command = osFiles.runCommands[i];
          if ((i+1) < osFiles.runCommands.length) {
            await shell.run(command);
          } else {
            shell.run(command);
          }
        }
      }

      // 5. Finalize and Exit
      setState(() {
        _statusMessage = 'Update Complete! Launching application...';
        _progress = 1.0;
      });

      // Wait 1 second then close the updater.
      await Future.delayed(const Duration(seconds: 2));
      exit(0); // Exit the application with success code 0.
    } catch (e) {
      // Make sure we check if the widget is still mounted before setting state
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: ${e.toString()}';
          _progress = 0.0;
        });
        _showErrorDialog(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return getScaffold(context);
  }

  Widget getScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Codenfast Updater - D-Signer Eimza')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset("assets/images/DeadLineLogo.png"
                        ,width: 250, height: 250,),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Image.asset("assets/images/codenfast_logo_transparent_2688_1242.webp",width: 250, height: 250,),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              ProgressIndicatorWidget(
                statusMessage: _statusMessage,
                progress: _progress,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
