import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import '../config.dart';
import '../models.dart';
import 'api.dart';
import 'cache.dart';

/// Holds the signed-in person and the signed token. No email, phone or Google account is involved.
class SessionController extends ChangeNotifier {
  static const _kStore = 'session_v1';
  final _storage = const FlutterSecureStorage();
  String? _token;
  DateTime? _expires;
  AppUser? user;
  bool ready = false;

  late final SupabaseClient db =
      SupabaseClient(AppConfig.supabaseUrl, AppConfig.anonKey, accessToken: () async => _token ?? AppConfig.anonKey);

  Future<void> restore() async {
    try {
      final raw = await _storage.read(key: _kStore);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final exp = DateTime.parse(j['expires'] as String);
        if (exp.isAfter(DateTime.now())) {
          _token = j['token'] as String;
          _expires = exp;
          user = AppUser.fromJson(Map<String, dynamic>.from(j['user'] as Map));
          if (exp.difference(DateTime.now()).inHours < 6) await _refresh();
        } else {
          await _storage.delete(key: _kStore);
        }
      }
    } catch (_) {
      await _storage.delete(key: _kStore);
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _refresh() async {
    try {
      final r = await Api.post('session', {'action': 'refresh'}, token: _token);
      _token = r['token'] as String;
      _expires = DateTime.parse(r['expires_at'] as String);
      await _persist();
    } on ApiException catch (e) {
      if (e.code == 'session_expired' || e.code == 'inactive') await logout();
    }
  }

  Future<void> _persist() => _storage.write(
      key: _kStore, value: jsonEncode({'token': _token, 'expires': _expires!.toIso8601String(), 'user': user!.toJson()}));

  Future<void> login({required String role, required String loginId, int? year, required String pin}) async {
    final r = await Api.post('login', {'role': role, 'login_id': loginId.trim(), 'year_level': year, 'pin': pin});
    _token = r['token'] as String;
    _expires = DateTime.parse(r['expires_at'] as String);
    user = AppUser.fromJson(Map<String, dynamic>.from(r['user'] as Map));
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    _expires = null;
    user = null;
    await _storage.delete(key: _kStore);
    await LocalCache.clear();
    notifyListeners();
  }

  Future<void> changePin(String current, String next) async {
    await Api.post('session', {'action': 'change_pin', 'current_pin': current, 'new_pin': next}, token: _token);
    user = user!.copyWith(mustChangePin: false);
    await _persist();
    notifyListeners();
  }

  Future<Map<String, dynamic>> adminAction(Map<String, dynamic> body) => Api.post('admin', body, token: _token);

  /// Wraps database calls: friendly messages, offline detection, and sign-out when the token expired.
  Future<T> run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt')) {
        await logout();
        throw ApiException('Your session has expired. Please sign in again.', 'session_expired');
      }
      throw ApiException(e.message);
    } on SocketException {
      throw ApiException('No internet connection. Check your network and try again.', 'offline');
    } on http.ClientException {
      throw ApiException('No internet connection. Check your network and try again.', 'offline');
    }
  }

  String get cachePrefix => 'u:${user?.id}:';
}
