import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ClassesTab extends StatefulWidget {
  const ClassesTab({super.key});
  @override
  State<ClassesTab> createState() => _ClassesTabState();
}

class _ClassesTabState extends State<ClassesTab> {
  late Future<({List<SchoolClass> classes, List<Map<String, dynamic>> teachers, String yearId})> _f = _load();

  Future<({List<SchoolClass> classes, List<Map<String, dynamic>> teachers, String yearId})> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final y = await s.db.from('academic_years').select('id').eq('is_current', true).single();
      final c = await s.db.from('classes').select().eq('academic_year_id', y['id']);
      final t = await s.db.from('users').select('id,full_name,login_id').eq('role', 'teacher').eq('status', 'active').order('full_name');
      final cl = (c as List).map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList()..sort((a, b) => a.label.compareTo(b.label));
      return (classes: cl, teachers: (t as List).map((e) => Map<String, dynamic>.from(e as Map)).toList(), yearId: y['id'] as String);
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _setTeacher(SchoolClass c, String? teacherId) async {
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('classes').update({'class_teacher_id': teacherId}).eq('id', c.id));
      if (mounted) toast(context, 'Class teacher updated');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
    _reload();
  }

  Future<void> _addSection(String yearId) async {
    final sec = TextEditingController();
    int level = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Add a section'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          SegmentedButton<int>(segments: const [ButtonSegment(value: 1, label: Text('First')), ButtonSegment(value: 2, label: Text('Second'))], selected: {level}, onSelectionChanged: (v) => set(() => level = v.first)),
          const SizedBox(height: 12),
          TextField(controller: sec, textCapitalization: TextCapitalization.characters, maxLength: 10, decoration: const InputDecoration(labelText: 'Section name (e.g. A)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Add'))],
      )),
    );
    if (ok != true || sec.text.trim().isEmpty) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('classes').insert({'academic_year_id': yearId, 'year_level': level, 'section': sec.text.trim()}));
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(snap.error!, _reload);
          final d = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Choose each class teacher. They can then see full class attendance across all subjects.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 12),
              for (final cl in d.classes) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cl.label, style: display(20)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: d.teachers.any((t) => t['id'] == cl.classTeacherId) ? cl.classTeacherId : null,
                  decoration: const InputDecoration(labelText: 'Class teacher'),
                  items: [const DropdownMenuItem<String?>(value: null, child: Text('Not assigned')), for (final t in d.teachers) DropdownMenuItem<String?>(value: t['id'] as String, child: Text('${t['full_name']} (${t['login_id']})'))],
                  onChanged: (v) => _setTeacher(cl, v),
                ),
              ])))),
              OutlinedButton.icon(onPressed: () => _addSection(d.yearId), icon: const Icon(Icons.add), label: const Text('Add a section'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
            ]),
          );
        },
      );
}
