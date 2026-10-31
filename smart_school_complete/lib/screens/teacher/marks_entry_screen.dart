import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models.dart';
import '../../services/helpers.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Fast marks entry: one student at a time, in roll-number order.
/// Type marks -> Save -> Next (Next also saves). Nothing is visible to students until the teacher publishes.
class MarksEntryScreen extends StatefulWidget {
  final Assignment assignment;
  const MarksEntryScreen({super.key, required this.assignment});
  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  late Future<List<Map<String, dynamic>>> _exams = _loadExams();
  Map<String, dynamic>? _exam;
  List<Map<String, dynamic>> _roster = [];
  int _i = 0;
  bool _loading = false, _busy = false;
  final _marks = TextEditingController();
  final _max = TextEditingController(text: '100');
  final _focus = FocusNode();

  Assignment get _a => widget.assignment;

  Future<List<Map<String, dynamic>>> _loadExams() {
    final s = context.read<SessionController>();
    return s.run(() async => asList(await s.db.from('examinations').select().eq('class_id', _a.cls.id).order('created_at', ascending: false)));
  }

  Future<void> _open(Map<String, dynamic> exam) async {
    setState(() { _exam = exam; _loading = true; });
    await _loadRoster(firstOpen: true);
  }

  Future<void> _loadRoster({bool firstOpen = false}) async {
    final s = context.read<SessionController>();
    try {
      final r = await s.run(() async => asList(await s.db.rpc('marks_roster', params: {'p_exam': _exam!['id'], 'p_subject': _a.subjectId})));
      _roster = r;
      if (firstOpen) {
        final withMax = r.firstWhere((x) => x['max_marks'] != null, orElse: () => {});
        _max.text = _fmt(withMax['max_marks'] ?? _exam!['default_max_marks']);
        final firstEmpty = r.indexWhere((x) => x['marks_obtained'] == null);
        _i = firstEmpty < 0 ? 0 : firstEmpty;
      }
      _showCurrent();
    } catch (e) {
      if (mounted) { toast(context, errText(e), error: true); setState(() => _exam = null); }
    }
    if (mounted) setState(() => _loading = false);
  }

  String _fmt(dynamic v) {
    final d = n(v).toDouble();
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }

  void _showCurrent() {
    if (_roster.isEmpty) return;
    final v = _roster[_i]['marks_obtained'];
    _marks.text = v == null ? '' : _fmt(v);
    _marks.selection = TextSelection.collapsed(offset: _marks.text.length);
  }

  bool get _locked => _roster.isNotEmpty && _roster[_i]['status'] == 'published';
  int get _entered => _roster.where((r) => r['marks_obtained'] != null).length;

  /// Validates and saves the current student's marks. Returns false if nothing was saved because of an error.
  Future<bool> _save({bool quiet = false}) async {
    if (_busy || _locked) return true;
    final max = num.tryParse(_max.text.trim().replaceAll(',', '.'));
    final got = num.tryParse(_marks.text.trim().replaceAll(',', '.'));
    if (max == null || max <= 0) { toast(context, 'Enter the maximum marks first.', error: true); return false; }
    if (got == null) { toast(context, 'Enter the marks obtained.', error: true); return false; }
    if (got < 0) { toast(context, 'Marks cannot be negative.', error: true); return false; }
    if (got > max) { toast(context, 'Marks cannot be more than the maximum ($max).', error: true); return false; }
    final row = _roster[_i];
    if (row['marks_obtained'] != null && n(row['marks_obtained']) == got && n(row['max_marks']) == max) return true; // nothing changed
    setState(() => _busy = true);
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('save_mark', params: {
            'p_exam': _exam!['id'], 'p_subject': _a.subjectId, 'p_student': row['student_id'], 'p_obtained': got, 'p_max': max}));
      row['marks_obtained'] = got;
      row['max_marks'] = max;
      row['status'] = 'draft';
      if (mounted && !quiet) toast(context, 'Saved');
      return true;
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    if (_marks.text.trim().isNotEmpty && !_locked) {
      if (!await _save(quiet: true)) return;
    }
    if (!mounted) return;
    if (_i < _roster.length - 1) {
      setState(() { _i++; _showCurrent(); });
      _focus.requestFocus();
    } else {
      toast(context, 'That was the last student. Review and publish when ready.');
    }
  }

  void _prev() {
    if (_i > 0) setState(() { _i--; _showCurrent(); });
  }

  Future<void> _publish() async {
    if (_marks.text.trim().isNotEmpty && !_locked && !await _save(quiet: true)) return;
    final missing = _roster.where((r) => r['marks_obtained'] == null).length;
    if (missing > 0) { toast(context, '$missing student(s) still have no marks.', error: true); return; }
    final draft = _roster.where((r) => r['status'] != 'published').length;
    if (draft == 0) { toast(context, 'Everything is already published.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Publish final marks?'),
        content: Text('${_a.subjectName}, ${_a.cls.label}\n${_exam!['name']}\n\n$draft student(s) will see these marks immediately and class ranks will be recalculated.\n\nPublished marks are locked. Only the administrator can correct them (with a logged reason).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), onPressed: () => Navigator.pop(c, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    final s = context.read<SessionController>();
    try {
      await s.run(() async => await s.db.rpc('publish_marks', params: {'p_exam': _exam!['id'], 'p_subject': _a.subjectId}));
      if (mounted) toast(context, 'Marks published');
      await _loadRoster();
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _jump() => showModalBottomSheet(
        context: context, backgroundColor: AppColors.surface, isScrollControlled: true,
        builder: (c) => SafeArea(child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: ListView.builder(
            padding: const EdgeInsets.all(12), itemCount: _roster.length,
            itemBuilder: (c, i) {
              final r = _roster[i];
              final has = r['marks_obtained'] != null;
              return ListTile(
                dense: true, selected: i == _i,
                leading: Text('${r['roll_no']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                title: Text(r['full_name'] as String),
                trailing: Text(has ? '${_fmt(r['marks_obtained'])}/${_fmt(r['max_marks'])}${r['status'] == 'published' ? '  \u{1F512}' : ''}' : 'not entered',
                    style: TextStyle(color: has ? AppColors.mint : AppColors.muted)),
                onTap: () { Navigator.pop(c); setState(() { _i = i; _showCurrent(); }); },
              );
            },
          ),
        )),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Marks - ${_a.subjectName}'), actions: [
          if (_exam != null) TextButton(onPressed: () => setState(() { _exam = null; _exams = _loadExams(); }), child: const Text('Change exam')),
        ]),
        body: SafeArea(child: _exam == null ? _examPicker() : (_loading ? const LoadingView() : _entry())),
      );

  Widget _examPicker() => FutureBuilder<List<Map<String, dynamic>>>(
        future: _exams,
        builder: (c, snap) {
          if (snap.connectionState != ConnectionState.done) return const LoadingView();
          if (snap.hasError) return ErrorView(snap.error!, () => setState(() => _exams = _loadExams()));
          final l = snap.data!;
          if (l.isEmpty) return const EmptyView(Icons.event_note_outlined, 'No examination has been created for this class yet.\nAsk the administrator to create one.');
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Choose the examination', style: display(20)),
            const SizedBox(height: 10),
            for (final e in l) Padding(padding: const EdgeInsets.only(bottom: 10), child: Card(child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              title: Text(e['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(e['starts_on'] == null ? 'Date not set' : DateFormat('d MMM yyyy').format(DateTime.parse(e['starts_on'] as String))),
              trailing: const Icon(Icons.chevron_right), onTap: () => _open(e),
            ))),
          ]);
        },
      );

  Widget _entry() {
    if (_roster.isEmpty) return const EmptyView(Icons.groups_outlined, 'This class has no approved students yet.');
    final r = _roster[_i];
    final published = _roster.where((x) => x['status'] == 'published').length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${_exam!['name']}  -  ${_a.cls.label}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 8),
      LinearProgressIndicator(value: _entered / _roster.length, color: AppColors.brass, backgroundColor: AppColors.surfaceHi, minHeight: 6),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$_entered of ${_roster.length} entered', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
        TextButton.icon(onPressed: _jump, icon: const Icon(Icons.list_alt, size: 18), label: const Text('All students')),
      ]),
      const SizedBox(height: 8),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        Text('Student ${_i + 1} of ${_roster.length}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text('Roll No. ${r['roll_no']}', style: display(34, c: AppColors.brass)),
        const SizedBox(height: 4),
        Text(r['full_name'] as String, textAlign: TextAlign.center, style: display(22)),
        const SizedBox(height: 20),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: TextField(
            controller: _marks, focusNode: _focus, enabled: !_locked, autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            textInputAction: TextInputAction.next, onSubmitted: (_) => _next(),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            decoration: InputDecoration(labelText: 'Marks obtained', suffixText: '/ ${_max.text}'),
          )),
          const SizedBox(width: 8),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(76, 56)), onPressed: (_busy || _locked) ? null : () => _save(), child: const Text('Save')),
          const SizedBox(width: 6),
          // Next sits immediately beside the entry controls, as requested.
          FilledButton.tonal(style: FilledButton.styleFrom(minimumSize: const Size(76, 56)), onPressed: _busy ? null : _next, child: const Text('Next')),
        ]),
        const SizedBox(height: 10),
        if (_locked) const Text('Published and locked', style: TextStyle(color: AppColors.amber, fontWeight: FontWeight.w600))
        else if (r['marks_obtained'] != null) const Text('Saved (draft)', style: TextStyle(color: AppColors.mint, fontWeight: FontWeight.w600)),
      ]))),
      const SizedBox(height: 10),
      Row(children: [
        TextButton.icon(onPressed: _i > 0 ? _prev : null, icon: const Icon(Icons.chevron_left), label: const Text('Previous')),
        const Spacer(),
        SizedBox(width: 130, child: TextField(
          controller: _max, enabled: published == 0, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Maximum marks', isDense: true))),
      ]),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _busy ? null : _publish, icon: const Icon(Icons.publish), label: const Text('Review & publish final marks')),
      const SizedBox(height: 6),
      const Text('Marks are saved to the server as you go, so closing the app loses nothing. Students see nothing until you publish.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }
}
