import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class MarkAttendanceScreen extends StatefulWidget {
  final Assignment assignment;
  const MarkAttendanceScreen({super.key, required this.assignment});
  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  DateTime _date = DateTime.now();
  int _period = 1;
  late Future<List<RosterRow>> _f = _load();
  final Map<String, String> _marks = {}; // studentId -> 'P' | 'A' (only used for a new session)
  bool _busy = false;

  String get _iso => DateFormat('yyyy-MM-dd').format(_date);

  Future<List<RosterRow>> _load() {
    final s = context.read<SessionController>();
    _marks.clear();
    return s.run(() async {
      final r = await s.db.rpc('attendance_roster', params: {
        'p_class_id': widget.assignment.cls.id, 'p_subject_id': widget.assignment.subjectId,
        'p_date': _iso, 'p_period': _period});
      return (r as List).map((e) => RosterRow.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 180)), lastDate: DateTime.now());
    if (d != null) { _date = d; _reload(); }
  }

  Future<void> _submit(List<RosterRow> roster) async {
    final p = _marks.values.where((v) => v == 'P').length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Submit attendance?'),
        content: Text('${widget.assignment.subjectName}, ${widget.assignment.cls.label}\n${DateFormat('d MMM yyyy').format(_date)}, period $_period\n\n$p present, ${roster.length - p} absent.\n\nAfter submitting, changes need a reason and are logged.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Submit'))],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final s = context.read<SessionController>();
    try {
      await s.run(() => s.db.rpc('submit_attendance', params: {
            'p_class_id': widget.assignment.cls.id, 'p_subject_id': widget.assignment.subjectId,
            'p_date': _iso, 'p_period': _period,
            'p_records': [for (final r in roster) {'student_id': r.studentId, 'status': _marks[r.studentId]}]}));
      if (mounted) toast(context, 'Attendance submitted');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
    if (mounted) { setState(() => _busy = false); _reload(); }
  }

  void _tap(RosterRow r, String letter, String? current, bool submitted) {
    if (submitted) {
      if (current != letter) _correct(r, letter);
    } else {
      setState(() => _marks[r.studentId] = letter);
    }
  }

  Future<void> _correct(RosterRow r, String to) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Change ${r.name} to ${to == 'P' ? 'Present' : 'Absent'}?'),
        content: TextField(controller: reason, autofocus: true, decoration: const InputDecoration(labelText: 'Reason (required)')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Save change'))],
      ),
    );
    if (ok != true || !mounted) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() => s.db.rpc('correct_attendance', params: {'p_session_id': r.sessionId, 'p_student_id': r.studentId, 'p_new_status': to, 'p_reason': reason.text}));
      if (mounted) toast(context, 'Correction saved and logged');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
    if (mounted) _reload();
  }

  Future<void> _history(String sessionId, Map<String, String> names) async {
    final s = context.read<SessionController>();
    try {
      final rows = await s.run(() async => await s.db.from('attendance_audit').select().eq('session_id', sessionId).order('changed_at', ascending: false));
      if (!mounted) return;
      showModalBottomSheet(context: context, backgroundColor: AppColors.surface, isScrollControlled: true, builder: (c) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Correction history', style: display(22)),
          const SizedBox(height: 10),
          if ((rows as List).isEmpty) const Text('No corrections have been made.', style: TextStyle(color: AppColors.muted)),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (final a in rows) ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${names[a['student_id']] ?? 'Student'}: ${a['old_status'] ?? '-'} to ${a['new_status']}'),
              subtitle: Text('${a['reason']}\n${DateFormat('d MMM, h:mm a').format(DateTime.parse(a['changed_at'] as String).toLocal())}'),
              isThreeLine: true),
          ])),
        ])),
      )));
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    return Scaffold(
      appBar: AppBar(title: Text(a.subjectName), actions: [
        FutureBuilder<List<RosterRow>>(future: _f, builder: (c, snap) {
          final sid = snap.data?.map((r) => r.sessionId).whereType<String>().firstOrNull;
          if (sid == null) return const SizedBox.shrink();
          return IconButton(icon: const Icon(Icons.history), tooltip: 'Correction history',
              onPressed: () => _history(sid, {for (final r in snap.data!) r.studentId: r.name}));
        }),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(child: Text(a.cls.label, style: const TextStyle(color: AppColors.muted))),
            ActionChip(avatar: const Icon(Icons.calendar_today, size: 16), label: Text(DateFormat('d MMM').format(_date)), onPressed: _pickDate),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: _period, underline: const SizedBox.shrink(), dropdownColor: AppColors.surfaceHi,
              items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('Period $i'))],
              onChanged: (v) { if (v != null) { _period = v; _reload(); } }),
          ]),
        ),
        Expanded(child: FutureBuilder<List<RosterRow>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final roster = snap.data!;
            if (roster.isEmpty) return const EmptyView(Icons.groups_outlined, 'No approved students in this class yet.');
            final submitted = roster.any((r) => r.sessionId != null);
            final marked = _marks.length;
            return Column(children: [
              if (submitted) Container(
                width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.surfaceHi, borderRadius: BorderRadius.circular(10)),
                child: const Text('Already submitted for this session. Tap P or A to correct; a reason is required.', style: TextStyle(fontSize: 13, color: AppColors.amber)),
              ) else Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Text('$marked of ${roster.length} marked', style: const TextStyle(color: AppColors.muted)),
                  const Spacer(),
                  TextButton(onPressed: () => setState(() { for (final r in roster) { _marks[r.studentId] = 'P'; } }), child: const Text('All present')),
                ]),
              ),
              Expanded(child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), itemCount: roster.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final r = roster[i];
                  final cur = submitted ? r.existing : _marks[r.studentId];
                  return Card(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(children: [
                      SizedBox(width: 40, child: Text('${r.rollNo}', style: display(18, c: AppColors.brass))),
                      Expanded(child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                      _PA('P', cur == 'P', AppColors.mint, () => _tap(r, 'P', cur, submitted)),
                      const SizedBox(width: 8),
                      _PA('A', cur == 'A', AppColors.coral, () => _tap(r, 'A', cur, submitted)),
                    ]),
                  ));
                },
              )),
              if (!submitted) SafeArea(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton(
                  onPressed: (_busy || marked != roster.length) ? null : () => _submit(roster),
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Submit attendance'),
                ),
              )),
            ]);
          },
        )),
      ]),
    );
  }
}

class _PA extends StatelessWidget {
  final String letter;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  const _PA(this.letter, this.on, this.color, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 52, height: 48, alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? color : Colors.transparent, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: on ? color : AppColors.line, width: 1.5)),
          child: Text(letter, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: on ? AppColors.ink : AppColors.muted)),
        ),
      );
}
