import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config.dart';
import 'screens/admin/admin_home.dart';
import 'screens/change_pin_screen.dart';
import 'screens/office/office_home.dart';
import 'screens/student/student_home.dart';
import 'screens/teacher/teacher_home.dart';
import 'screens/welcome_screen.dart';
import 'services/session.dart';
import 'theme.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartSchoolApp());
}

class SmartSchoolApp extends StatelessWidget {
  const SmartSchoolApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: AppConfig.schoolName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: AppConfig.isConfigured
            ? ChangeNotifierProvider(create: (_) => SessionController()..restore(), child: const _Root())
            : const _SetupMissing(),
      );
}

class _Root extends StatelessWidget {
  const _Root();
  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionController>();
    if (!s.ready) return const Scaffold(body: LoadingView());
    final u = s.user;
    if (u == null) return const WelcomeScreen();
    if (u.mustChangePin) return const ChangePinScreen(forced: true);
    switch (u.role) {
      case 'admin': return const AdminHome();
      case 'teacher': return const TeacherHome();
      case 'student': return const StudentHome();
      default: return const OfficeHome();
    }
  }
}

class _SetupMissing extends StatelessWidget {
  const _SetupMissing();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(28),
          child: Center(
            child: Text(
              'This build has no server settings.\n\nRebuild with --dart-define=SUPABASE_URL=... and --dart-define=SUPABASE_ANON_KEY=... (see README).',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 16)),
          ),
        ),
      );
}
