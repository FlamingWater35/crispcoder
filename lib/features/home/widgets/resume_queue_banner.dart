import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Prominent action shown when the queue has pending work but nothing is
/// running — e.g. right after the app is reopened and the persisted queue is
/// restored. Tapping it starts the next pending encode.
class ResumeQueueBanner extends StatelessWidget {
  const ResumeQueueBanner({super.key, required this.onResume, this.count});

  final VoidCallback onResume;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Card(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.onSecondaryContainer.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count != null && count! > 1
                          ? 'Resume queue'
                          : 'Resume encode',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      count != null && count! > 1
                          ? '$count tasks waiting'
                          : 'One task waiting',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSecondaryContainer.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: onResume,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.onSecondaryContainer,
                  foregroundColor: scheme.secondaryContainer,
                ),
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1, end: 0);
  }
}
