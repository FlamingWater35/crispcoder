import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/permission_service.dart';

/// App settings: permissions, battery exemption, about info.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notification permission'),
            subtitle: const Text('Required for encode progress in background'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              try {
                await ref
                    .read(permissionServiceProvider)
                    .requireNotifications();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notifications granted')),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Permission denied')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_full_outlined),
            title: const Text('Disable battery optimizations'),
            subtitle: const Text('Recommended for long encodes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () =>
                ref.read(permissionServiceProvider).requireBatteryExemption(),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About CrispCoder'),
            subtitle: const Text(
              'Handbrake-equivalent transcoder • FFmpeg powered',
            ),
          ),
        ],
      ),
    );
  }
}
