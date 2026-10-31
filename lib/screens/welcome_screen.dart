import 'package:flutter/material.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  static const _roles = [
    ('student', 'Student', 'Notes, attendance, results, fees', Icons.school_outlined),
    ('teacher', 'Teacher', 'Attendance, marks, materials', Icons.menu_book_outlined),
    ('office', 'Office', 'Fees and receipts', Icons.receipt_long_outlined),
    ('admin', 'Administrator', 'Approvals and school settings', Icons.admin_panel_settings_outlined),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Animation<double> _step(int i) =>
      CurvedAnimation(parent: _c, curve: Interval(0.15 + i * 0.15, 0.55 + i * 0.15, curve: Curves.easeOutCubic));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 44),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FadeTransition(
                  opacity: _c,
                  child: Image.asset('assets/logo.png', width: 64, height: 64), // logo: upper-left
                ),
                const SizedBox(height: 36),
                FadeTransition(
                  opacity: _step(0),
                  child: Text(AppConfig.schoolName, style: display(36)),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: _step(1),
                  child: const Text('Choose how you are signing in.', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                ),
                const SizedBox(height: 28),
                for (var i = 0; i < _roles.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FadeTransition(
                      opacity: _step(i + 1),
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(_step(i + 1)),
                        child: _RoleTile(role: _roles[i].$1, title: _roles[i].$2, sub: _roles[i].$3, icon: _roles[i].$4),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String role, title, sub;
  final IconData icon;
  const _RoleTile({required this.role, required this.title, required this.sub, required this.icon});
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LoginScreen(role: role))),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: AppColors.surfaceHi, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.brass),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ])),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ]),
          ),
        ),
      );
}
