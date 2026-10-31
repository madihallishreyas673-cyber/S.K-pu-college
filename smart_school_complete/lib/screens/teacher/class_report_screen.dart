import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../student/my_attendance_screen.dart';

/// Class-teacher view: whole-class attendance across all subjects, low-attendance list, CSV report.
class ClassReportScreen extends StatefulWidget {
  final SchoolClass cls;
  const ClassReportScreen({super.key, required this.cls});
  @override
  State<ClassReportScreen> createState() => _ClassReportScreenState();
}

class _ClassReportScreenState extends State<ClassReportScreen> {
  String _range = '30'; // '30' | 'month' | 'all'
  late Future<({List<Map<String, dynamic>> students, List<Map<String, dynamic>> subjects})> _f = _load();

  (String?, String?) get _dates {
    final now = DateTime.now();
    final f = DateFormat('yyyy-MM-dd');
    if (_range == '30') return (f.format(now.subtract(const Duration(days: 30))), f.format(now));
    if (_range == 'month') return (f.format(DateTime(now.year, now.month, 1)), f.format(now));
    return (null, null);
  }

  Future<({List<Map<String, dynamic>> students, List<Map<String, dynamic>> subjects})> _load() {
    final s = context.read<SessionController>();
    final (from, to) = _dates;
    List<Map<String, dynamic>> l(dynamic v) => (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return s.run(() async {
      final p = {'p_class_id': widget.cls.id, 'p_from': from, 'p_to': to};
      return (students: l(await s.db.rpc('class_attendance_report', params: p)), subjects: l(await s.db.rpc('class_subject_attendance', params: p)));
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _export(List<Map<String, dynamic>> rows) async {
    final b = StringBuffer('Roll No,Name,Conducted,Present,Absent,Percentage,Low attendance\n');
    for (final r in rows) {
      final name = '"${(r['full_name'] as String).replaceAll('"', '""')}"';
      b.writeln('${r['roll_no']},$name,${r['conducted']},${r['present']},${r['absent']},${r['percentage']},${r['is_low'] == true ? 'YES' : 'no'}');
    }
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/attendance_${widget.cls.label.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(b.toString());
      await Share.shareXFiles([XFile(file.path)], subject: 'Attendance report - ${widget.cls.label}');
    } catch (_) {
      if (mounted) toast(context, 'Could not create the report file.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.cls.label)),
        body: FutureBuilder(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final d = snap.data!;
            final low = d.students.where((r) => r['is_low'] == true).toList();
            final conducted = d.students.fold<int>(0, (a, r) => a + n(r['conducted']).toInt());
            final present = d.students.fold<int>(0, (a, r) => a + n(r['present']).toInt());
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: '30', label: Text('30 days')), ButtonSegment(value: 'month', label: Text('This month')), ButtonSegment(value: 'all', label: Text('All'))],
                  selected: {_range}, onSelectionChanged: (s) { _range = s.first; _reload(); }),
                const SizedBox(height: 18),
                Row(children: [
                  StatChip('Class attendance', '${attendancePercent(present, conducted).toStringAsFixed(1)}%', color: AppColors.brass), const SizedBox(width: 10),
                  StatChip('Students', '${d.students.length}'), const SizedBox(width: 10),
                  StatChip('Low', '${low.length}', color: low.isEmpty ? AppColors.mint : AppColors.coral),
                ]),
                const SizedBox(height: 22),
                if (low.isNotEmpty) ...[
                  Text('Low attendance', style: display(20, c: AppColors.coral)),
                  const SizedBox(height: 8),
                  for (final r in low) _StudentTile(r, onTap: () => _open(r)),
                  const SizedBox(height: 18),
                ],
                Text('Across all subjects', style: display(20)),
                const SizedBox(height: 8),
                if (d.subjects.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No attendance marked in this period.', style: TextStyle(color: AppColors.muted))),
                for (final s in d.subjects) ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s['subject_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${s['sessions']} classes held', style: const TextStyle(color: AppColors.muted)),
                  trailing: Text('${n(s['percentage']).toStringAsFixed(1)}%', style: display(18, c: attColor(n(s['percentage']).toDouble(), 75))),
                ),
                const SizedBox(height: 18),
                Text('Whole class (by roll number)', style: display(20)),
                const SizedBox(height: 8),
                for (final r in d.students) _StudentTile(r, onTap: () => _open(r)),
                const SizedBox(height: 18),
                OutlinedButton.icon(onPressed: d.students.isEmpty ? null : () => _export(d.students), icon: const Icon(Icons.ios_share), label: const Text('Share CSV report'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
              ]),
            );
          },
        ),
      );

  void _open(Map<String, dynamic> r) => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MyAttendanceScreen(studentId: r['student_id'] as String, studentName: r['full_name'] as String)));
}

class _StudentTile extends StatelessWidget {
  final Map<String, dynamic> r;
  final VoidCallback onTap;
  const _StudentTile(this.r, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final pct = n(r['percentage']).toDouble();
    final none = n(r['conducted']) == 0;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
      onTap: onTap,
      leading: Text('${r['roll_no']}', style: display(18, c: AppColors.brass)),
      title: Text(r['full_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${r['present']} present, ${r['absent']} absent of ${r['conducted']}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      trailing: Text(none ? '-' : '${pct.toStringAsFixed(1)}%', style: display(18, c: attColor(pct, 75, none: none))),
    )));
  }
}
