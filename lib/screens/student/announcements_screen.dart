import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// School announcements visible to the signed-in person (row-level security decides which ones).
class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});
  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('announcements').select().order('created_at', ascending: false).limit(50)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Announcements')),
        body: SafeArea(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, () => setState(() => _f = _load()));
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.campaign_outlined, 'No announcements yet.');
            return RefreshIndicator(
              onRefresh: () async => setState(() => _f = _load()),
              child: ListView(padding: const EdgeInsets.all(16), children: [
                for (final a in l) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a['title'] as String, style: display(18)),
                  Text(DateFormat('d MMM yyyy').format(DateTime.parse(a['created_at'] as String).toLocal()), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Text(a['body'] as String, style: const TextStyle(height: 1.4)),
                ])))),
              ]),
            );
          },
        )),
      );
}
