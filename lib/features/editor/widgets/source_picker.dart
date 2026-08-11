import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Source video selector: opens the platform file picker (SAF on Android).
/// Shows a prominent tappable card with loading and picked states.
///
/// While [probing] is true the card renders an animated pulsing indicator —
/// a breathing ring around the icon plus an indeterminate progress bar —
/// instead of a tiny static spinner.
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
    final scheme = theme.colorScheme;
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
                  ? scheme.primaryContainer.withValues(alpha: 0.3)
                  : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPicked
                    ? scheme.primary.withValues(alpha: 0.5)
                    : scheme.outlineVariant,
                width: isPicked ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Icon with a breathing pulse while probing.
                    _PulsingIcon(
                      probing: probing,
                      isPicked: isPicked,
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
                          strokeWidth: 2.5,
                          color: scheme.primary,
                        ),
                      )
                    else
                      Icon(
                        isPicked ? Icons.edit_outlined : Icons.add,
                        color: scheme.onSurfaceVariant,
                      ),
                  ],
                ),
                // Indeterminate progress bar shown only while loading.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: probing
                      ? Padding(
                          key: const ValueKey('probing-bar'),
                          padding: const EdgeInsets.only(top: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const LinearProgressIndicator(
                              minHeight: 4,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon tile that "breathes" (expands a fading halo ring) while probing.
///
/// Uses flutter_animate's repeat so the ticker lifecycle is managed safely by
/// the package (no manual AnimationController teardown issues in tests).
class _PulsingIcon extends StatelessWidget {
  const _PulsingIcon({required this.probing, required this.isPicked});

  final bool probing;
  final bool isPicked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding halo ring while probing.
          if (probing)
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
            ).animate(
              onPlay: (controller) => controller.repeat(reverse: true),
            ).scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.4, 1.4),
              duration: 1100.ms,
              curve: Curves.easeOut,
            ).fadeOut(
              duration: 1100.ms,
              curve: Curves.easeOut,
            ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isPicked ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              probing
                  ? Icons.hourglass_top
                  : (isPicked ? Icons.video_file : Icons.folder_open_outlined),
              color: isPicked ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
