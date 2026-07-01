import 'package:flutter/material.dart';

/// Sticky bottom action bar with Preview and Start Encode buttons.
class EditorActionBar extends StatelessWidget {
  const EditorActionBar({
    super.key,
    required this.canSubmit,
    required this.hasSource,
    required this.onPreview,
    required this.onSubmit,
  });

  final bool canSubmit;
  final bool hasSource;
  final VoidCallback onPreview;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_outlined),
                  label: const Text('Preview'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: hasSource ? onPreview : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.queue),
                  label: const Text('Start Encode'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: canSubmit ? onSubmit : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
