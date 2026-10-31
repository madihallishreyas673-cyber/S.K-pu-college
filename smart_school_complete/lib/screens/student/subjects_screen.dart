import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/content_view.dart';

IconData _subjectIcon(String n) => switch (n) {
      'Physics' => Icons.bolt_outlined, 'Chemistry' => Icons.science_outlined, 'Mathematics' => Icons.calculate_outlined,
      'Biology' => Icons.biotech_outlined, 'English' => Icons.menu_book_outlined, 'Hindi' => Icons.translate, 'Kannada' => Icons.translate,
      _ => Icons.school_outlined };

/// One card per subject with the teacher's name; opens that subject's notes, videos and live classes.
class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});
  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.rpc('my_subject_teachers')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Subjects')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, () => setState(() => _f = _load()));
            final l = snap.data!;
            return GridView.count(
              crossAxisCount: 2, padding: const EdgeInsets.all(16), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.05,
              children: [
                for (final x in l) Card(child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentContentScreen(title: x['subject_name'] as String, subjectId: x['subject_id'] as String))),
                  child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Icon(_subjectIcon(x['subject_name'] as String), size: 30, color: AppColors.brass),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x['subject_name'] as String, style: display(18)),
                      const SizedBox(height: 2),
                      Text(x['teacher_name'] == null ? 'Teacher not assigned yet' : x['teacher_name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ])),
                )),
              ],
            );
          },
        )),
      );
}
