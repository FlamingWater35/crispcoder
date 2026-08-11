import 'package:flutter/material.dart';

import '../../../data/models/transcode_preset.dart';
import 'source_picker.dart';

/// Inviting onboarding view shown before any source video is selected.
///
/// Replaces the bare mode-selector + picker with a centered, guided layout:
/// a hero icon, a short explanation, the output-mode choice, and the large
/// source-picker card that starts the whole flow.
class EditorWelcomeView extends StatelessWidget {
  const EditorWelcomeView({
    super.key,
    required this.outputType,
    required this.onOutputTypeChanged,
    required this.probing,
    required this.onPick,
  });

  final OutputType outputType;
  final ValueChanged<OutputType> onOutputTypeChanged;
  final bool probing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Hero icon
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primaryContainer,
                      scheme.primary.withValues(alpha: 0.4),
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
                  Icons.video_library_rounded,
                  size: 48,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Start a new encode',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a source video, choose what you want to produce, '
                'and tune the settings to your liking.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Output-mode selector (chips instead of a heavy segmented bar)
              Text(
                'What do you want to produce?',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _ModeChip(
                    icon: Icons.movie_outlined,
                    label: 'Video',
                    selected: outputType == OutputType.video,
                    onTap: () => onOutputTypeChanged(OutputType.video),
                  ),
                  _ModeChip(
                    icon: Icons.music_note_outlined,
                    label: 'Audio',
                    selected: outputType == OutputType.audio,
                    onTap: () => onOutputTypeChanged(OutputType.audio),
                  ),
                  _ModeChip(
                    icon: Icons.subtitles_outlined,
                    label: 'Subtitles',
                    selected: outputType == OutputType.subtitle,
                    onTap: () => onOutputTypeChanged(OutputType.subtitle),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // The big source picker card
              SourcePicker(
                path: null,
                probing: probing,
                onPick: onPick,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selectable chip for the output-mode choice.
class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        // Compact vertical padding so chips sit closer together.
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.8)
                : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
