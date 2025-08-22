import 'package:flutter/material.dart';

import '../services/file_service.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _statusMessage = 'Initializing...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _startUpdateProcess();
  }

  void _startUpdateProcess() async {
    final fileService = FileService();
    await fileService.startUpdateProcess((message, progress) {
      setState(() {
        _statusMessage = message;
        _progress = progress;
      });
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Codenfast Updater - WireCutterBot'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Image.network(
              'https://wirecutterbot.com/assets/images/wire-cutter-image_512.jpg',
              height: 150,
              errorBuilder: (context, error, stackTrace) {
                return Text('Image not found');
              },
            ),
            SizedBox(height: 20),
            Text(
              _statusMessage,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 10),
            LinearProgressIndicator(
              value: _progress,
            ),
          ],
        ),
      ),
    );
  }
}