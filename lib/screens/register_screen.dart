import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase/supabase.dart';
import '../config.dart';
import '../models.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dart:convert';

class RegisterScreen extends StatefulWidget {
  final String role;
  const RegisterScreen({super.key, required this.role});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController(), _id = TextEditingController(), _pin = TextEditingController(), _pin2 = TextEditingController();
  int _year = 1;
  String _section = '';
  final Set<String> _subjects = {};
  final Set<int> _years = {};
  XFile? _photo;
  bool _busy = false;
  String? _error;
  List<Subject> _allSubjects = [];
  List<SchoolClass> _classes = [];
  Object? _loadError;

  late final SupabaseClient _anon = SupabaseClient(AppConfig.supabaseUrl, AppConfig.anonKey);

  @override
  void initState() {
    super.initState();
    _loadRefs();
  }

  Future<void> _loadRefs() async {
    try {
      final s = await _anon.from('subjects').select('id,name').eq('is_active', true).order('name');
      final c = await _anon.from('classes').select('id,year_level,section,class_teacher_id');
      setState(() {
        _allSubjects = (s as List).map((e) => Subject(e['id'] as String, e['name'] as String)).toList();
        _classes = (c as List).map((e) => SchoolClass.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _loadError = null;
      });
    } catch (e) {
      setState(() => _loadError = e);
    }
  }

  Future<void> _capture() async {
    try {
      // Camera only: a live photo of the original card, requested when this button is tapped.
      final x = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600, imageQuality: 80, preferredCameraDevice: CameraDevice.rear);
      if (x != null) setState(() => _photo = x);
    } catch (_) {
      if (mounted) toast(context, 'Camera could not be opened. Allow camera access in Settings and try again.', error: true);
    }
  }

  String get _cardName => switch (widget.role) { 'student' => 'student ID card', 'teacher' => 'teacher ID card', _ => 'staff ID card' };

  Future<void> _submit() async {
    String? err;
    if (_name.text.trim().length < 2) {
      err = 'Enter your full name.';
    } else if (_id.text.trim().isEmpty) {
      err = widget.role == 'student' ? 'Enter your roll number.' : 'Enter your staff ID.';
    } else if (widget.role == 'teacher' && _subjects.isEmpty) {
      err = 'Choose the subject(s) you teach.';
    } else if (widget.role == 'teacher' && _years.isEmpty) {
      err = 'Choose the year(s) you teach.';
    } else if (_photo == null) {
      err = 'Take a photo of your $_cardName.';
    } else if (_pin.text.length != 6) {
      err = 'Choose a 6-digit PIN.';
    } else if (_pin.text != _pin2.text) {
      err = 'The two PINs do not match.';
    }
    if (err != null) return setState(() => _error = err);

    setState(() { _busy = true; _error = null; });
    try {
      await Api.register({
        'role': widget.role,
        'full_name': _name.text.trim(),
        'login_id': _id.text.trim(),
        'pin': _pin.text,
        if (widget.role == 'student') 'year_level': '$_year',
        if (widget.role == 'student') 'section': _section,
        if (widget.role == 'teacher') 'subject_ids': jsonEncode(_subjects.toList()),
        if (widget.role == 'teacher') 'year_levels': jsonEncode(_years.toList()),
      }, _photo!.path);
      try { await File(_photo!.path).delete(); } catch (_) {} // do not keep the ID photo on the phone
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('Registration sent'),
          content: const Text('The administrator will check your ID card. Sign in with your ID and PIN once you are approved.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendly(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = widget.role == 'student', isTeacher = widget.role == 'teacher';
    final sections = _classes.where((c) => c.yearLevel == _year && c.section.isNotEmpty).map((c) => c.section).toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('Register as ${roleTitles[widget.role]}')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 32), children: [
          if (isStudent) ...[
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 1, label: Text('First Year')), ButtonSegment(value: 2, label: Text('Second Year'))],
              selected: {_year},
              onSelectionChanged: (s) => setState(() { _year = s.first; _section = ''; }),
            ),
            const SizedBox(height: 14),
          ],
          TextField(controller: _name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name (as on your ID card)', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 14),
          TextField(
            controller: _id,
            keyboardType: isStudent ? TextInputType.number : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
            decoration: InputDecoration(labelText: isStudent ? 'Roll number' : 'Staff ID (printed on your card)', prefixIcon: const Icon(Icons.badge_outlined)),
          ),
          if (isStudent && sections.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _section.isEmpty ? null : _section,
              decoration: const InputDecoration(labelText: 'Section'),
              items: [for (final s in sections) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => _section = v ?? ''),
            ),
          ],
          if (isTeacher) ...[
            const SizedBox(height: 18),
            const Text('Subjects you teach', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_loadError != null) ErrorView(_loadError!, _loadRefs)
            else if (_allSubjects.isEmpty) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
            else Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in _allSubjects)
                FilterChip(
                  label: Text(s.name), selected: _subjects.contains(s.id),
                  onSelected: (v) => setState(() => v ? _subjects.add(s.id) : _subjects.remove(s.id)),
                ),
            ]),
            const SizedBox(height: 16),
            const Text('Class / year', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final y in [1, 2])
                FilterChip(label: Text(yearName(y)), selected: _years.contains(y),
                    onSelected: (v) => setState(() => v ? _years.add(y) : _years.remove(y))),
            ]),
          ],
          const SizedBox(height: 22),
          Text('Photo of your $_cardName', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            isStudent
                ? 'Photograph your original card. The red "Student ID Card" marking, your name and roll number must be readable.'
                : 'Photograph your original card. Your name and ID must be readable.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          if (_photo != null) ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photo!.path), height: 190, width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _busy ? null : _capture,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(_photo == null ? 'Open camera' : 'Retake photo'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 4),
          const Text('Only the administrator can see this photo. It is deleted once your registration is reviewed.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 22),
          PinField(_pin, label: 'Choose a 6-digit PIN'),
          const SizedBox(height: 14),
          PinField(_pin2, label: 'Repeat PIN'),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppColors.coral))),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Submit for approval'),
          ),
        ]),
      ),
    );
  }
}
