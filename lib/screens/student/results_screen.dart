import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../pdf/pdf_docs.dart';
import '../../services/cache.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Published results for the signed-in student. [rankOnly] opens the Percentage & Rank view first.
class ResultsScreen extends StatefulWidget {
  final bool rankOnly;
  const ResultsScreen({super.key, this.rankOnly = false});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late Future<({List<Map<String, dynamic>> results, List<Map<String, dynamic>> upcoming, bool offline})> _f = _load();

  Future<({List<Map<String, dynamic>> results, List<Map<String, dynamic>> upcoming, bool offline})> _load() async {
    final s = context.read<SessionController>();
    final key = '${s.cachePrefix}results';
    try {
      final r = await s.run(() async {
        final res = asList(await s.db.rpc('my_results'));
        final cls = await myClassId(s);
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final up = asList(await s.db.from('examinations').select().eq('class_id', cls).gte('starts_on', today).order('starts_on'));
        return {'results': res, 'upcoming': up};
      });
      await LocalCache.put(key, r);
      return (results: asList(r['results']), upcoming: asList(r['upcoming']), offline: false);
    } catch (e) {
      final c = await LocalCache.get(key);
      if (c != null) {
        final m = Map<String, dynamic>.from(c.value as Map);
        return (results: asList(m['results']), upcoming: asList(m['upcoming']), offline: true);
      }
      rethrow;
    }
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.rankOnly ? 'Percentage & Rank' : 'Examination Results')),
        body: SafeArea(child: FutureBuilder(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final d = snap.data!;
            final u = context.read<SessionController>().user!;
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                if (d.offline) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Offline - showing your last saved results.', style: TextStyle(color: AppColors.amber))),
                if (d.upcoming.isNotEmpty) ...[
                  Text('Upcoming examinations', style: display(19)),
                  const SizedBox(height: 8),
                  for (final e in d.upcoming) Card(child: ListTile(
                    leading: const Icon(Icons.event_note_outlined, color: AppColors.brass),
                    title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(DateFormat('EEE d MMM yyyy').format(DateTime.parse(e['starts_on'] as String))))),
                  const SizedBox(height: 16),
                ],
                if (d.results.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: EmptyView(Icons.fact_check_outlined, 'No results have been published yet.')),
                for (final r in d.results) _ResultCard(result: r, name: u.fullName, year: u.yearLevel ?? 1, roll: u.loginId),
              ]),
            );
          },
        )),
      );
}

class _ResultCard extends StatelessWidget {
  final Map<String, dynamic> result;
  final String name, roll;
  final int year;
  const _ResultCard({required this.result, required this.name, required this.year, required this.roll});

  @override
  Widget build(BuildContext context) {
    final subjects = asList(result['subjects']);
    final passed = result['passed'] == true;
    return Padding(padding: const EdgeInsets.only(bottom: 14), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(result['exam_name'] as String, style: display(21))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: (passed ? AppColors.mint : AppColors.coral).withOpacity(.18), borderRadius: BorderRadius.circular(8)),
          child: Text(passed ? 'PASS' : 'FAIL', style: TextStyle(fontWeight: FontWeight.w800, color: passed ? AppColors.mint : AppColors.coral)),
        ),
      ]),
      const Divider(height: 22),
      for (final s in subjects) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
        Expanded(child: Text(s['subject'] as String)),
        Text('${_t(s['obtained'])} / ${_t(s['max'])}', style: TextStyle(fontWeight: FontWeight.w600, color: s['passed'] == true ? AppColors.text : AppColors.coral)),
      ])),
      const Divider(height: 22),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Total'), Text('${_t(result['total_obtained'])} / ${_t(result['total_max'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Percentage'), Text(pct(n(result['percentage'])), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brass)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RankScreen(result: result))),
          icon: const Icon(Icons.emoji_events_outlined), label: const Text('Percentage & Rank'))),
        const SizedBox(width: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(56, 48)),
          onPressed: () async {
            try { await shareReportCard(name, year, roll, result); } catch (_) { if (context.mounted) toast(context, 'Could not create the report card.', error: true); }
          },
          child: const Icon(Icons.picture_as_pdf_outlined)),
      ]),
    ]))));
  }
}

String _t(dynamic v) {
  final d = n(v).toDouble();
  return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
}

/// Congratulation screen with percentage, total marks and class rank.
class RankScreen extends StatefulWidget {
  final Map<String, dynamic> result;
  const RankScreen({super.key, required this.result});
  @override
  State<RankScreen> createState() => _RankScreenState();
}

class _RankScreenState extends State<RankScreen> {
  int? get _rank => widget.result['rank'] as int?;

  (String, String, IconData, Color) _message() {
    final r = _rank;
    if (r == 1) return ('Congratulations!', 'You secured Rank 1 in your class!', Icons.emoji_events, AppColors.brass);
    if (r == 2) return ('Excellent work!', 'You secured Rank 2 in your class!', Icons.military_tech, const Color(0xFFC9D1E8));
    if (r == 3) return ('Great job!', 'You secured Rank 3 in your class!', Icons.military_tech, const Color(0xFFD99A6C));
    if (r == 4 || r == 5) return ('Well done!', 'You secured Rank $r - you are in the top five!', Icons.star_rounded, AppColors.mint);
    if (r != null) return ('Keep going!', 'You secured Rank $r in your class. Every exam is a chance to climb.', Icons.trending_up, AppColors.mint);
    return ('Your result', 'Your class rank will appear once every subject is published.', Icons.hourglass_empty, AppColors.muted);
  }

  @override
  void initState() {
    super.initState();
    if (_rank != null) WidgetsBinding.instance.addPostFrameCallback((_) => _celebrate());
  }

  void _celebrate() {
    final (t, m, icon, col) = _message();
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        icon: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 1), duration: const Duration(milliseconds: 700), curve: Curves.elasticOut,
          builder: (_, v, child) => Transform.scale(scale: v, child: child), child: Icon(icon, size: 64, color: col)),
        title: Text(t, textAlign: TextAlign.center), content: Text(m, textAlign: TextAlign.center),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Continue'))],
      ),
    );
  }

  Future<void> _merit() async {
    final s = context.read<SessionController>();
    try {
      final l = await s.run(() async => asList(await s.db.rpc('exam_merit_list', params: {'p_exam': widget.result['exam_id']})));
      if (!mounted) return;
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: AppColors.surface,
        builder: (c) => SafeArea(child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Class merit list', style: display(22))),
            Flexible(child: ListView(shrinkWrap: true, children: [
              for (final r in l) ListTile(
                tileColor: r['is_me'] == true ? AppColors.surfaceHi : null,
                leading: CircleAvatar(backgroundColor: AppColors.ink, child: Text('${r['rank']}', style: const TextStyle(fontWeight: FontWeight.w800))),
                title: Text(r['full_name'] as String, style: TextStyle(fontWeight: r['is_me'] == true ? FontWeight.w800 : FontWeight.w500)),
                subtitle: Text('Roll ${r['roll_no']}'),
                trailing: Text(pct(n(r['percentage'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ])),
          ]),
        )),
      );
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final (title, msg, icon, col) = _message();
    final subjects = asList(r['subjects']);
    final p = n(r['percentage']).toDouble();
    return Scaffold(
      appBar: AppBar(title: Text(r['exam_name'] as String)),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
        Card(child: Padding(padding: const EdgeInsets.all(22), child: Column(children: [
          Icon(icon, size: 56, color: col),
          const SizedBox(height: 8),
          Text(title, style: display(28)),
          const SizedBox(height: 4),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          const SizedBox(height: 18),
          PercentRing(pct: p, color: p >= 75 ? AppColors.mint : p >= 50 ? AppColors.amber : AppColors.coral, size: 150, label: 'Your percentage'),
          const SizedBox(height: 16),
          Row(children: [
            StatChip('Total marks', '${_t(r['total_obtained'])}/${_t(r['total_max'])}'),
            const SizedBox(width: 10),
            StatChip('Rank', _rank == null ? '-' : '$_rank / ${r['ranked_students']}', color: col),
          ]),
        ]))),
        const SizedBox(height: 14),
        Text('Subject-wise performance', style: display(19)),
        const SizedBox(height: 8),
        for (final s in subjects) Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(s['subject'] as String), Text('${_t(s['obtained'])}/${_t(s['max'])}  (${pct(n(s['percentage']))})')]),
          const SizedBox(height: 4),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(
            value: (n(s['percentage']).toDouble() / 100).clamp(0.0, 1.0), minHeight: 8, backgroundColor: AppColors.surfaceHi,
            color: n(s['percentage']) >= 75 ? AppColors.mint : n(s['percentage']) >= 50 ? AppColors.amber : AppColors.coral)),
        ])),
        const SizedBox(height: 16),
        if (_rank != null) OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _merit, icon: const Icon(Icons.format_list_numbered), label: const Text('View class merit list')),
      ])),
    );
  }
}
