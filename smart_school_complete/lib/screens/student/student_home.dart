import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../change_pin_screen.dart';
import 'my_attendance_screen.dart';
import 'results_screen.dart';
import 'fees_screen.dart';
import 'subjects_screen.dart';
import 'assistant_screen.dart';
import 'announcements_screen.dart';
import '../shared/content_view.dart';
import '../shared/notifications_screen.dart';
import '../../widgets/tiles.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  Future<Map<String, dynamic>>? _f;

  Future<Map<String, dynamic>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => Map<String, dynamic>.from(await s.db.rpc('attendance_summary') as Map));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => setState(() => _f = _load()));
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user!;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _f = _load()),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            Row(children: [
              const Expanded(child: BrandBar()),
              const BellButton(),
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: () => context.read<SessionController>().logout()),
            ]),
            const SizedBox(height: 22),
            Text('Hello, ${u.fullName.split(' ').first}', style: display(30)),
            const SizedBox(height: 4),
            Text('${yearName(u.yearLevel ?? 1)}  -  Roll no. ${u.loginId}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            _AttendanceCard(future: _f, onOpen: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyAttendanceScreen())).then((_) => setState(() => _f = _load()))),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.35,
              children: [
                _Tile(Icons.person_outline, 'My Profile', () => _profile(context)),
                _Tile(Icons.menu_book_outlined, 'My Subjects', () => _go(const SubjectsScreen())),
                _Tile(Icons.description_outlined, 'Notes', () => _go(const StudentContentScreen(title: 'Notes', initialTab: 0))),
                _Tile(Icons.play_circle_outline, 'Videos', () => _go(const StudentContentScreen(title: 'Videos', initialTab: 1))),
                _Tile(Icons.videocam_outlined, 'Live Classes', () => _go(const StudentContentScreen(title: 'Live Classes', initialTab: 2))),
                _Tile(Icons.fact_check_outlined, 'Examination Results', () => _go(const ResultsScreen())),
                _Tile(Icons.emoji_events_outlined, 'Percentage & Rank', () => _go(const ResultsScreen(rankOnly: true))),
                _Tile(Icons.campaign_outlined, 'Announcements', () => _go(const AnnouncementsScreen())),
                _Tile(Icons.account_balance_wallet_outlined, 'My Fees', () => _go(const MyFeesScreen())),
                _Tile(Icons.psychology_outlined, 'Study Assistant', () => _go(const AssistantScreen())),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  void _profile(BuildContext context) {
    final u = context.read<SessionController>().user!;
    showModalBottomSheet(
      context: context, backgroundColor: AppColors.surface,
      builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(u.fullName, style: display(24)),
        const SizedBox(height: 6),
        Text('${yearName(u.yearLevel ?? 1)}  -  Roll no. ${u.loginId}', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () { Navigator.pop(c); Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePinScreen())); },
          icon: const Icon(Icons.lock_reset), label: const Text('Change PIN'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
      ]))),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _Tile(this.icon, this.title, this.onTap);
  @override
  Widget build(BuildContext context) => Card(child: InkWell(
        borderRadius: BorderRadius.circular(16), onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Icon(icon, color: AppColors.brass),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        ])),
      ));
}

class _AttendanceCard extends StatelessWidget {
  final Future<Map<String, dynamic>>? future;
  final VoidCallback onOpen;
  const _AttendanceCard({required this.future, required this.onOpen});
  @override
  Widget build(BuildContext context) => Card(child: InkWell(
        borderRadius: BorderRadius.circular(16), onTap: onOpen,
        child: Padding(padding: const EdgeInsets.all(16), child: FutureBuilder<Map<String, dynamic>>(
          future: future,
          builder: (c, snap) {
            Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = const SizedBox(height: 72, child: Center(child: CircularProgressIndicator(color: AppColors.brass, strokeWidth: 2.5)));
            } else if (snap.hasError) {
              body = const SizedBox(height: 72, child: Center(child: Text('Tap to open My Attendance', style: TextStyle(color: AppColors.muted))));
            } else {
              final s = AttSummary.fromJson(snap.data!);
              final none = s.overall.conducted == 0;
              body = Row(children: [
                PercentRing(pct: s.overall.pct, color: attColor(s.overall.pct, s.threshold, none: none), size: 84),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('My Attendance', style: display(20)),
                  const SizedBox(height: 4),
                  Text(none ? 'Nothing marked yet' : '${s.overall.present} present, ${s.overall.absent} absent', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  if (s.isLow) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Below the required level', style: TextStyle(color: AppColors.coral, fontSize: 13, fontWeight: FontWeight.w600))),
                ])),
                const Icon(Icons.chevron_right, color: AppColors.muted),
              ]);
            }
            return body;
          },
        )),
      ));
}
