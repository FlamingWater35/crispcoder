import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/utils/snackbar_helper.dart';
import '../../data/models/transcode_preset.dart';
import '../../data/services/permission_service.dart';
import '../../providers/app_settings_provider.dart';
import '../../providers/app_update_provider.dart';

/// App settings: appearance, updates, encoder preference, permissions, about.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _currentVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  /// Fetches the current app version for display in the Updates section.
  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _currentVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider);
    final updateState = ref.watch(appUpdateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // --- Appearance Section ---
          _SectionHeader(title: 'Appearance', icon: Icons.palette_outlined),
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
                    'Theme Mode',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose how the app adapts to system settings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.settings_brightness, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined, size: 18),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined, size: 18),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (selection) {
                      ref
                          .read(appSettingsProvider.notifier)
                          .setThemeMode(selection.first);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // --- Updates Section ---
          _SectionHeader(title: 'Updates', icon: Icons.system_update_outlined),
          const SizedBox(height: 8),
          _buildUpdateCard(context, updateState),
          const SizedBox(height: 24),

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
                    selected: {settings.encoderPreference},
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
                        AppSnackbar.show(
                          context: context,
                          title: 'Success!',
                          message: 'Notifications granted.',
                          contentType: ContentType.success,
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        AppSnackbar.show(
                          context: context,
                          title: 'Denied',
                          message: 'Permission denied.',
                          contentType: ContentType.failure,
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

  /// Builds the update card with dynamic UI based on the update lifecycle state.
  Widget _buildUpdateCard(BuildContext context, AppUpdateState state) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Version: $_currentVersion',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            switch (state.status) {
              UpdateStatus.idle || UpdateStatus.noUpdate => _buildCheckButton(),
              UpdateStatus.checking => const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
              UpdateStatus.updateAvailable => _buildAvailableUI(state),
              UpdateStatus.downloading => _buildDownloadingUI(state),
              UpdateStatus.readyToInstall => _buildReadyUI(state),
              UpdateStatus.error => _buildErrorUI(state),
            },
          ],
        ),
      ),
    );
  }

  /// Idle/No Update action button.
  Widget _buildCheckButton() {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        icon: const Icon(Icons.download_outlined),
        label: const Text('Check for Updates'),
        onPressed: () => ref.read(appUpdateProvider.notifier).checkForUpdate(),
      ),
    );
  }

  /// Update available confirmation with release notes.
  Widget _buildAvailableUI(AppUpdateState state) {
    final info = state.updateInfo!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Version ${info.version} is available!',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            info.releaseNotes,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => ref.read(appUpdateProvider.notifier).reset(),
                child: const Text('Later'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () =>
                    ref.read(appUpdateProvider.notifier).downloadUpdate(),
                child: const Text('Download'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Download progress indicator.
  Widget _buildDownloadingUI(AppUpdateState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Downloading... ${(state.downloadProgress * 100).toStringAsFixed(0)}%',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(value: state.downloadProgress),
      ],
    );
  }

  /// Installation prompt requiring confirmation.
  Widget _buildReadyUI(AppUpdateState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to install!',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The app will close and the Android installer will open. Continue?',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.system_update),
            label: const Text('Install Now'),
            onPressed: () async {
              await OpenFilex.open(state.downloadedPath!);
            },
          ),
        ),
      ],
    );
  }

  /// Error fallback UI with retry option.
  Widget _buildErrorUI(AppUpdateState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Update check failed',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          state.errorMessage ?? 'Unknown error',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () => ref.read(appUpdateProvider.notifier).reset(),
            child: const Text('Dismiss'),
          ),
        ),
      ],
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
