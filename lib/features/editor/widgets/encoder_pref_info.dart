import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/transcode_preset.dart';
import '../../../providers/app_settings_provider.dart';

/// Builds a small info banner showing the resolved encoder and any warnings.
/// Turns red and displays a warning if software encoding is forced.
class EncoderPrefInfo extends ConsumerWidget {
  const EncoderPrefInfo({
    super.key,
    required this.isUsingHw,
    required this.feedbackMessage,
  });

  final bool isUsingHw;
  final String feedbackMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pref = ref.watch(appSettingsProvider).encoderPreference;

    String label = isUsingHw ? 'Hardware' : 'Software';

    final bool isForced = feedbackMessage.isNotEmpty;
    if (!isForced) {
      if (pref == EncoderPreference.auto) {
        label += ' (Auto)';
      } else {
        label += ' (Forced)';
      }
    }

    Color bgColor = theme.colorScheme.surfaceContainerHighest.withValues(
      alpha: 0.5,
    );
    Color fgColor = theme.colorScheme.onSurfaceVariant;
    if (isForced) {
      bgColor = theme.colorScheme.errorContainer.withValues(alpha: 0.5);
      fgColor = theme.colorScheme.onErrorContainer;
    }

    String text = isForced
        ? 'Encoder: Software (Forced) — $feedbackMessage'
        : 'Encoder: $label — configurable in Settings';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isUsingHw ? Icons.memory : Icons.developer_board,
            size: 16,
            color: fgColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(color: fgColor),
            ),
          ),
          Icon(Icons.settings_outlined, size: 16, color: fgColor),
        ],
      ),
    );
  }
}
