import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppDestination {
  const AppDestination(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const appDestinations = [
  AppDestination('/', 'Dashboard', Icons.dashboard_outlined, Icons.dashboard),
  AppDestination(
    '/depenses',
    'Dépenses',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
  ),
  AppDestination(
    '/budgets',
    'Budgets',
    Icons.pie_chart_outline,
    Icons.pie_chart,
  ),
  AppDestination('/epargne', 'Épargne', Icons.savings_outlined, Icons.savings),
  AppDestination(
    '/distribution',
    'Distribution',
    Icons.account_tree_outlined,
    Icons.account_tree,
  ),
];

/// Barre de navigation en bas sur téléphone, rail latéral sur grand écran.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _railBreakpoint = 800.0;

  void _goTo(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _goTo,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in appDestinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _goTo,
        destinations: [
          for (final d in appDestinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
