import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('notifications').select().order('created_at', ascending: false).limit(100)));
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _markAll() async {
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('notifications').update({'is_read': true}).eq('is_read', false));
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _reload();
  }

  Future<void> _markOne(String id) async {
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('notifications').update({'is_read': true}).eq('id', id));
    } catch (_) {}
    _reload();
  }

  IconData _icon(String k) => switch (k) {
        'notes' => Icons.description_outlined, 'video' => Icons.play_circle_outline, 'live' => Icons.videocam_outlined,
        'exam' => Icons.event_note_outlined, 'result' => Icons.fact_check_outlined, 'fee' => Icons.account_balance_wallet_outlined,
        'announcement' => Icons.campaign_outlined, _ => Icons.notifications_none };

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Notifications'), actions: [TextButton(onPressed: _markAll, child: const Text('Mark all read'))]),
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _f,
            builder: (c, snap) {
              if (snap.connectionState != ConnectionState.done) return const LoadingView();
              if (snap.hasError) return ErrorView(snap.error!, _reload);
              final l = snap.data!;
              if (l.isEmpty) return const EmptyView(Icons.notifications_none, 'No notifications yet.');
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16), itemCount: l.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (c, i) {
                    final n = l[i];
                    final unread = n['is_read'] != true;
                    return Card(child: ListTile(
                      leading: Icon(_icon(n['kind'] as String), color: unread ? AppColors.brass : AppColors.muted),
                      title: Text(n['title'] as String, style: TextStyle(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                      subtitle: Text('${n['body']}\n${DateFormat('d MMM, h:mm a').format(DateTime.parse(n['created_at'] as String).toLocal())}'),
                      isThreeLine: true,
                      onTap: unread ? () => _markOne(n['id'] as String) : null,
                    ));
                  },
                ),
              );
            },
          ),
        ),
      );
}

/// Bell button with an unread dot, for any role's header row.
class BellButton extends StatefulWidget {
  const BellButton({super.key});
  @override
  State<BellButton> createState() => _BellButtonState();
}

class _BellButtonState extends State<BellButton> {
  int _unread = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _count());
  }

  Future<void> _count() async {
    final s = context.read<SessionController>();
    try {
      final r = await s.run(() async => await s.db.from('notifications').select('id').eq('is_read', false).limit(50));
      if (mounted) setState(() => _unread = (r as List).length);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Notifications',
        icon: Badge(isLabelVisible: _unread > 0, label: Text(_unread > 9 ? '9+' : '$_unread'), child: const Icon(Icons.notifications_none)),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())).then((_) => _count()),
      );
}
