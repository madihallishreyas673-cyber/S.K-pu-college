import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../change_pin_screen.dart';
import 'class_report_screen.dart';
import 'mark_attendance_screen.dart';
import 'marks_entry_screen.dart';
import '../shared/content_view.dart';
import '../shared/notifications_screen.dart';

class TeacherHome extends StatefulWidget {
  const TeacherHome({super.key});
  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  late Future<({List<Assignment> assignments, List<SchoolClass> mine})> _f = _load();

  Future<({List<Assignment> assignments, List<SchoolClass> mine})> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      // Row-level security returns ONLY this teacher's assignments.
      final a = await s.db.from('teacher_assignments').select('id,subject_id,class_id,subjects(name),classes(year_level,section,class_teacher_id)');
      final c = await s.db.from('classes').select().eq('class_teacher_id', s.user!.id);
      final list = (a as List).map((e) => Assignment.fromJson(Map<String, dynamic>.from(e as Map))).toList()
        ..sort((x, y) => '${x.subjectName}${x.cls.label}'.compareTo('${y.subjectName}${y.cls.label}'));
      return (assignments: list, mine: (c as List).map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList());
    });
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user!;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            Row(children: [
              const Expanded(child: BrandBar()),
              const BellButton(),
              IconButton(icon: const Icon(Icons.lock_reset), tooltip: 'Change PIN', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePinScreen()))),
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: () => context.read<SessionController>().logout()),
            ]),
            const SizedBox(height: 22),
            Text(u.fullName, style: display(28)),
            const SizedBox(height: 20),
            FutureBuilder(
              future: _f,
              builder: (c, snap) {
                if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(40), child: LoadingView());
                if (snap.hasError) return ErrorView(snap.error!, _reload);
                final d = snap.data!;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (d.mine.isNotEmpty) ...[
                    Text('Class teacher', style: display(20)),
                    const SizedBox(height: 10),
                    for (final cl in d.mine) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const Icon(Icons.groups_outlined, color: AppColors.brass),
                      title: Text(cl.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Class attendance, low attendance, reports'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClassReportScreen(cls: cl))),
                    ))),
                    const SizedBox(height: 14),
                  ],
                  Text('My subjects', style: display(20)),
                  const SizedBox(height: 4),
                  const Text('Attendance, marks, notes, videos and live classes for each subject.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (d.assignments.isEmpty) const EmptyView(Icons.menu_book_outlined, 'No subjects assigned yet. Ask the administrator.'),
                  for (final a in d.assignments) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: Column(children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: const Icon(Icons.fact_check_outlined, color: AppColors.brass),
                      title: Text(a.subjectName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                      subtitle: Text(a.cls.label),
                      trailing: const Text('Attendance', style: TextStyle(color: AppColors.brass, fontWeight: FontWeight.w600)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarkAttendanceScreen(assignment: a))),
                    ),
                    Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Row(children: [
                      Expanded(child: TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MarksEntryScreen(assignment: a))), icon: const Icon(Icons.edit_note, size: 18), label: const Text('Marks'))),
                      Expanded(child: TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherContentScreen(assignment: a))), icon: const Icon(Icons.upload_file_outlined, size: 18), label: const Text('Notes'))),
                      Expanded(child: TextButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherContentScreen(assignment: a, initialTab: 2))), icon: const Icon(Icons.videocam_outlined, size: 18), label: const Text('Live'))),
                    ])),
                  ]))),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
