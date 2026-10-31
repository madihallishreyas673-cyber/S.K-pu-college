import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'review_screen.dart';

class ApprovalsTab extends StatefulWidget {
  const ApprovalsTab({super.key});
  @override
  State<ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<ApprovalsTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final r = await s.db.from('registrations').select().eq('status', 'pending').order('created_at');
      return (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    });
  }

  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _f,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(snap.error!, _reload);
          final rows = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: rows.isEmpty
                ? ListView(children: const [SizedBox(height: 120), EmptyView(Icons.task_alt, 'No registrations are waiting.')])
                : ListView.separated(
                    padding: const EdgeInsets.all(16), itemCount: rows.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final role = r['role'] as String;
                      return Card(child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: Icon(role == 'student' ? Icons.school_outlined : role == 'teacher' ? Icons.menu_book_outlined : Icons.receipt_long_outlined, color: AppColors.brass),
                        title: Text(r['full_name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(role == 'student'
                            ? 'Student  -  ${yearName(r['year_level'] as int)}  -  Roll ${r['login_id']}'
                            : '${role == 'teacher' ? 'Teacher' : 'Office'}  -  ID ${r['login_id']}\nSent ${DateFormat('d MMM, h:mm a').format(DateTime.parse(r['created_at'] as String).toLocal())}'),
                        isThreeLine: role != 'student',
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReviewScreen(reg: r)));
                          if (changed == true) _reload();
                        },
                      ));
                    },
                  ),
          );
        },
      );
}
