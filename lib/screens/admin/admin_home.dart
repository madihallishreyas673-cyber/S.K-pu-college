import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../change_pin_screen.dart';
import 'accounts_tab.dart';
import 'approvals_tab.dart';
import 'classes_tab.dart';
import 'school_tab.dart';

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _i = 0;
  @override
  Widget build(BuildContext context) {
    const titles = ['Approvals', 'Classes', 'Accounts', 'School'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_i]),
        actions: [
          IconButton(icon: const Icon(Icons.lock_reset), tooltip: 'Change PIN', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChangePinScreen()))),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Sign out', onPressed: () => context.read<SessionController>().logout()),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: _i, children: const [ApprovalsTab(), ClassesTab(), AccountsTab(), SchoolTab()])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i, onDestinationSelected: (v) => setState(() => _i = v),
        backgroundColor: AppColors.surface, indicatorColor: AppColors.surfaceHi,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Classes'),
          NavigationDestination(icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: 'Accounts'),
          NavigationDestination(icon: Icon(Icons.school_outlined), selectedIcon: Icon(Icons.school), label: 'School'),
        ],
      ),
    );
  }
}
