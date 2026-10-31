import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../change_pin_screen.dart';
import '../shared/notifications_screen.dart';
import 'student_fee_screen.dart';

/// Office staff: find a student, record fee payments, see the school collection summary.
class OfficeHome extends StatefulWidget {
  const OfficeHome({super.key});
  @override
  State<OfficeHome> createState() => _OfficeHomeState();
}

class _OfficeHomeState extends State<OfficeHome> {
  late Future<Map<String, dynamic>> _sum = _load();

  Future<Map<String, dynamic>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => Map<String, dynamic>.from(await s.db.rpc('fee_summary') as Map));
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user!;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => setState(() => _sum = _load()),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
            Row(children: [
              const Expanded(child: BrandBar()),
              const BellButton(),
              IconButton(icon: const Icon(Icons.lock_reset), tooltip: 'Change PIN', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePinScreen()))),
              IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: () => context.read<SessionController>().logout()),
            ]),
            const SizedBox(height: 22),
            Text(u.fullName, style: display(28)),
            const Text('Office staff - Fees', style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 18),
            const FeeSearch(),
            const SizedBox(height: 22),
            FutureBuilder<Map<String, dynamic>>(
              future: _sum,
              builder: (c, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                final m = snap.data!;
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('School collection ${m['year_label'] ?? ''}', style: display(19)),
                  const SizedBox(height: 8),
                  Row(children: [StatChip('Collected', money(n0(m['collected'])), color: AppColors.mint), const SizedBox(width: 10), StatChip('Remaining', money(n0(m['remaining'])), color: AppColors.amber)]),
                  const SizedBox(height: 8),
                  Text('${m['students_with_dues']} of ${m['students_with_account']} students with fee accounts still have dues.', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

num n0(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;
