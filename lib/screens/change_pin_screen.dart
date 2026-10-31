import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ChangePinScreen extends StatefulWidget {
  final bool forced;
  const ChangePinScreen({super.key, this.forced = false});
  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _cur = TextEditingController(), _new = TextEditingController(), _new2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_cur.text.length != 6 || _new.text.length != 6) return setState(() => _error = 'PINs must be 6 digits.');
    if (_new.text != _new2.text) return setState(() => _error = 'The new PINs do not match.');
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<SessionController>().changePin(_cur.text, _new.text);
      if (!mounted) return;
      toast(context, 'PIN changed');
      if (!widget.forced) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() { _busy = false; _error = friendly(e); });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !widget.forced,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Change PIN'),
            automaticallyImplyLeading: !widget.forced,
            actions: [if (widget.forced) TextButton(onPressed: () => context.read<SessionController>().logout(), child: const Text('Sign out'))],
          ),
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
              if (widget.forced) const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text('The administrator reset your PIN. Choose a new private PIN to continue.', style: TextStyle(color: AppColors.muted)),
              ),
              PinField(_cur, label: 'Current PIN'),
              const SizedBox(height: 14),
              PinField(_new, label: 'New PIN'),
              const SizedBox(height: 14),
              PinField(_new2, label: 'Repeat new PIN'),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: AppColors.coral))),
              const SizedBox(height: 22),
              FilledButton(onPressed: _busy ? null : _save, child: const Text('Save PIN')),
            ]),
          ),
        ),
      );
}
