import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase/supabase.dart' show FileOptions;
import '../../models.dart';
import '../../services/api.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

const _maxBytes = 50 * 1024 * 1024;

/// Notes / Videos / Live classes for one class (and optionally one subject).
/// Teachers (with [assignment]) can add, edit and delete; students only read.
class ContentView extends StatelessWidget {
  final String classId;
  final String? subjectId;
  final Assignment? assignment; // non-null => teacher mode
  final int initialTab;
  const ContentView({super.key, required this.classId, this.subjectId, this.assignment, this.initialTab = 0});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3, initialIndex: initialTab,
        child: Column(children: [
          const TabBar(
            indicatorColor: AppColors.brass, labelColor: AppColors.brass, unselectedLabelColor: AppColors.muted,
            tabs: [Tab(text: 'Notes'), Tab(text: 'Videos'), Tab(text: 'Live classes')]),
          Expanded(child: TabBarView(children: [
            _NotesTab(classId: classId, subjectId: subjectId, a: assignment),
            _VideosTab(classId: classId, subjectId: subjectId, a: assignment),
            _LiveTab(classId: classId, subjectId: subjectId, a: assignment),
          ])),
        ]),
      );
}

/// Teacher page: one subject + class.
class TeacherContentScreen extends StatelessWidget {
  final Assignment assignment;
  final int initialTab;
  const TeacherContentScreen({super.key, required this.assignment, this.initialTab = 0});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('${assignment.subjectName} - ${assignment.cls.label}')),
        body: SafeArea(child: ContentView(classId: assignment.cls.id, subjectId: assignment.subjectId, assignment: assignment, initialTab: initialTab)),
      );
}

/// Student page: all subjects, or one subject.
class StudentContentScreen extends StatefulWidget {
  final String title;
  final String? subjectId;
  final int initialTab;
  const StudentContentScreen({super.key, required this.title, this.subjectId, this.initialTab = 0});
  @override
  State<StudentContentScreen> createState() => _StudentContentScreenState();
}

class _StudentContentScreenState extends State<StudentContentScreen> {
  late Future<String> _f = myClassId(context.read<SessionController>());
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: SafeArea(child: FutureBuilder<String>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError || snap.data == null) return ErrorView(snap.error ?? 'Class not found.', () => setState(() => _f = myClassId(context.read<SessionController>())));
            return ContentView(classId: snap.data!, subjectId: widget.subjectId, initialTab: widget.initialTab);
          },
        )),
      );
}

// ---------------------------------------------------------------- shared bits
Future<bool> _confirm(BuildContext c, String title, String body) async =>
    (await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(100, 44)), onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
      ]),
    )) == true;

Future<({String path, String name, String ext})?> _pickFile(BuildContext c, List<String> exts) async {
  final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: exts, withData: false);
  if (r == null || r.files.isEmpty || r.files.single.path == null) return null;
  final f = r.files.single;
  if (f.size > _maxBytes) {
    if (c.mounted) toast(c, 'That file is larger than 50 MB.', error: true);
    return null;
  }
  return (path: f.path!, name: f.name, ext: (f.extension ?? '').toLowerCase());
}

Future<String> _upload(SessionController s, String classId, String subjectId, String path, String ext) async {
  final ct = contentTypes[ext];
  if (ct == null) throw ApiException('This file type is not allowed.');
  final dest = '$classId/$subjectId/${randomId(16)}.$ext';
  final bytes = await File(path).readAsBytes();
  await s.run(() => s.db.storage.from('materials').uploadBinary(dest, bytes, fileOptions: FileOptions(contentType: ct)));
  return dest;
}

Future<void> _removeFile(SessionController s, String? path) async {
  if (path == null) return;
  try { await s.db.storage.from('materials').remove([path]); } catch (_) {}
}

Widget _addButton(VoidCallback onTap, String label) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: FilledButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: Text(label)));

// ---------------------------------------------------------------------- NOTES
class _NotesTab extends StatefulWidget {
  final String classId;
  final String? subjectId;
  final Assignment? a;
  const _NotesTab({required this.classId, this.subjectId, this.a});
  @override
  State<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends State<_NotesTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final base = s.db.from('notes').select('*, subjects(name)').eq('class_id', widget.classId);
      final q = widget.subjectId == null ? base : base.eq('subject_id', widget.subjectId!);
      return asList(await q.order('created_at', ascending: false));
    });
  }

  void _reload() => setState(() => _f = _load());

  IconData _icon(String k) => switch (k) { 'pdf' => Icons.picture_as_pdf_outlined, 'image' => Icons.image_outlined, 'text' => Icons.notes, _ => Icons.insert_drive_file_outlined };

  Future<void> _open(Map<String, dynamic> n) async {
    final s = context.read<SessionController>();
    if (n['kind'] == 'text') {
      showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: AppColors.surface,
        builder: (c) => SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(n['title'] as String, style: display(22)),
          Text('${n['chapter']}', style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          SelectableText((n['body'] ?? '') as String, style: const TextStyle(fontSize: 16, height: 1.45)),
        ])))),
      );
    } else if (n['file_path'] != null) {
      await openStored(context, s, n['file_path'] as String);
    }
  }

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final a = widget.a!;
    final s = context.read<SessionController>();
    final chapter = TextEditingController(text: existing?['chapter'] as String? ?? 'General');
    final title = TextEditingController(text: existing?['title'] as String? ?? '');
    final body = TextEditingController(text: existing?['body'] as String? ?? '');
    String kind = existing?['kind'] as String? ?? 'text';
    ({String path, String name, String ext})? file;
    bool busy = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: Text(existing == null ? 'Add notes' : 'Edit notes'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: chapter, maxLength: 60, decoration: const InputDecoration(labelText: 'Chapter')),
          TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Title')),
          if (existing == null) ...[
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: kind, decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'text', child: Text('Text note')), DropdownMenuItem(value: 'pdf', child: Text('PDF')),
                DropdownMenuItem(value: 'image', child: Text('Image')), DropdownMenuItem(value: 'document', child: Text('Document (Word, PowerPoint, Excel)'))],
              onChanged: (v) => set(() { kind = v!; file = null; }),
            ),
          ],
          const SizedBox(height: 10),
          if (kind == 'text') TextField(controller: body, minLines: 5, maxLines: 10, maxLength: 20000, decoration: const InputDecoration(labelText: 'Note text')),
          if (kind != 'text' && existing == null) OutlinedButton.icon(
            icon: const Icon(Icons.attach_file),
            label: Text(file?.name ?? 'Choose file (max 50 MB)'),
            onPressed: () async {
              final exts = kind == 'pdf' ? ['pdf'] : kind == 'image' ? ['jpg', 'jpeg', 'png', 'webp'] : ['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt'];
              final f = await _pickFile(c, exts);
              if (f != null) set(() => file = f);
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: busy ? null : () async {
              if (title.text.trim().isEmpty) { toast(c, 'Enter a title.', error: true); return; }
              if (kind == 'text' && body.text.trim().isEmpty) { toast(c, 'Write the note text.', error: true); return; }
              if (kind != 'text' && existing == null && file == null) { toast(c, 'Choose a file.', error: true); return; }
              set(() => busy = true);
              try {
                if (existing != null) {
                  await s.run(() async => await s.db.from('notes').update({
                        'chapter': chapter.text.trim().isEmpty ? 'General' : chapter.text.trim(), 'title': title.text.trim(),
                        if (kind == 'text') 'body': body.text.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', existing['id']));
                } else {
                  String? path;
                  if (kind != 'text') path = await _upload(s, a.cls.id, a.subjectId, file!.path, file!.ext);
                  try {
                    await s.run(() async => await s.db.from('notes').insert({
                          'subject_id': a.subjectId, 'class_id': a.cls.id, 'teacher_id': s.user!.id,
                          'chapter': chapter.text.trim().isEmpty ? 'General' : chapter.text.trim(), 'title': title.text.trim(),
                          'kind': kind, 'body': kind == 'text' ? body.text.trim() : null, 'file_path': path}));
                  } catch (e) { await _removeFile(s, path); rethrow; }
                }
                if (c.mounted) Navigator.pop(c);
                if (mounted) { toast(context, 'Saved'); _reload(); }
              } catch (e) {
                if (c.mounted) { toast(c, errText(e), error: true); set(() => busy = false); }
              }
            },
            child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      )),
    );
  }

  Future<void> _delete(Map<String, dynamic> n) async {
    if (!await _confirm(context, 'Delete these notes?', '"${n['title']}" will be removed for all students.')) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('notes').delete().eq('id', n['id']));
      await _removeFile(s, n['file_path'] as String?);
      if (mounted) toast(context, 'Deleted');
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (widget.a != null) _addButton(() => _edit(), 'Add notes'),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.description_outlined, 'No notes yet.');
            final byChapter = <String, List<Map<String, dynamic>>>{};
            for (final n in l) { byChapter.putIfAbsent(n['chapter'] as String, () => []).add(n); }
            return RefreshIndicator(onRefresh: () async => _reload(), child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final e in byChapter.entries) ...[
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(e.key, style: display(17, c: AppColors.brass))),
                for (final n in e.value) Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
                  leading: Icon(_icon(n['kind'] as String), color: AppColors.brass),
                  title: Text(n['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([if (widget.subjectId == null) (n['subjects'] as Map)['name'], DateFormat('d MMM yyyy').format(DateTime.parse(n['created_at'] as String).toLocal())].join('  -  ')),
                  trailing: widget.a == null ? null : PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? _edit(existing: n) : _delete(n),
                    itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'del', child: Text('Delete'))]),
                  onTap: () => _open(n),
                ))),
              ],
            ]));
          },
        )),
      ]);
}

// --------------------------------------------------------------------- VIDEOS
class _VideosTab extends StatefulWidget {
  final String classId;
  final String? subjectId;
  final Assignment? a;
  const _VideosTab({required this.classId, this.subjectId, this.a});
  @override
  State<_VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<_VideosTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final base = s.db.from('videos').select('*, subjects(name)').eq('class_id', widget.classId);
      final q = widget.subjectId == null ? base : base.eq('subject_id', widget.subjectId!);
      return asList(await q.order('created_at', ascending: false));
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _edit({Map<String, dynamic>? existing}) async {
    final a = widget.a!;
    final s = context.read<SessionController>();
    final chapter = TextEditingController(text: existing?['chapter'] as String? ?? 'General');
    final title = TextEditingController(text: existing?['title'] as String? ?? '');
    final url = TextEditingController(text: existing?['url'] as String? ?? '');
    bool useFile = false, busy = false;
    ({String path, String name, String ext})? file;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: Text(existing == null ? 'Add video' : 'Edit video'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: chapter, maxLength: 60, decoration: const InputDecoration(labelText: 'Chapter')),
          TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Title')),
          if (existing == null) SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Link')), ButtonSegment(value: true, label: Text('Upload'))],
            selected: {useFile}, onSelectionChanged: (v) => set(() => useFile = v.first)),
          const SizedBox(height: 10),
          if (!useFile || existing != null) TextField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Video link (https://...)')),
          if (useFile && existing == null) OutlinedButton.icon(
            icon: const Icon(Icons.video_file_outlined), label: Text(file?.name ?? 'Choose video (mp4/webm/mov, max 50 MB)'),
            onPressed: () async { final f = await _pickFile(c, ['mp4', 'webm', 'mov']); if (f != null) set(() => file = f); }),
        ])),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: busy ? null : () async {
              if (title.text.trim().isEmpty) { toast(c, 'Enter a title.', error: true); return; }
              final link = url.text.trim();
              final needLink = !useFile || existing != null;
              if (needLink && !(link.startsWith('https://') || link.startsWith('http://'))) { toast(c, 'Enter a valid link starting with https://', error: true); return; }
              if (!needLink && file == null) { toast(c, 'Choose a video file.', error: true); return; }
              set(() => busy = true);
              try {
                final ch = chapter.text.trim().isEmpty ? 'General' : chapter.text.trim();
                if (existing != null) {
                  await s.run(() async => await s.db.from('videos').update({'chapter': ch, 'title': title.text.trim(), 'url': link}).eq('id', existing['id']));
                } else {
                  String? path;
                  if (useFile) path = await _upload(s, a.cls.id, a.subjectId, file!.path, file!.ext);
                  try {
                    await s.run(() async => await s.db.from('videos').insert({
                          'subject_id': a.subjectId, 'class_id': a.cls.id, 'teacher_id': s.user!.id, 'chapter': ch,
                          'title': title.text.trim(), 'url': useFile ? null : link, 'file_path': path}));
                  } catch (e) { await _removeFile(s, path); rethrow; }
                }
                if (c.mounted) Navigator.pop(c);
                if (mounted) { toast(context, 'Saved'); _reload(); }
              } catch (e) {
                if (c.mounted) { toast(c, errText(e), error: true); set(() => busy = false); }
              }
            },
            child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      )),
    );
  }

  Future<void> _delete(Map<String, dynamic> v) async {
    if (!await _confirm(context, 'Delete this video?', '"${v['title']}" will be removed for all students.')) return;
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('videos').delete().eq('id', v['id']));
      await _removeFile(s, v['file_path'] as String?);
      if (mounted) toast(context, 'Deleted');
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (widget.a != null) _addButton(() => _edit(), 'Add video'),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.play_circle_outline, 'No videos yet.');
            final byChapter = <String, List<Map<String, dynamic>>>{};
            for (final v in l) { byChapter.putIfAbsent(v['chapter'] as String, () => []).add(v); }
            return RefreshIndicator(onRefresh: () async => _reload(), child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final e in byChapter.entries) ...[
                Padding(padding: const EdgeInsets.only(top: 8, bottom: 6), child: Text(e.key, style: display(17, c: AppColors.brass))),
                for (final v in e.value) Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
                  leading: const Icon(Icons.play_circle_outline, color: AppColors.brass),
                  title: Text(v['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([if (widget.subjectId == null) (v['subjects'] as Map)['name'], DateFormat('d MMM yyyy').format(DateTime.parse(v['created_at'] as String).toLocal())].join('  -  ')),
                  trailing: widget.a == null ? null : PopupMenuButton<String>(
                    onSelected: (x) => x == 'edit' ? _edit(existing: v) : _delete(v),
                    itemBuilder: (_) => [if (v['url'] != null) const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'del', child: Text('Delete'))]),
                  onTap: () {
                    final s = context.read<SessionController>();
                    if (v['url'] != null) { openUrl(context, v['url'] as String); } else if (v['file_path'] != null) { openStored(context, s, v['file_path'] as String); }
                  },
                ))),
              ],
            ]));
          },
        )),
      ]);
}

// ---------------------------------------------------------------- LIVE CLASSES
class _LiveTab extends StatefulWidget {
  final String classId;
  final String? subjectId;
  final Assignment? a;
  const _LiveTab({required this.classId, this.subjectId, this.a});
  @override
  State<_LiveTab> createState() => _LiveTabState();
}

class _LiveTabState extends State<_LiveTab> {
  late Future<List<Map<String, dynamic>>> _f = _load();

  Future<List<Map<String, dynamic>>> _load() {
    final s = context.read<SessionController>();
    return s.run(() async {
      final base = s.db.from('live_classes').select('*, subjects(name)').eq('class_id', widget.classId);
      final q = widget.subjectId == null ? base : base.eq('subject_id', widget.subjectId!);
      final all = asList(await q.order('scheduled_at', ascending: false).limit(60));
      // Students see what is live or upcoming; teachers also see ended sessions.
      return widget.a == null ? all.where((x) => x['status'] != 'ended').toList().reversed.toList() : all;
    });
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _schedule() async {
    final a = widget.a!;
    final s = context.read<SessionController>();
    final title = TextEditingController();
    final link = TextEditingController();
    DateTime when = DateTime.now().add(const Duration(hours: 1));
    bool own = false, busy = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(builder: (c, set) => AlertDialog(
        title: const Text('Schedule a live class'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 100, decoration: const InputDecoration(labelText: 'Title (e.g. Chapter 3 doubts)')),
          OutlinedButton.icon(
            icon: const Icon(Icons.event), label: Text(DateFormat('d MMM yyyy, h:mm a').format(when)),
            onPressed: () async {
              final d = await showDatePicker(context: c, initialDate: when, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
              if (d == null || !c.mounted) return;
              final t = await showTimePicker(context: c, initialTime: TimeOfDay.fromDateTime(when));
              if (t == null) return;
              set(() => when = DateTime(d.year, d.month, d.day, t.hour, t.minute));
            },
          ),
          const SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Jitsi room')), ButtonSegment(value: true, label: Text('My own link'))],
            selected: {own}, onSelectionChanged: (v) => set(() => own = v.first)),
          const SizedBox(height: 8),
          if (own) TextField(controller: link, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Meet / Zoom / Teams link (https://...)'))
          else const Text('A private Jitsi Meet room is created for this class (video, microphone, screen sharing). The public Jitsi server may ask the teacher to sign in once to start the meeting.', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ])),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: busy ? null : () async {
              if (title.text.trim().isEmpty) { toast(c, 'Enter a title.', error: true); return; }
              final url = own ? link.text.trim() : 'https://meet.jit.si/SmartSchool-${randomId(14)}';
              if (!url.startsWith('https://')) { toast(c, 'The link must start with https://', error: true); return; }
              set(() => busy = true);
              try {
                await s.run(() async => await s.db.from('live_classes').insert({
                      'subject_id': a.subjectId, 'class_id': a.cls.id, 'teacher_id': s.user!.id, 'title': title.text.trim(),
                      'scheduled_at': when.toUtc().toIso8601String(), 'join_url': url}));
                if (c.mounted) Navigator.pop(c);
                if (mounted) { toast(context, 'Live class scheduled - students were notified'); _reload(); }
              } catch (e) {
                if (c.mounted) { toast(c, errText(e), error: true); set(() => busy = false); }
              }
            },
            child: busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Schedule'),
          ),
        ],
      )),
    );
  }

  Future<void> _setStatus(Map<String, dynamic> l, String status, {bool open = false}) async {
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.from('live_classes').update({'status': status}).eq('id', l['id']));
      if (open && mounted) await openUrl(context, l['join_url'] as String);
    } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    if (!await _confirm(context, 'Delete this live class?', '"${l['title']}" will be removed.')) return;
    final s = context.read<SessionController>();
    try { await s.run(() async => await s.db.from('live_classes').delete().eq('id', l['id'])); } catch (e) { if (mounted) toast(context, errText(e), error: true); }
    _reload();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        if (widget.a != null) _addButton(_schedule, 'Schedule live class'),
        Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (c, snap) {
            if (snap.connectionState != ConnectionState.done) return const LoadingView();
            if (snap.hasError) return ErrorView(snap.error!, _reload);
            final l = snap.data!;
            if (l.isEmpty) return const EmptyView(Icons.videocam_outlined, 'No live classes scheduled.');
            return RefreshIndicator(onRefresh: () async => _reload(), child: ListView(padding: const EdgeInsets.all(16), children: [
              for (final x in l) Builder(builder: (_) {
                final status = x['status'] as String;
                final at = DateTime.parse(x['scheduled_at'] as String).toLocal();
                final isLive = status == 'live';
                final teacher = widget.a != null;
                return Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(x['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: (isLive ? AppColors.coral : status == 'ended' ? AppColors.muted : AppColors.brass).withOpacity(.18), borderRadius: BorderRadius.circular(8)),
                      child: Text(isLive ? 'LIVE NOW' : status == 'ended' ? 'Ended' : 'Scheduled', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isLive ? AppColors.coral : status == 'ended' ? AppColors.muted : AppColors.brass)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('${(x['subjects'] as Map)['name']}  -  ${DateFormat('EEE d MMM, h:mm a').format(at)}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  if (teacher) Wrap(spacing: 8, runSpacing: 4, children: [
                    if (status == 'scheduled') FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 42)), onPressed: () => _setStatus(x, 'live', open: true), child: const Text('Start class')),
                    if (isLive) FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 42)), onPressed: () => openUrl(context, x['join_url'] as String), child: const Text('Open room')),
                    if (isLive) OutlinedButton(onPressed: () => _setStatus(x, 'ended'), child: const Text('End class')),
                    OutlinedButton(onPressed: () => Clipboard.setData(ClipboardData(text: x['join_url'] as String)).then((_) { if (mounted) toast(context, 'Class link copied'); }), child: const Text('Copy link')),
                    TextButton(onPressed: () => _delete(x), child: const Text('Delete', style: TextStyle(color: AppColors.coral))),
                  ])
                  else if (isLive) FilledButton(onPressed: () => openUrl(context, x['join_url'] as String), child: const Text('Join now'))
                  else const Text('Waiting for the teacher to start. Pull down to refresh.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ]))));
              }),
            ]));
          },
        )),
      ]);
}
