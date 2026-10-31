import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class TeacherAssignmentsScreen extends StatefulWidget {
  final String teacherId, teacherName;
  const TeacherAssignmentsScreen({super.key, required this.teacherId, required this.teacherName});
  @override
  State<TeacherAssignmentsScreen> createState() => _TeacherAssignmentsScreenState();
}

class _TeacherAssignmentsScreenState extends State<TeacherAssignmentsScreen> {
  late Future<({List<Assignment> list, List<Subject> subjects, List<SchoolClass> classes})> _f = _load();

  Future<({List<Assignment> list, List<Subject> subjects, List<SchoolClass> classes})> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final a = await s.db.from('teacher_assignments').select('id,subject_id,class_id,subjects(name),classes(year_level,section,class_teacher_id)').eq('teacher_id', widget.teacherId);
      final sub = await s.db.from('subjects').select('id,name').eq('is_active', true).order('name');
      final c = await s.db.from('classes').select();
      return (
        list: (a as List).map((e) => Assignment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        subjects: (sub as List).map((e) => Subject(e['id'] as String, e['name'] as String)).toList(),
        classes: (c as List).map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList()..sort((x, y) => x.label.compareTo(y.label)),
      );
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _remove(Assignment a) async {
    final s = context.read<SessionController>();
    try { await s.run(() async => await s.db.from('teacher_assignments').delete().eq('id', a.id)); } catch (e) { if (mounted) toast(context, friendly(e), error: true); }
    _reload();
  }

  Future<void> _add(List<Subject> subjects, List<SchoolClass> classes) async {
    String? sid, cid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Add assignment'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Subject'), items: [for (final s in subjects) DropdownMenuItem(value: s.id, child: Text(s.name))], onChanged: (v) => set(() => sid = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Class'), items: [for (final x in classes) DropdownMenuItem(value: x.id, child: Text(x.label))], onChanged: (v) => set(() => cid = v)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: sid != null && cid != null ? () => Navigator.pop(c, true) : null, child: const Text('Add'))],
      )),
    );
    if (ok != true) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('teacher_assignments').insert({'teacher_id': widget.teacherId, 'subject_id': sid, 'class_id': cid}));
    } catch (e) {
      if (mounted) toast(context, e.toString().contains('duplicate') ? 'That assignment already exists.' : friendly(e), error: true);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.teacherName)),
        body: FutureBuilder(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final d = snap.data!;
            return ListView(padding: const EdgeInsets.all(16), children: [
              const Text('This teacher can take attendance (and later enter marks) only for these subjects and classes.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              if (d.list.isEmpty) const EmptyView(Icons.menu_book_outlined, 'No assignments yet.'),
              for (final a in d.list) Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
                title: Text(a.subjectName, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text(a.cls.label),
                trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.coral), onPressed: () => _remove(a), tooltip: 'Remove'),
              ))),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () => _add(d.subjects, d.classes), icon: const Icon(Icons.add), label: const Text('Add subject and class'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
            ]);
          },
        ),
      );
}
