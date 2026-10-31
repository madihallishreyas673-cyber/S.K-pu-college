import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../student/fees_screen.dart';

/// One student's fee account for office staff (add payments, set total) or the administrator (set total, void).
class StudentFeeScreen extends StatefulWidget {
  final String studentId, studentName;
  const StudentFeeScreen({super.key, required this.studentId, required this.studentName});
  @override
  State<StudentFeeScreen> createState() => _StudentFeeScreenState();
}

class _StudentFeeScreenState extends State<StudentFeeScreen> {
  late Future<Map<String, dynamic>> _f = _load();
  final _amount = TextEditingController(), _ref = TextEditingController();
  bool _busy = false;

  Future<Map<String, dynamic>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => Map<String, dynamic>.from(await s.db.rpc('fee_account', params: {'p_student': widget.studentId}) as Map));
  }

  void _reload() => setState(() => _f = _load());
  bool get _isOffice => context.read<SessionController>().user!.role == 'office';

  Future<void> _addPayment(Map<String, dynamic> a) async {
    final amt = num.tryParse(_amount.text.trim().replaceAll(',', ''));
    final ref = _ref.text.trim();
    final remaining = n(a['remaining']);
    if (amt == null || amt <= 0) { toast(context, 'Enter the amount received.', error: true); return; }
    if (amt > remaining) { toast(context, 'That is more than the remaining ${money(remaining)}.', error: true); return; }
    if (ref.length < 3) { toast(context, 'Enter the receipt / transaction reference.', error: true); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm payment'),
        content: Text('${widget.studentName}\nAmount: ${money(amt)}\nReference: $ref\n\nRemaining after this payment: ${money(remaining - amt)}.\n\nPayments cannot be edited or deleted afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Add payment')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('add_payment', params: {'p_student': widget.studentId, 'p_amount': amt, 'p_reference': ref}));
      _amount.clear(); _ref.clear();
      if (mounted) toast(context, 'Payment added');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) { setState(() => _busy = false); _reload(); }
  }

  Future<void> _setTotal(Map<String, dynamic> a) async {
    final c0 = TextEditingController(text: a['has_account'] == true ? '${n(a['total'])}' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(a['has_account'] == true ? 'Change total fees' : 'Set total fees'),
        content: TextField(controller: c0, autofocus: true, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'Total school fees (Rs.)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    final v = num.tryParse(c0.text.trim());
    if (ok != true || v == null) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('set_total_fee', params: {'p_student': widget.studentId, 'p_total': v}));
      if (mounted) toast(context, 'Total fees saved (logged)');
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  Future<void> _void(Map<String, dynamic> p) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Void this payment?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${money(n(p['amount']))}  -  Ref ${p['reference_no']}\nIt stays visible in the history, marked VOID, and the balance is restored.'),
          const SizedBox(height: 10),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (required)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44), backgroundColor: AppColors.coral), onPressed: () => Navigator.pop(c, true), child: const Text('Void')),
        ],
      ),
    );
    if (ok != true) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('void_payment', params: {'p_payment': p['id'], 'p_reason': reason.text}));
      if (mounted) toast(context, 'Payment voided (logged)');
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.read<SessionController>().user!.role;
    return Scaffold(
      appBar: AppBar(title: Text(widget.studentName)),
      body: SafeArea(child: FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(snap.error!, _reload);
          final a = snap.data!;
          final st = Map<String, dynamic>.from(a['student'] as Map);
          final pays = asList(a['payments']);
          final has = a['has_account'] == true;
          return RefreshIndicator(onRefresh: () async => _reload(), child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('Roll no. ${st['roll_no']}  -  ${yearName(st['year_level'] as int)}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 10),
            if (!has) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              const Text('No fee account yet. Set the total school fees to begin.'),
              const SizedBox(height: 10),
              FilledButton(onPressed: () => _setTotal(a), child: const Text('Set total fees')),
            ])))
            else ...[
              FeeSummaryCard(account: a),
              TextButton.icon(onPressed: () => _setTotal(a), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Change total fees')),
              if (role == 'office') ...[
                const SizedBox(height: 6),
                Text('Add payment', style: display(19)),
                const SizedBox(height: 8),
                if (n(a['remaining']) == 0) const Text('Nothing remaining - all fees are paid.', style: TextStyle(color: AppColors.mint))
                else ...[
                  TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], decoration: const InputDecoration(labelText: 'Amount received (Rs.)', prefixIcon: Icon(Icons.currency_rupee))),
                  const SizedBox(height: 10),
                  TextField(controller: _ref, maxLength: 40, decoration: const InputDecoration(labelText: 'Receipt / transaction reference (unique)', prefixIcon: Icon(Icons.tag))),
                  FilledButton.icon(onPressed: _busy ? null : () => _addPayment(a), icon: const Icon(Icons.add_card), label: const Text('Add payment')),
                ],
              ],
            ],
            if (pays.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Payment history', style: display(19)),
              const SizedBox(height: 8),
              for (final p in pays) PaymentTile(
                account: a, payment: p,
                extra: role == 'admin' && p['is_void'] != true ? IconButton(tooltip: 'Void payment', icon: const Icon(Icons.block, color: AppColors.coral), onPressed: () => _void(p)) : null),
            ],
          ]));
        },
      )),
    );
  }
}

/// Search box + results shared by office home and the administrator's fee view.
class FeeSearch extends StatefulWidget {
  const FeeSearch({super.key});
  @override
  State<FeeSearch> createState() => _FeeSearchState();
}

class _FeeSearchState extends State<FeeSearch> {
  final _q = TextEditingController();
  List<Map<String, dynamic>>? _rows;
  bool _busy = false;
  String? _error;

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _busy = true; _error = null; });
    final s = context.read<SessionController>();
    try {
      final r = asList(await s.run(() => s.db.rpc('fee_search', params: {'p_query': q})));
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() { _error = errText(e); _rows = null; });
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _q, textInputAction: TextInputAction.search, onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            labelText: 'Search by roll number or student name', prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search)),
        ),
        const Padding(padding: EdgeInsets.only(top: 4, left: 4), child: Text('A roll number shows the exact matching student only.', style: TextStyle(color: AppColors.muted, fontSize: 12))),
        const SizedBox(height: 10),
        if (_busy) const Padding(padding: EdgeInsets.all(24), child: LoadingView()),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: AppColors.coral))),
        if (_rows != null && _rows!.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No matching student.', style: TextStyle(color: AppColors.muted)))),
        for (final r in _rows ?? const <Map<String, dynamic>>[]) Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.surfaceHi, child: Text('${r['roll_no']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          title: Text(r['full_name'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(r['has_account'] == true ? '${yearName(r['year_level'] as int)}  -  Remaining ${money(n(r['remaining']))}' : '${yearName(r['year_level'] as int)}  -  fees not set'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => StudentFeeScreen(studentId: r['student_id'] as String, studentName: r['full_name'] as String))).then((_) => _search()),
        ))),
      ]);
}
