import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/transcode_preset.dart';
import '../../../providers/app_settings_provider.dart';

/// Builds a small info banner showing the current global encoder preference.
class EncoderPrefInfo extends ConsumerWidget {
  const EncoderPrefInfo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pref = ref.watch(appSettingsProvider).encoderPreference;
    final label = switch (pref) {
      EncoderPreference.auto => 'Auto',
      EncoderPreference.hardware => 'Hardware',
      EncoderPreference.software => 'Software',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.memory_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Encoder: $label — configurable in Settings',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Icon(
            Icons.settings_outlined,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
