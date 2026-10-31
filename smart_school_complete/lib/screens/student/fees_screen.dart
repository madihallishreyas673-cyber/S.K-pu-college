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

/// The signed-in student's own fee account. Staff screens reuse [FeeSummaryCard] and [PaymentTile].
class MyFeesScreen extends StatefulWidget {
  const MyFeesScreen({super.key});
  @override
  State<MyFeesScreen> createState() => _MyFeesScreenState();
}

class _MyFeesScreenState extends State<MyFeesScreen> {
  late Future<(Map<String, dynamic>, bool)> _f = _load();

  Future<(Map<String, dynamic>, bool)> _load() async {
    final s = context.read<SessionController>();
    final key = '${s.cachePrefix}fees';
    try {
      final r = Map<String, dynamic>.from(await s.run(() => s.db.rpc('fee_account')) as Map);
      await LocalCache.put(key, r);
      return (r, false);
    } catch (e) {
      final c = await LocalCache.get(key);
      if (c != null) return (Map<String, dynamic>.from(c.value as Map), true);
      rethrow;
    }
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('My Fees')),
        body: SafeArea(child: FutureBuilder(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final (a, offline) = snap.data!;
            final pays = asList(a['payments']);
            return RefreshIndicator(onRefresh: () async => _reload(), child: ListView(padding: const EdgeInsets.all(16), children: [
              if (offline) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Offline - showing your last saved fee account.', style: TextStyle(color: AppColors.amber))),
              if (a['has_account'] != true) const EmptyView(Icons.account_balance_wallet_outlined, 'Your fee account has not been set up by the office yet.')
              else FeeSummaryCard(account: a),
              if (pays.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Payment history', style: display(19)),
                const SizedBox(height: 8),
                for (final p in pays) PaymentTile(account: a, payment: p),
              ],
            ]));
          },
        )),
      );
}

class FeeSummaryCard extends StatelessWidget {
  final Map<String, dynamic> account;
  const FeeSummaryCard({super.key, required this.account});
  @override
  Widget build(BuildContext context) {
    final total = n(account['total']).toDouble(), paid = n(account['paid']).toDouble(), rem = n(account['remaining']).toDouble();
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
      Row(children: [
        PercentRing(pct: total == 0 ? 0 : paid * 100 / total, color: rem == 0 ? AppColors.mint : AppColors.brass, size: 96, label: 'paid'),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Remaining', style: const TextStyle(color: AppColors.muted)),
          Text(money(rem), style: display(30, c: rem == 0 ? AppColors.mint : AppColors.text)),
          if (rem == 0) const Text('All fees paid', style: TextStyle(color: AppColors.mint, fontWeight: FontWeight.w600)),
        ])),
      ]),
      const SizedBox(height: 14),
      Row(children: [StatChip('Total fees', money(total)), const SizedBox(width: 10), StatChip('Paid', money(paid), color: AppColors.mint)]),
      if (account['year_label'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Academic year ${account['year_label']}', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
    ])));
  }
}

class PaymentTile extends StatelessWidget {
  final Map<String, dynamic> account, payment;
  final Widget? extra;
  const PaymentTile({super.key, required this.account, required this.payment, this.extra});
  @override
  Widget build(BuildContext context) {
    final voided = payment['is_void'] == true;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
      leading: Icon(voided ? Icons.block : Icons.receipt_long_outlined, color: voided ? AppColors.coral : AppColors.brass),
      title: Text(money(n(payment['amount'])), style: TextStyle(fontWeight: FontWeight.w700, decoration: voided ? TextDecoration.lineThrough : null)),
      subtitle: Text('Ref ${payment['reference_no']}  -  ${DateFormat('d MMM yyyy').format(DateTime.parse(payment['paid_on'] as String))}'
          '${voided ? '\nVOID: ${payment['void_reason']}' : ''}'),
      isThreeLine: voided,
      trailing: voided ? extra : Row(mainAxisSize: MainAxisSize.min, children: [
        if (extra != null) extra!,
        IconButton(
          tooltip: 'Download receipt (PDF)', icon: const Icon(Icons.download_outlined),
          onPressed: () async {
            try { await shareReceipt(account, payment); } catch (_) { if (context.mounted) toast(context, 'Could not create the receipt.', error: true); }
          }),
      ]),
    )));
  }
}
