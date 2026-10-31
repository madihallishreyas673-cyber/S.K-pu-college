import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Small on-device cache so screens still open offline. The server stays the source of truth.
class LocalCache {
  static Database? _db;
  static Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'smart_school_cache.db'), version: 1,
        onCreate: (d, _) => d.execute('create table kv (k text primary key, v text not null, saved_at text not null)'));

  static Future<void> put(String key, Object value) async {
    final d = await _open();
    await d.insert('kv', {'k': key, 'v': jsonEncode(value), 'saved_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<({dynamic value, DateTime savedAt})?> get(String key) async {
    final d = await _open();
    final rows = await d.query('kv', where: 'k = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return (value: jsonDecode(rows.first['v'] as String), savedAt: DateTime.parse(rows.first['saved_at'] as String));
  }

  static Future<void> clear() async => (await _open()).delete('kv');
}
