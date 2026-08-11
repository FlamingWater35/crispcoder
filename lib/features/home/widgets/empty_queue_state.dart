import 'package:flutter/material.dart';

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
              ),
              child: Icon(
                Icons.video_library_outlined,
                size: 56,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text('No encodes queued', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap "New Encode" to pick a source video and start transcoding.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onNewEncode != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onNewEncode,
                icon: const Icon(Icons.add),
                label: const Text('New Encode'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
