import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_models.dart';

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Klien GitHub Releases API untuk repo **publik** — tanpa token, tanpa
/// kredensial apa pun (REL-03).
class GitHubUpdateApi {
  GitHubUpdateApi({
    http.Client? client,
    this.repo = 'dwikyfarid/nyatet',
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String repo;
  final Duration timeout;

  Future<ReleaseInfo?> latest() async {
    final uri = Uri.https('api.github.com', '/repos/$repo/releases/latest');
    late http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'Nyatet-Android',
        },
      ).timeout(timeout);
    } catch (_) {
      throw UpdateCheckException('Tidak bisa cek update');
    }

    if (response.statusCode == 404) return null; // belum ada rilis
    if (response.statusCode == 403) {
      throw UpdateCheckException('Tidak bisa cek update (batas GitHub)');
    }
    if (response.statusCode != 200) {
      throw UpdateCheckException('Tidak bisa cek update');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) throw UpdateCheckException('Balasan GitHub tidak sah');
    return parseReleaseJson(Map<String, Object?>.from(decoded));
  }
}
