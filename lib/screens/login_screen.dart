import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'register_screen.dart';

const roleTitles = {'student': 'Student', 'teacher': 'Teacher', 'office': 'Office', 'admin': 'Administrator'};

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _id = TextEditingController(), _pin = TextEditingController();
  int _year = 1;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_id.text.trim().isEmpty) return setState(() => _error = 'Enter your ${_idLabel.toLowerCase()}.');
    if (_pin.text.length != 6) return setState(() => _error = 'Enter your 6-digit PIN.');
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<SessionController>().login(
          role: widget.role, loginId: _id.text, year: widget.role == 'student' ? _year : null, pin: _pin.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendly(e); });
    }
  }

  String get _idLabel => widget.role == 'student' ? 'Roll number' : widget.role == 'admin' ? 'Admin ID' : 'Staff ID';

  @override
  Widget build(BuildContext context) {
    final isStudent = widget.role == 'student';
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), children: [
          const BrandBar(),
          const SizedBox(height: 28),
          Text('${roleTitles[widget.role]} sign in', style: display(30)),
          const SizedBox(height: 20),
          if (isStudent) ...[
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 1, label: Text('First Year')), ButtonSegment(value: 2, label: Text('Second Year'))],
              selected: {_year},
              onSelectionChanged: (s) => setState(() => _year = s.first),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _id,
            keyboardType: isStudent ? TextInputType.number : TextInputType.text,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))],
            decoration: InputDecoration(labelText: _idLabel, prefixIcon: const Icon(Icons.badge_outlined)),
          ),
          const SizedBox(height: 14),
          PinField(_pin),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_error!, style: const TextStyle(color: AppColors.coral, fontSize: 14)),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Sign in'),
          ),
          if (widget.role != 'admin') ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegisterScreen(role: widget.role))),
              child: const Text('New here? Register with your ID card'),
            ),
          ],
        ]),
      ),
    );
  }
}
