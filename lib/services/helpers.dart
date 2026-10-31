import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase/supabase.dart' show StorageException;
import 'package:url_launcher/url_launcher.dart';
import '../widgets/common.dart';
import 'session.dart';

List<Map<String, dynamic>> asList(dynamic v) => (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

/// Friendly text for any error, including storage errors.
String errText(Object e) => e is StorageException ? e.message : friendly(e);

String money(num v) => '\u20B9${NumberFormat.decimalPattern('en_IN').format(v)}';
String pct(num v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2)}%';

final _rnd = Random.secure();
String randomId([int n = 12]) {
  const c = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(n, (_) => c[_rnd.nextInt(c.length)]).join();
}

/// Only http(s) links are ever opened.
Future<void> openUrl(BuildContext c, String url) async {
  final u = Uri.tryParse(url.trim());
  if (u == null || !(u.scheme == 'https' || u.scheme == 'http') || u.host.isEmpty) {
    toast(c, 'That link is not valid.', error: true);
    return;
  }
  try {
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok && c.mounted) toast(c, 'Could not open the link.', error: true);
  } catch (_) {
    if (c.mounted) toast(c, 'Could not open the link.', error: true);
  }
}

/// Opens a private file from the `materials` bucket through a short-lived signed link.
Future<void> openStored(BuildContext c, SessionController s, String path) async {
  try {
    final url = await s.run(() => s.db.storage.from('materials').createSignedUrl(path, 3600));
    if (c.mounted) await openUrl(c, url);
  } catch (e) {
    if (c.mounted) toast(c, errText(e), error: true);
  }
}

Future<String> myClassId(SessionController s) async => (await s.run(() => s.db.rpc('my_class_id'))) as String;

const contentTypes = {
  'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'webp': 'image/webp',
  'txt': 'text/plain', 'doc': 'application/msword',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'mp4': 'video/mp4', 'webm': 'video/webm', 'mov': 'video/quicktime',
};
