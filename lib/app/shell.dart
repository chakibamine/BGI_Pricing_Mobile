import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';

/// Status / navigation bar icons and colors matching the active theme.
SystemUiOverlayStyle systemUiFor(AppPalette p, {Color? navigationBar}) {
  final base = p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark;
  return base.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: navigationBar ?? p.surface,
    systemNavigationBarIconBrightness: p.isDark ? Brightness.light : Brightness.dark,
    systemNavigationBarDividerColor: Colors.transparent,
  );
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiFor(p),
      child: Scaffold(
        body: shell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: p.border, width: 0.8)),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) {
              HapticFeedback.selectionClick();
              shell.goBranch(i, initialLocation: i == shell.currentIndex);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Tableau',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month_rounded),
                label: 'Quinzaines',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Cotations',
              ),
              NavigationDestination(
                icon: Icon(Icons.currency_exchange_outlined),
                selectedIcon: Icon(Icons.currency_exchange_rounded),
                label: 'Taux',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'Plus',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
