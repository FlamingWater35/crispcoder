import 'package:flutter/material.dart';

/// Source video selector: opens the platform file picker (SAF on Android).
/// Shows a prominent tappable card with loading and picked states.
class SourcePicker extends StatelessWidget {
  const SourcePicker({
    super.key,
    required this.path,
    required this.probing,
    required this.onPick,
  });

  final String? path;
  final bool probing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPicked = path != null;

    return Semantics(
      label: probing
          ? 'Reading source video'
          : isPicked
          ? 'Source video: ${path!.split('/').last}. Tap to change.'
          : 'Select source video',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: probing ? null : onPick,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isPicked
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPicked
                    ? theme.colorScheme.primary.withValues(alpha: 0.5)
                    : theme.colorScheme.outlineVariant,
                width: isPicked ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isPicked
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    probing
                        ? Icons.hourglass_top
                        : (isPicked
                              ? Icons.video_file
                              : Icons.folder_open_outlined),
                    color: isPicked
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        probing
                            ? 'Reading source…'
                            : (isPicked
                                  ? 'Source video'
                                  : 'Select source video'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        probing
                            ? 'Analyzing metadata'
                            : (isPicked
                                  ? path!.split('/').last
                                  : 'Tap to choose a video file'),
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
                if (probing)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    isPicked ? Icons.edit_outlined : Icons.add,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
