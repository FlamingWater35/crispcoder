import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/transcode_preset.dart';
import '../../data/services/permission_service.dart';
import '../../providers/app_settings_provider.dart';

/// App settings: encoder preference, permissions, battery exemption, about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final encoderPref = ref.watch(appSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // --- Encoding Section ---
          _SectionHeader(title: 'Encoding', icon: Icons.memory_outlined),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Encoder Preference',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hardware encoding is faster but may have codec '
                    'compatibility issues. Software is slower but more reliable.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Segmented selector for encoder preference
                  SegmentedButton<EncoderPreference>(
                    segments: const [
                      ButtonSegment(
                        value: EncoderPreference.auto,
                        label: Text('Auto'),
                        icon: Icon(Icons.auto_mode, size: 18),
                      ),
                      ButtonSegment(
                        value: EncoderPreference.hardware,
                        label: Text('Hardware'),
                        icon: Icon(Icons.memory, size: 18),
                      ),
                      ButtonSegment(
                        value: EncoderPreference.software,
                        label: Text('Software'),
                        icon: Icon(Icons.developer_board, size: 18),
                      ),
                    ],
                    selected: {encoderPref},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setEncoderPreference(selection.first);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Permissions Section ---
          _SectionHeader(title: 'Permissions', icon: Icons.lock_outline),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notification permission'),
                  subtitle: const Text(
                    'Required for encode progress in background',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  onTap: () async {
                    try {
                      await ref
                          .read(permissionServiceProvider)
                          .requireNotifications();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Notifications granted'),
                          ),
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.battery_full_outlined),
                  title: const Text('Disable battery optimizations'),
                  subtitle: const Text('Recommended for long encodes'),
                  trailing: const Icon(Icons.chevron_right),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                  ),
                  onTap: () => ref
                      .read(permissionServiceProvider)
                      .requireBatteryExemption(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- About Section ---
          _SectionHeader(title: 'About', icon: Icons.info_outline),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('CrispCoder'),
              subtitle: const Text(
                'Handbrake-equivalent transcoder • FFmpeg powered',
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small section header label with icon for visual grouping in settings.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
