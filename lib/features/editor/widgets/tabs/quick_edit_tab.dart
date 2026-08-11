import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.isVideoCopy,
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

  /// Whether video passthrough (copy) is active. Burn-in requires a
  /// re-encoded video stream, so the subtitle chips are hidden when true.
  final bool isVideoCopy;
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

  /// Compact decoration for the start/end time fields: shorter vertical
  /// padding so the row is slimmer than the default inputs.
  InputDecoration _timeDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: '00:00:00',
      border: OutlineInputBorder(),
      prefixIcon: Icon(icon, size: 20),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
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
              decoration: _timeDecoration(
                label: 'Start Time',
                icon: Icons.play_arrow,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: const [TimeInputFormatter()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: endController,
              validator: _validateTime,
              decoration: _timeDecoration(
                label: 'End Time',
                icon: Icons.stop,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: const [TimeInputFormatter()],
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
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
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
            title: Text(
              'Remove Audio',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Strip the audio track from the output',
              style: theme.textTheme.bodySmall,
            ),
            value: removeAudio,
            onChanged: onRemoveAudioChanged,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (isVideoCopy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Subtitle burn-in is unavailable while copying video (no '
              're-encode). Choose a video codec to burn subtitles.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else ...[
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
                  onSelected: (_) =>
                      onSubtitleChanged(sub.subtitleStreamIndex),
                ),
            ],
          ),
        ],
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

    // Compact density scoped to the tab so choice chips stay smaller than the
    // 48px default tap target without shrinking the app's other controls.
    return Theme(
      data: Theme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: SingleChildScrollView(
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
      ),
    );
  }
}

/// Restricts input to the strict `HH:MM:SS` time format.
///
/// Only digits and colons are allowed; colons are auto-inserted every two
/// digits and the value is capped at 8 characters, so users can't type
/// arbitrary text into the start/end time fields.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Keep only digits, then rebuild as HH:MM:SS.
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final capped = digits.length > 6 ? digits.substring(0, 6) : digits;

    final buffer = StringBuffer();
    for (var i = 0; i < capped.length; i++) {
      if (i == 2 || i == 4) buffer.write(':');
      buffer.write(capped[i]);
    }

    final formatted = buffer.toString();
    // Preserve cursor position roughly: place it after the formatted text.
    final selectionEnd = formatted.length;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: selectionEnd),
    );
  }
}
