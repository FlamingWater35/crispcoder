import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/home/home_screen.dart';
import 'features/logs/logs_screen.dart';
import 'features/settings/settings_screen.dart';
import 'providers/app_settings_provider.dart';

/// Root widget: Material app with bottom-nav between Queue, Logs, Settings.
class CrispCoderApp extends ConsumerWidget {
  const CrispCoderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp(
      title: 'CrispCoder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2196F3),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF2196F3),
        brightness: Brightness.dark,
      ),
      themeMode: settings.themeMode,
      home: const _RootShell(),
    );
  }
}

/// Tabbed shell hosting the three primary destinations.
class _RootShell extends StatefulWidget {
  const _RootShell();

  @override
  State<_RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<_RootShell> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.queue, label: 'Queue', screen: HomeScreen()),
    (icon: Icons.receipt_long, label: 'Logs', screen: LogsScreen()),
    (icon: Icons.settings, label: 'Settings', screen: SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _destinations.map((d) => d.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}
