import 'package:flutter/material.dart';

/// Empty-queue placeholder prompting the user to add their first encode.
class EmptyQueueState extends StatelessWidget {
  const EmptyQueueState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.video_library_outlined,
              size: 96,
              color: theme.colorScheme.primary.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text('No encodes queued', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Tap "New Encode" to pick a source video and start transcoding.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
