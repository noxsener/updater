import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/root_context.dart';

class ApiService {
  static const String _jsonUrl = 'http://app.codenfast.com/wirecutterbot/files.json';

  Future<RootContext> fetchJsonConfig() async {
    final response = await http.get(Uri.parse(_jsonUrl));
    if (response.statusCode == 200) {
      return RootContext.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load configuration');
    }
  }

  Future<void> downloadFile(String url, String savePath) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final file = File(savePath);
      await file.writeAsBytes(response.bodyBytes);
    } else {
      throw Exception('Failed to download file');
    }
  }
}