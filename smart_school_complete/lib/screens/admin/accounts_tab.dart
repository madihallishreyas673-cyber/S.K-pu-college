import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'teacher_assignments_screen.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});
  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  String _role = 'student', _q = '';
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final r = await s.db.from('users').select('id,role,login_id,year_level,full_name,status').eq('role', _role).order('full_name');
      return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _resetPin(Map<String, dynamic> u) async {
    final pin = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reset PIN for ${u['full_name']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter a temporary 6-digit PIN. They must choose their own PIN at next sign in.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          PinField(pin, label: 'Temporary PIN'),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(90, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Reset'))],
      ),
    );
    if (ok != true) return;
    try {
      await context.read<SessionController>().adminAction({'action': 'reset_pin', 'user_id': u['id'], 'new_pin': pin.text});
      if (mounted) toast(context, 'PIN reset. Share the temporary PIN privately.');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
  }

  Future<void> _toggle(Map<String, dynamic> u) async {
    final next = u['status'] == 'active' ? 'disabled' : 'active';
    try {
      await context.read<SessionController>().adminAction({'action': 'set_status', 'user_id': u['id'], 'status': next});
      if (mounted) toast(context, next == 'disabled' ? 'Account disabled' : 'Account enabled');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
    _reload();
  }

  Future<void> _purge() async {
    try {
      final r = await context.read<SessionController>().adminAction({'action': 'purge_photos'});
      if (mounted) toast(context, '${r['deleted']} leftover ID photo(s) deleted');
    } catch (e) {
      if (mounted) toast(context, friendly(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(children: [
            Expanded(child: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'student', label: Text('Students')), ButtonSegment(value: 'teacher', label: Text('Teachers')), ButtonSegment(value: 'office', label: Text('Office'))],
              selected: {_role}, onSelectionChanged: (s) { _role = s.first; _reload(); })),
            PopupMenuButton<String>(onSelected: (_) => _purge(), itemBuilder: (_) => const [PopupMenuItem(value: 'purge', child: Text('Delete leftover ID photos'))]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(onChanged: (v) => setState(() => _q = v.trim().toLowerCase()), decoration: const InputDecoration(hintText: 'Search name or ID', prefixIcon: Icon(Icons.search))),
        ),
        const SizedBox(height: 8),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final rows = snap.data!.where((u) => _q.isEmpty || (u['full_name'] as String).toLowerCase().contains(_q) || (u['login_id'] as String).toLowerCase().contains(_q)).toList();
            if (rows.isEmpty) return const EmptyView(Icons.person_search_outlined, 'No accounts found.');
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final u = rows[i];
                  final off = u['status'] != 'active';
                  return Card(child: ListTile(
                    title: Text(u['full_name'] as String, style: TextStyle(fontWeight: FontWeight.w700, color: off ? AppColors.muted : AppColors.text)),
                    subtitle: Text(u['role'] == 'student' ? '${yearName(u['year_level'] as int)}  -  Roll ${u['login_id']}${off ? '  -  disabled' : ''}' : 'ID ${u['login_id']}${off ? '  -  disabled' : ''}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'pin') _resetPin(u);
                        if (v == 'toggle') _toggle(u);
                        if (v == 'assign') Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeacherAssignmentsScreen(teacherId: u['id'] as String, teacherName: u['full_name'] as String)));
                      },
                      itemBuilder: (_) => [
                        if (u['role'] == 'teacher') const PopupMenuItem(value: 'assign', child: Text('Subjects and classes')),
                        const PopupMenuItem(value: 'pin', child: Text('Reset PIN')),
                        PopupMenuItem(value: 'toggle', child: Text(off ? 'Enable account' : 'Disable account')),
                      ],
                    ),
                  ));
                },
              ),
            );
          },
        )),
      ]);
}
