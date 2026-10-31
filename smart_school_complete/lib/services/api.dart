import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config.dart';

class ApiException implements Exception {
  final String message, code;
  ApiException(this.message, [this.code = 'error']);
  @override
  String toString() => message;
}

const _offline = 'No internet connection. Check your network and try again.';

class Api {
  static Uri _u(String fn) => Uri.parse('${AppConfig.supabaseUrl}/functions/v1/$fn');

  static Map<String, dynamic> _decode(http.Response r) {
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    throw ApiException((body['error'] ?? 'Request failed (${r.statusCode}).') as String, (body['code'] ?? 'error') as String);
  }

  static Future<T> _net<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on SocketException {
      throw ApiException(_offline, 'offline');
    } on http.ClientException {
      throw ApiException(_offline, 'offline');
    } on TimeoutException {
      throw ApiException('The server took too long to respond. Try again.', 'timeout');
    }
  }

  static Future<Map<String, dynamic>> post(String fn, Map<String, dynamic> body, {String? token}) => _net(() async {
        final r = await http
            .post(_u(fn),
                headers: {
                  'Content-Type': 'application/json',
                  'apikey': AppConfig.anonKey,
                  'Authorization': 'Bearer ${token ?? AppConfig.anonKey}',
                },
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));
        return _decode(r);
      });

  static Future<Map<String, dynamic>> register(Map<String, String> fields, String photoPath) => _net(() async {
        final req = http.MultipartRequest('POST', _u('register'))
          ..headers['apikey'] = AppConfig.anonKey
          ..headers['Authorization'] = 'Bearer ${AppConfig.anonKey}'
          ..fields.addAll(fields)
          ..files.add(await http.MultipartFile.fromPath('id_photo', photoPath, filename: 'id_card.jpg'));
        final streamed = await req.send().timeout(const Duration(seconds: 60));
        return _decode(await http.Response.fromStream(streamed));
      });
}
