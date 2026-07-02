import 'package:flutter/material.dart';

import '../../../../data/models/media_info.dart';
import '../../../../data/models/transcode_preset.dart';
import '../preset_dropdown.dart';
import '../section_card.dart';

/// Quick Edit Tab: Presets, Trimming, Cropping, Subtitles, Remove Audio
class QuickEditTab extends StatelessWidget {
  const QuickEditTab({
    super.key,
    required this.presets,
    required this.selectedPresetId,
    required this.onPresetChanged,
    required this.outputType,
    required this.startController,
    required this.endController,
    required this.sourcePath,
    required this.removeAudio,
    required this.onRemoveAudioChanged,
    required this.subtitleTracks,
    required this.burnSubtitleIndex,
    required this.onSubtitleChanged,
    required this.onTrimPreview,
  });

  final List<TranscodePreset> presets;
  final String? selectedPresetId;
  final void Function(String?) onPresetChanged;
  final OutputType outputType;
  final TextEditingController startController;
  final TextEditingController endController;
  final String? sourcePath;
  final bool removeAudio;
  final void Function(bool) onRemoveAudioChanged;
  final List<SubtitleTrack> subtitleTracks;
  final int? burnSubtitleIndex;
  final void Function(int?) onSubtitleChanged;
  final VoidCallback onTrimPreview;

  String? _validateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final regex = RegExp(r'^(\d{1,2}):([0-5]\d):([0-5]\d)$');
    if (!regex.hasMatch(value)) {
      return 'Use HH:MM:SS format';
    }
    return null;
  }

  Duration? _parseTimeToDuration(String? value) {
    if (value == null || value.isEmpty) return null;
    final regex = RegExp(r'^(\d{1,2}):([0-5]\d):([0-5]\d)$');
    final match = regex.firstMatch(value);
    if (match == null) return null;
    return Duration(
      hours: int.parse(match.group(1)!),
      minutes: int.parse(match.group(2)!),
      seconds: int.parse(match.group(3)!),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final startDur = _parseTimeToDuration(startController.text);
    final endDur = _parseTimeToDuration(endController.text);
    final trimDuration =
        (startDur != null && endDur != null && endDur > startDur)
        ? endDur - startDur
        : null;

    List<Widget> editChildren = [
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: startController,
              validator: _validateTime,
              decoration: const InputDecoration(
                labelText: 'Start Time',
                hintText: '00:00:00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.play_arrow, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: endController,
              validator: _validateTime,
              decoration: const InputDecoration(
                labelText: 'End Time',
                hintText: '00:00:00',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.stop, size: 20),
              ),
            ),
          ),
        ],
      ),
      if (trimDuration != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Trimmed length: ${_formatDuration(trimDuration)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.content_cut_rounded),
          label: const Text('Trim Visually'),
          onPressed: sourcePath != null ? onTrimPreview : null,
        ),
      ),
    ];

    // Add Mode-Specific options
    if (outputType == OutputType.video) {
      editChildren.addAll([
        const SizedBox(height: 16),
        // Wrapped SwitchListTile in a Card for proper focus styling and rounding
        Card(
          elevation: 0,
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: SwitchListTile(
            title: const Text('Remove Audio'),
            subtitle: const Text('Strip the audio track from the output'),
            value: removeAudio,
            onChanged: onRemoveAudioChanged,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Hardcode Subtitles (Burn-in)', style: labelStyle),
        const SizedBox(height: 8),
        // Subtitle Chips
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: burnSubtitleIndex == null,
              onSelected: (_) => onSubtitleChanged(null),
            ),
            for (final sub in subtitleTracks)
              ChoiceChip(
                label: Text(sub.label),
                selected: burnSubtitleIndex == sub.subtitleStreamIndex,
                onSelected: (_) => onSubtitleChanged(sub.subtitleStreamIndex),
              ),
          ],
        ),
      ]);
    } else if (outputType == OutputType.subtitle) {
      editChildren.addAll([
        const SizedBox(height: 16),
        Text('Extract Subtitle Track', style: labelStyle),
        const SizedBox(height: 8),
        // Subtitle Chips
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            for (final sub in subtitleTracks)
              ChoiceChip(
                label: Text(sub.label),
                selected: burnSubtitleIndex == sub.subtitleStreamIndex,
                onSelected: (_) => onSubtitleChanged(sub.subtitleStreamIndex),
              ),
          ],
        ),
      ]);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Preset',
            icon: Icons.tune_rounded,
            children: [
              PresetDropdown(
                presets: presets,
                selectedPresetId: selectedPresetId,
                onChanged: onPresetChanged,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Editing & Trimming',
            icon: Icons.content_cut_rounded,
            children: editChildren,
          ),
        ],
      ),
    );
  }
}
