import 'package:flutter/material.dart';

/// Row of small stat chips summarizing the current queue state.
class StatusSummary extends StatelessWidget {
  const StatusSummary({
    super.key,
    required this.running,
    required this.queued,
    required this.completed,
  });

  final int running;
  final int queued;
  final int completed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _StatChip(
              icon: Icons.autorenew,
              color: Colors.blue,
              label: 'Running',
              value: running,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatChip(
              icon: Icons.schedule_outlined,
              color: Colors.grey,
              label: 'Queued',
              value: queued,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatChip(
              icon: Icons.check_circle_outline,
              color: Colors.green,
              label: 'Completed',
              value: completed,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
