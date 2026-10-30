import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/catalog.dart';
import 'url_guard.dart';

const catalogUrl = String.fromEnvironment(
  'CATALOG_URL',
  defaultValue: 'https://media.codenfast.com/catalog.json',
);

class CatalogService {
  final http.Client _client;

  CatalogService({http.Client? client}) : _client = client ?? http.Client();

  Future<Catalog> fetch([String url = catalogUrl]) async {
    final response = await _client
        .get(requireSecureUri(url))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Katalog alınamadı (HTTP ${response.statusCode}).');
    }
    return Catalog.fromJson(
      json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
