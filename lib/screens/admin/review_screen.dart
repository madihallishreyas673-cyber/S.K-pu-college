import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// The administrator compares the ID photo with the typed details, ticks the checks, then approves or rejects.
class ReviewScreen extends StatefulWidget {
  final Map<String, dynamic> reg;
  const ReviewScreen({super.key, required this.reg});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  String? _photoUrl;
  Object? _photoError;
  List<SchoolClass> _classes = [];
  List<Subject> _subjects = [];
  String? _classId;
  final Set<String> _pairs = {}; // "subjectId|classId" chosen for a teacher
  final _checks = <bool>[false, false, false];
  bool _busy = false;

  Map<String, dynamic> get r => widget.reg;
  String get role => r['role'] as String;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final s = context.read<SessionController>();
    try {
      final path = r['id_photo_path'] as String?;
      if (path != null) {
        _photoUrl = await s.run(() => s.db.storage.from('id-cards').createSignedUrl(path, 120));
      }
    } catch (e) {
      _photoError = e;
    }
    try {
      final c = await s.run(() async => await s.db.from('classes').select());
      final sub = await s.run(() async => await s.db.from('subjects').select('id,name').order('name'));
      _classes = (c as List).map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        ..sort((a, b) => a.label.compareTo(b.label));
      _subjects = (sub as List).map((e) => Subject(e['id'] as String, e['name'] as String)).toList();
      if (role == 'student') {
        final match = _classes.where((c) => c.yearLevel == r['year_level'] && c.section == (r['section'] ?? ''));
        _classId = match.isNotEmpty ? match.first.id : null;
      } else if (role == 'teacher') {
        final years = List<int>.from(r['year_levels'] as List);
        for (final sid in List<String>.from(r['subject_ids'] as List)) {
          for (final c in _classes.where((c) => years.contains(c.yearLevel))) { _pairs.add('$sid|${c.id}'); }
        }
      }
    } catch (e) {
      _photoError ??= e;
    }
    if (mounted) setState(() {});
  }

  List<String> get _checkLabels => switch (role) {
        'student' => ['Name on the card matches', 'Roll number on the card matches', 'Card clearly shows the red "Student ID Card" marking'],
        'teacher' => ['Name on the card matches', 'Card shows this person is a teacher', 'Subjects and classes below are correct'],
        _ => ['Name on the card matches', 'Card shows this person is office staff', 'ID number on the card is readable'],
      };

  bool get _ready => _checks.every((c) => c) && (role != 'student' || _classId != null) && (role != 'teacher' || _pairs.isNotEmpty);

  Future<void> _approve() async {
    setState(() => _busy = true);
    final s = context.read<SessionController>();
    try {
      final res = await s.adminAction({
        'action': 'approve', 'registration_id': r['id'],
        if (role == 'student') 'class_id': _classId,
        if (role == 'teacher') 'assignments': [for (final p in _pairs) {'subject_id': p.split('|')[0], 'class_id': p.split('|')[1]}],
      });
      if (!mounted) return;
      toast(context, res['photo_deleted'] == true ? 'Approved. ID photo deleted.' : 'Approved. Photo deletion will be retried from Accounts.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) { setState(() => _busy = false); toast(context, friendly(e), error: true); }
    }
  }

  Future<void> _reject() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reject registration?'),
        content: TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (shown in the audit log)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44), backgroundColor: AppColors.coral), onPressed: () => Navigator.pop(c, true), child: const Text('Reject'))],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await context.read<SessionController>().adminAction({'action': 'reject', 'registration_id': r['id'], 'reason': reason.text});
      if (mounted) { toast(context, 'Rejected. ID photo deleted.'); Navigator.pop(context, true); }
    } catch (e) {
      if (mounted) { setState(() => _busy = false); toast(context, friendly(e), error: true); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectName = {for (final s in _subjects) s.id: s.name};
    return Scaffold(
      appBar: AppBar(title: const Text('Review registration')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 28), children: [
          Text(r['full_name'] as String, style: display(26)),
          const SizedBox(height: 4),
          Text(role == 'student' ? '${yearName(r['year_level'] as int)}  -  Roll ${r['login_id']}${(r['section'] ?? '') == '' ? '' : '  -  Section ${r['section']}'}' : '${role == 'teacher' ? 'Teacher' : 'Office'}  -  ID ${r['login_id']}',
              style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 160), color: AppColors.surface,
              child: _photoUrl != null
                  ? InteractiveViewer(child: Image.network(_photoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Padding(padding: EdgeInsets.all(40), child: Text('Photo could not be loaded.'))))
                  : Padding(padding: const EdgeInsets.all(40), child: Center(child: _photoError != null ? Text(friendly(_photoError!), textAlign: TextAlign.center) : const CircularProgressIndicator(color: AppColors.brass))),
            ),
          ),
          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Pinch to zoom. The photo is deleted automatically after you decide.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
          const SizedBox(height: 18),
          if (role == 'student') DropdownButtonFormField<String>(
            value: _classId, decoration: const InputDecoration(labelText: 'Place in class'),
            items: [for (final c in _classes.where((c) => c.yearLevel == r['year_level'])) DropdownMenuItem(value: c.id, child: Text(c.label))],
            onChanged: (v) => setState(() => _classId = v),
          ),
          if (role == 'teacher') ...[
            Text('Subjects and classes to assign', style: display(18)),
            const SizedBox(height: 4),
            const Text('Requested by the teacher. Untick anything that is wrong.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            for (final sid in List<String>.from(r['subject_ids'] as List))
              for (final c in _classes.where((c) => List<int>.from(r['year_levels'] as List).contains(c.yearLevel)))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: AppColors.brass,
                  title: Text('${subjectName[sid] ?? 'Subject'}  -  ${c.label}'),
                  value: _pairs.contains('$sid|${c.id}'),
                  onChanged: (v) => setState(() => v == true ? _pairs.add('$sid|${c.id}') : _pairs.remove('$sid|${c.id}')),
                ),
          ],
          const SizedBox(height: 14),
          Text('Verification checks', style: display(18)),
          for (var i = 0; i < 3; i++)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading, activeColor: AppColors.brass,
              title: Text(_checkLabels[i]), value: _checks[i], onChanged: (v) => setState(() => _checks[i] = v ?? false)),
          const SizedBox(height: 18),
          FilledButton(onPressed: (_busy || !_ready) ? null : _approve, child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Approve and create account')),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _busy ? null : _reject, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: AppColors.coral, side: const BorderSide(color: AppColors.coral)), child: const Text('Reject')),
        ]),
      ),
    );
  }
}
