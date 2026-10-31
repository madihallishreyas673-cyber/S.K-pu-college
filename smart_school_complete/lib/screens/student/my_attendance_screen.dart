import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/cache.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Shows attendance for the signed-in student, or (when [studentId] is given) for a student
/// the class teacher / administrator is allowed to view. The database enforces who may call this.
class MyAttendanceScreen extends StatefulWidget {
  final String? studentId, studentName;
  const MyAttendanceScreen({super.key, this.studentId, this.studentName});
  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  late Future<_Data> _f = _load();
  bool _offlineCopy = false;

  Future<_Data> _load() async {
    final s = context.read<SessionController>();
    final key = '${s.cachePrefix}att';
    final own = widget.studentId == null;
    try {
      final r = await s.run(() async {
        final sum = await s.db.rpc('attendance_summary', params: {'p_student': widget.studentId});
        final daily = await s.db.rpc('attendance_daily', params: {'p_student': widget.studentId});
        final monthly = await s.db.rpc('attendance_monthly', params: {'p_student': widget.studentId});
        return {'summary': sum, 'daily': daily, 'monthly': monthly};
      });
      if (own) await LocalCache.put(key, r);
      _offlineCopy = false;
      return _Data.from(r);
    } catch (e) {
      if (own) {
        final c = await LocalCache.get(key);
        if (c != null) {
          _offlineCopy = true;
          return _Data.from(Map<String, dynamic>.from(c.value as Map), savedAt: c.savedAt);
        }
      }
      rethrow;
    }
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.studentName ?? 'My Attendance'),
            bottom: const TabBar(
              indicatorColor: AppColors.brass, labelColor: AppColors.brass, unselectedLabelColor: AppColors.muted,
              tabs: [Tab(text: 'Overview'), Tab(text: 'Daily'), Tab(text: 'Monthly')]),
          ),
          body: FutureBuilder<_Data>(
            future: _f,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) return ErrorView(snap.error!, _reload);
              final d = snap.data!;
              return Column(children: [
                if (_offlineCopy) Container(
                  width: double.infinity, color: AppColors.surfaceHi, padding: const EdgeInsets.all(10),
                  child: Text('Offline. Showing data saved ${DateFormat('d MMM, h:mm a').format(d.savedAt!)}.',
                      style: const TextStyle(color: AppColors.amber, fontSize: 13), textAlign: TextAlign.center),
                ),
                Expanded(child: TabBarView(children: [
                  RefreshIndicator(onRefresh: () async => _reload(), child: _Overview(d.summary)),
                  RefreshIndicator(onRefresh: () async => _reload(), child: _Daily(d.daily)),
                  RefreshIndicator(onRefresh: () async => _reload(), child: _Monthly(d.monthly, d.summary.threshold)),
                ])),
              ]);
            },
          ),
        ),
      );
}

class _Data {
  final AttSummary summary;
  final List<Map<String, dynamic>> daily, monthly;
  final DateTime? savedAt;
  _Data(this.summary, this.daily, this.monthly, this.savedAt);
  static List<Map<String, dynamic>> _l(dynamic v) => (v as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  factory _Data.from(Map<String, dynamic> r, {DateTime? savedAt}) =>
      _Data(AttSummary.fromJson(Map<String, dynamic>.from(r['summary'] as Map)), _l(r['daily']), _l(r['monthly']), savedAt);
}

class _Overview extends StatelessWidget {
  final AttSummary s;
  const _Overview(this.s);
  @override
  Widget build(BuildContext context) {
    final none = s.overall.conducted == 0;
    final color = attColor(s.overall.pct, s.threshold, none: none);
    return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), children: [
      if (s.isLow) Container(
        margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.coral.withOpacity(0.14), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.coral)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.coral),
          const SizedBox(width: 10),
          Expanded(child: Text('Attendance is below ${s.threshold.toStringAsFixed(0)}%. Attend regularly to avoid shortage.', style: const TextStyle(fontSize: 14))),
        ]),
      ),
      Center(child: PercentRing(pct: s.overall.pct, color: color, size: 170, label: 'overall')),
      const SizedBox(height: 20),
      Row(children: [
        StatChip('Present', '${s.overall.present}', color: AppColors.mint), const SizedBox(width: 10),
        StatChip('Absent', '${s.overall.absent}', color: AppColors.coral), const SizedBox(width: 10),
        StatChip('Conducted', '${s.overall.conducted}'),
      ]),
      const SizedBox(height: 8),
      const Text('Overall = total present classes / total conducted classes across all subjects.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
      const SizedBox(height: 22),
      Text('By subject', style: display(20)),
      const SizedBox(height: 10),
      if (s.subjects.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('No attendance has been marked yet.', style: TextStyle(color: AppColors.muted))),
      for (final sub in s.subjects) Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            Row(children: [
              Expanded(child: Text(sub.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              Text('${sub.stat.pct.toStringAsFixed(1)}%', style: display(18, c: attColor(sub.stat.pct, s.threshold))),
            ]),
            const SizedBox(height: 8),
            ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
              value: (sub.stat.pct / 100).clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppColors.surfaceHi,
              color: attColor(sub.stat.pct, s.threshold))),
            const SizedBox(height: 6),
            Align(alignment: Alignment.centerLeft, child: Text(
              '${sub.stat.present} present, ${sub.stat.absent} absent of ${sub.stat.conducted}${sub.stat.pct < s.threshold ? '  -  low' : ''}',
              style: TextStyle(color: sub.stat.pct < s.threshold ? AppColors.coral : AppColors.muted, fontSize: 12))),
          ]),
        )),
      ),
    ]);
  }
}

class _Daily extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _Daily(this.rows);
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return ListView(children: const [SizedBox(height: 120), EmptyView(Icons.event_note_outlined, 'No attendance has been marked yet.')]);
    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) { byDate.putIfAbsent(r['session_date'] as String, () => []).add(r); }
    final dates = byDate.keys.toList();
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), itemCount: dates.length,
      itemBuilder: (_, i) {
        final items = byDate[dates[i]]!;
        final p = items.where((e) => e['status'] == 'P').length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(DateFormat('EEE, d MMM yyyy').format(DateTime.parse(dates[i])), style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('$p/${items.length} present', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            for (final r in items) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              Container(
                width: 28, height: 28, alignment: Alignment.center,
                decoration: BoxDecoration(color: (r['status'] == 'P' ? AppColors.mint : AppColors.coral).withOpacity(0.18), borderRadius: BorderRadius.circular(8)),
                child: Text(r['status'] as String, style: TextStyle(fontWeight: FontWeight.w800, color: r['status'] == 'P' ? AppColors.mint : AppColors.coral)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('${r['subject_name']}  (period ${r['period']})')),
              Text(r['teacher_name'] as String, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ])),
          ]))),
        );
      },
    );
  }
}

class _Monthly extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final double threshold;
  const _Monthly(this.rows, this.threshold);
  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return ListView(children: const [SizedBox(height: 120), EmptyView(Icons.calendar_month_outlined, 'No monthly report yet.')]);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(20), itemCount: rows.length,
      itemBuilder: (_, i) {
        final r = rows[i];
        final pct = n(r['percentage']).toDouble();
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          PercentRing(pct: pct, color: attColor(pct, threshold), size: 64),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('MMMM yyyy').format(DateTime.parse(r['month'] as String)), style: display(18)),
            const SizedBox(height: 4),
            Text('${r['present']} present, ${r['absent']} absent, ${r['conducted']} classes', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ])),
        ]))));
      },
    );
  }
}
