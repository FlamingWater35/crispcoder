import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

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
              // Output-mode selector: a segmented control matching the
              // pre-redesign style, with an animated entrance.
              SegmentedButton<OutputType>(
                segments: const [
                  ButtonSegment(
                    value: OutputType.video,
                    label: Text('Video'),
                    icon: Icon(Icons.movie_outlined),
                  ),
                  ButtonSegment(
                    value: OutputType.audio,
                    label: Text('Audio'),
                    icon: Icon(Icons.music_note_outlined),
                  ),
                  ButtonSegment(
                    value: OutputType.subtitle,
                    label: Text('Subtitles'),
                    icon: Icon(Icons.subtitles_outlined),
                  ),
                ],
                selected: {outputType},
                onSelectionChanged: (selection) =>
                    onOutputTypeChanged(selection.first),
              ).animate(
                key: ValueKey('mode-selector'),
              ).fadeIn(
                delay: 150.ms,
                duration: 400.ms,
                curve: Curves.easeOut,
              ).slideY(
                begin: 0.12,
                end: 0,
                delay: 150.ms,
                duration: 400.ms,
                curve: Curves.easeOutCubic,
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
