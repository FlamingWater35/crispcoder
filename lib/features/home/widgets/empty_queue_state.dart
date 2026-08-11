import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Empty-queue placeholder prompting the user to add their first encode.
class EmptyQueueState extends StatelessWidget {
  const EmptyQueueState({super.key, this.onNewEncode});

  /// Invoked by the primary "New Encode" action. Defaults to null (hidden)
  /// so the widget stays usable standalone.
  final VoidCallback? onNewEncode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.primary.withValues(alpha: 0.35),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.video_library_outlined,
                size: 56,
                color: scheme.primary,
              ),
            )
                .animate()
                .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1, 1),
                  duration: 500.ms,
                  curve: Curves.easeOutBack,
                ),
            const SizedBox(height: 24),
            Text('No encodes queued', style: theme.textTheme.headlineSmall)
                .animate()
                .fadeIn(delay: 120.ms, duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),
            const SizedBox(height: 8),
            Text(
              'Tap "New Encode" to pick a source video and start transcoding.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
                .animate()
                .fadeIn(delay: 200.ms, duration: 400.ms)
                .slideY(begin: 0.1, end: 0, duration: 400.ms),
            if (onNewEncode != null) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onNewEncode,
                icon: const Icon(Icons.add),
                label: const Text('New Encode'),
              )
                  .animate()
                  .fadeIn(delay: 280.ms, duration: 400.ms)
                  .slideY(begin: 0.1, end: 0, duration: 400.ms),
            ],
          ],
        ),
      ),
    );
  }
}
