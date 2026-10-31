import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../office/student_fee_screen.dart';
import '../shared/notifications_screen.dart';

/// Administrator: examinations & results, fees, announcements, subjects, audit log.
class SchoolTab extends StatelessWidget {
  const SchoolTab({super.key});
  @override
  Widget build(BuildContext context) {
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData i, String t, String sub, Widget page) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Icon(i, color: AppColors.brass), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(sub), trailing: const Icon(Icons.chevron_right), onTap: () => go(page))));
    return ListView(padding: const EdgeInsets.all(16), children: [
      tile(Icons.event_note_outlined, 'Examinations & results', 'Create exams, merit lists, subject averages, mark corrections', const ExamsScreen()),
      tile(Icons.account_balance_wallet_outlined, 'Fees', 'School summary, find a student, void a wrong payment', const FeeOverviewScreen()),
      tile(Icons.campaign_outlined, 'Announcements', 'Post notices to everyone, a role or a class', const AnnouncementsAdminScreen()),
      tile(Icons.menu_book_outlined, 'Subjects', 'Add or switch off subjects', const SubjectsAdminScreen()),
      tile(Icons.notifications_none, 'My notifications', 'Updates sent to your account', const NotificationsScreen()),
      tile(Icons.history, 'Audit log', 'Who changed what (read-only)', const AuditScreen()),
    ]);
  }
}

// ------------------------------------------------------------------ EXAMS
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});
  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('examinations').select('*, classes(year_level,section)').order('created_at', ascending: false)));
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _create() async {
    final s = context.read<SessionController>();
    final y = await s.run(() => s.db.from('academic_years').select('id').eq('is_current', true).single());
    final cl = (await s.run(() => s.db.from('classes').select().eq('academic_year_id', y['id']))) as List;
    final classes = cl.map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList()..sort((a, b) => a.label.compareTo(b.label));
    if (!mounted) return;
    final name = TextEditingController();
    final max = TextEditingController(text: '100');
    SchoolClass? cls = classes.isEmpty ? null : classes.first;
    DateTime? date;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('New examination'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<SchoolClass>(
            value: cls, decoration: const InputDecoration(labelText: 'Class'),
            items: [for (final x in classes) DropdownMenuItem(value: x, child: Text(x.label))], onChanged: (v) => set(() => cls = v)),
          const SizedBox(height: 8),
          TextField(controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Examination name (e.g. Unit Test 1)')),
          TextField(controller: max, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Default maximum marks per subject')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.event), label: Text(date == null ? 'Exam start date (optional)' : DateFormat('d MMM yyyy').format(date!)),
            onPressed: () async {
              final d = await showDatePicker(context: c, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 730)));
              if (d != null) set(() => date = d);
            }),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () async {
              if (cls == null) return;
              try {
                await s.run(() async => await s.db.rpc('create_exam', params: {
                      'p_class': cls!.id, 'p_name': name.text, 'p_starts': date == null ? null : DateFormat('yyyy-MM-dd').format(date!),
                      'p_max': num.tryParse(max.text.trim()) ?? 100}));
                if (c.mounted) Navigator.pop(c);
                if (mounted) { toast(context, 'Examination created - students notified'); _reload(); }
              } catch (e) { if (c.mounted) toast(c, errText(e), error: true); }
            },
            child: const Text('Create')),
        ],
      )),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Examinations')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New exam')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.event_note_outlined, 'No examinations yet. Tap "New exam".');
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              for (final e in l) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${SchoolClass.fromJson({...(e['classes'] as Map<String, dynamic>), 'id': e['class_id']}).label}'
                    '${e['starts_on'] == null ? '' : '  -  ${DateFormat('d MMM yyyy').format(DateTime.parse(e['starts_on'] as String))}'}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ExamDetailScreen(exam: e))),
              ))),
            ]);
          },
        )),
      );
}

class ExamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> exam;
  const ExamDetailScreen({super.key, required this.exam});
  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> {
  late Future<({List<Map<String, dynamic>> merit, List<Map<String, dynamic>> subjects, List<Map<String, dynamic>> marks})> _f = _load();

  Future<({List<Map<String, dynamic>> merit, List<Map<String, dynamic>> subjects, List<Map<String, dynamic>> marks})> _load() {
    final s = context.read<SessionController>();
    final id = widget.exam['id'];
    return s.run(() async {
      final merit = asList(await s.db.rpc('exam_merit_list', params: {'p_exam': id}));
      final subs = asList(await s.db.rpc('exam_subject_summary', params: {'p_exam': id}));
      final marks = asList(await s.db.from('marks').select('subject_id,student_id,marks_obtained,max_marks,subjects(name),users!marks_student_id_fkey(full_name)').eq('exam_id', id).eq('status', 'published'));
      return (merit: merit, subjects: subs, marks: marks);
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _correct(Map<String, dynamic> m) async {
    final v = TextEditingController(text: '${n(m['marks_obtained'])}');
    final why = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Correct a published mark'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${(m['users'] as Map)['full_name']} - ${(m['subjects'] as Map)['name']}\nMaximum ${n(m['max_marks'])}'),
          const SizedBox(height: 10),
          TextField(controller: v, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Correct marks')),
          const SizedBox(height: 8),
          TextField(controller: why, decoration: const InputDecoration(labelText: 'Reason (required, logged)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Correct')),
        ],
      ),
    );
    final nv = num.tryParse(v.text.trim());
    if (ok != true || nv == null) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('correct_published_mark', params: {
            'p_exam': widget.exam['id'], 'p_subject': m['subject_id'], 'p_student': m['student_id'], 'p_new': nv, 'p_reason': why.text}));
      if (mounted) toast(context, 'Corrected. Rankings recalculated automatically.');
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(title: Text(widget.exam['name'] as String), bottom: const TabBar(
            indicatorColor: AppColors.brass, labelColor: AppColors.brass, unselectedLabelColor: AppColors.muted,
            tabs: [Tab(text: 'Merit list'), Tab(text: 'Subjects'), Tab(text: 'Marks')])),
          body: SafeArea(child: FutureBuilder(
            future: _f,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) return ErrorView(snap.error!, _reload);
              final d = snap.data!;
              return TabBarView(children: [
                d.merit.isEmpty ? const EmptyView(Icons.leaderboard_outlined, 'No ranks yet. Ranks appear when teachers publish marks.') : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final r in d.merit) ListTile(
                    leading: CircleAvatar(backgroundColor: AppColors.surfaceHi, child: Text('${r['rank']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                    title: Text(r['full_name'] as String), subtitle: Text('Roll ${r['roll_no']}  -  ${_t(r['total_obtained'])}/${_t(r['total_max'])}'),
                    trailing: Text(pct(n(r['percentage'])), style: const TextStyle(fontWeight: FontWeight.w700))),
                ]),
                d.subjects.isEmpty ? const EmptyView(Icons.bar_chart, 'No marks entered yet.') : ListView(padding: const EdgeInsets.all(12), children: [
                  for (final s in d.subjects) Card(child: ListTile(
                    title: Text(s['subject_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${s['students']} students  -  high ${pct(n(s['highest_pct']))}  -  low ${pct(n(s['lowest_pct']))}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('avg ${pct(n(s['average_pct']))}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(s['published'] == true ? 'published' : 'draft', style: TextStyle(fontSize: 12, color: s['published'] == true ? AppColors.mint : AppColors.amber)),
                    ]))),
                ]),
                d.marks.isEmpty ? const EmptyView(Icons.edit_note, 'No published marks to correct.') : ListView(padding: const EdgeInsets.all(12), children: [
                  const Padding(padding: EdgeInsets.all(8), child: Text('Tap a mark to make an authorised correction.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                  for (final m in d.marks) ListTile(
                    dense: true, title: Text((m['users'] as Map)['full_name'] as String), subtitle: Text((m['subjects'] as Map)['name'] as String),
                    trailing: Text('${_t(m['marks_obtained'])} / ${_t(m['max_marks'])}', style: const TextStyle(fontWeight: FontWeight.w700)), onTap: () => _correct(m)),
                ]),
              ]);
            },
          )),
        ),
      );
}

String _t(dynamic v) {
  final d = n(v).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

// -------------------------------------------------------------------- FEES
class FeeOverviewScreen extends StatefulWidget {
  const FeeOverviewScreen({super.key});
  @override
  State<FeeOverviewScreen> createState() => _FeeOverviewScreenState();
}

class _FeeOverviewScreenState extends State<FeeOverviewScreen> {
  late Future<Map<String, dynamic>> _f = _load();
  Future<Map<String, dynamic>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => Map<String, dynamic>.from(await s.db.rpc('fee_summary') as Map));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fees')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _f,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(30), child: LoadingView());
              if (snap.hasError) return ErrorView(snap.error!, () => setState(() => _f = _load()));
              final m = snap.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Academic year ${m['year_label']}', style: display(19)),
                const SizedBox(height: 10),
                Row(children: [StatChip('Total fees', money(n(m['total_fees']))), const SizedBox(width: 10), StatChip('Collected', money(n(m['collected'])), color: AppColors.mint)]),
                const SizedBox(height: 10),
                Row(children: [StatChip('Remaining', money(n(m['remaining'])), color: AppColors.amber), const SizedBox(width: 10), StatChip('With dues', '${m['students_with_dues']}/${m['students_with_account']}')]),
                const SizedBox(height: 24),
              ]);
            },
          ),
          Text('Find a student', style: display(19)),
          const SizedBox(height: 8),
          const FeeSearch(),
        ])),
      );
}

// ------------------------------------------------------------ ANNOUNCEMENTS
class AnnouncementsAdminScreen extends StatefulWidget {
  const AnnouncementsAdminScreen({super.key});
  @override
  State<AnnouncementsAdminScreen> createState() => _AnnouncementsAdminScreenState();
}

class _AnnouncementsAdminScreenState extends State<AnnouncementsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('announcements').select('*, classes(year_level,section)').order('created_at', ascending: false).limit(50)));
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _create() async {
    final s = context.read<SessionController>();
    final cl = (await s.run(() => s.db.from('classes').select())) as List;
    final classes = cl.map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList()..sort((a, b) => a.label.compareTo(b.label));
    if (!mounted) return;
    final title = TextEditingController(), body = TextEditingController();
    String? role;
    String? classId;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('New announcement'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Title')),
          TextField(controller: body, minLines: 3, maxLines: 8, maxLength: 2000, decoration: const InputDecoration(labelText: 'Message')),
          DropdownButtonFormField<String?>(
            value: role, decoration: const InputDecoration(labelText: 'Send to'),
            items: const [DropdownMenuItem(value: null, child: Text('Everyone')), DropdownMenuItem(value: 'student', child: Text('Students')), DropdownMenuItem(value: 'teacher', child: Text('Teachers')), DropdownMenuItem(value: 'office', child: Text('Office staff'))],
            onChanged: (v) => set(() => role = v)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            value: classId, decoration: const InputDecoration(labelText: 'Class (students only)'),
            items: [const DropdownMenuItem(value: null, child: Text('All classes')), for (final x in classes) DropdownMenuItem(value: x.id, child: Text(x.label))],
            onChanged: (v) => set(() => classId = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () async {
              if (title.text.trim().isEmpty || body.text.trim().isEmpty) { toast(c, 'Enter a title and a message.', error: true); return; }
              try {
                await s.run(() async => await s.db.from('announcements').insert({
                      'title': title.text.trim(), 'body': body.text.trim(), 'target_role': role, 'class_id': classId, 'created_by': s.user!.id}));
                if (c.mounted) Navigator.pop(c);
                if (mounted) { toast(context, 'Announcement posted'); _reload(); }
              } catch (e) { if (c.mounted) toast(c, errText(e), error: true); }
            },
            child: const Text('Post')),
        ],
      )),
    );
  }

  Future<void> _delete(Map<String, dynamic> a) async {
    final s = context.read<SessionController>();
    try { await s.run(() async => await s.db.from('announcements').delete().eq('id', a['id'])); } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Announcements')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.campaign_outlined, 'No announcements yet.');
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              for (final a in l) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(
                title: Text(a['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${a['body']}\n${a['target_role'] ?? 'everyone'}${a['classes'] == null ? '' : ' - ${SchoolClass.fromJson({...(a['classes'] as Map<String, dynamic>), 'id': a['class_id']}).label}'}  -  ${DateFormat('d MMM').format(DateTime.parse(a['created_at'] as String).toLocal())}'),
                isThreeLine: true,
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(a)),
              ))),
            ]);
          },
        )),
      );
}

// ----------------------------------------------------------------- SUBJECTS
class SubjectsAdminScreen extends StatefulWidget {
  const SubjectsAdminScreen({super.key});
  @override
  State<SubjectsAdminScreen> createState() => _SubjectsAdminScreenState();
}

class _SubjectsAdminScreenState extends State<SubjectsAdminScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('subjects').select().order('name')));
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _add() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add a subject'),
        content: TextField(controller: name, autofocus: true, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Subject name')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Add'))]),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final s = context.read<SessionController>();
    try { await s.run(() async => await s.db.from('subjects').insert({'name': name.text.trim()})); } catch (e) { if (mounted) toast(context, 'Could not add (is the name already used?)', error: true); }
    _reload();
  }

  Future<void> _toggle(Map<String, dynamic> x, bool on) async {
    final s = context.read<SessionController>();
    try { await s.run(() async => await s.db.from('subjects').update({'is_active': on}).eq('id', x['id'])); } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Subjects')),
        floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add subject')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Switching a subject off hides it from new registrations. Existing marks and attendance are kept.', style: TextStyle(color: AppColors.muted, fontSize: 13))),
              for (final x in snap.data!) Card(child: SwitchListTile(title: Text(x['name'] as String), value: x['is_active'] == true, onChanged: (v) => _toggle(x, v))),
            ]);
          },
        )),
      );
}

// -------------------------------------------------------------------- AUDIT
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();
  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('audit_logs').select().order('at', ascending: false).limit(150)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Audit log')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, () => setState(() => _f = _load()));
            return ListView(padding: const EdgeInsets.all(12), children: [
              for (final a in snap.data!) ListTile(
                dense: true, title: Text(a['action'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${a['entity']}  ${a['details']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Text(DateFormat('d MMM\nh:mm a').format(DateTime.parse(a['at'] as String).toLocal()), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AppColors.muted))),
            ]);
          },
        )),
      );
}
