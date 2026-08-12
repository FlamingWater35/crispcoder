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
    required this.subtitleFormat,
    required this.onSubtitleFormatChanged,
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
  final SubtitleFormat subtitleFormat;
  final void Function(SubtitleFormat) onSubtitleFormatChanged;
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
                  label: Text(
                    sub.isTextSubtitle
                        ? sub.label
                        : '${sub.label} (image-based)',
                  ),
                  // Image-based tracks (PGS/DVD/VobSub) cannot be burned in
                  // with libass — mark them disabled so the user is not
                  // surprised by a silent failure.
                  onSelected: sub.isTextSubtitle
                      ? (_) => onSubtitleChanged(sub.subtitleStreamIndex)
                      : null,
                  selected: burnSubtitleIndex == sub.subtitleStreamIndex,
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
        // Subtitle Chips. Image-based tracks (PGS/DVD/VobSub) cannot be
        // converted to SRT/ASS by FFmpeg, so they are disabled and labelled.
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: [
            for (final sub in subtitleTracks)
              ChoiceChip(
                label: Text(
                  sub.isTextSubtitle
                      ? sub.label
                      : '${sub.label} (image-based)',
                ),
                selected: burnSubtitleIndex == sub.subtitleStreamIndex,
                onSelected: sub.isTextSubtitle
                    ? (_) => onSubtitleChanged(sub.subtitleStreamIndex)
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Subtitle Format', style: labelStyle),
        const SizedBox(height: 8),
        // Output format chips: SRT (plain text) or ASS (styling support).
        Wrap(
          spacing: 8.0,
          runSpacing: 8.0,
          children: SubtitleFormat.values.map((f) {
            return ChoiceChip(
              label: Text(f.name.toUpperCase()),
              selected: subtitleFormat == f,
              onSelected: (_) => onSubtitleFormatChanged(f),
            );
          }).toList(),
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
/// Only digits are allowed; colons are auto-inserted every two digits. The
/// value is capped at 6 digits. Short inputs are right-aligned: `5` means
/// `00:00:05`, `1234` means `00:12:34` (MM:SS) and `123456` is `12:34:56` —
/// never `01:23:4` left-padded. Minutes and seconds are clamped to 0–59 so
/// `99` seconds becomes `00:59`.
class TimeInputFormatter extends TextInputFormatter {
  const TimeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Keep only digits, then pad left to 6 so the value reads naturally:
    // HH:MM:SS with the typed digits right-aligned.
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final capped = digits.length > 6 ? digits.substring(0, 6) : digits;
    final padded = capped.padLeft(6, '0');

    String clampTwo(String raw) {
      final n = int.tryParse(raw) ?? 0;
      return n.clamp(0, 59).toString().padLeft(2, '0');
    }

    final formatted = [
      padded.substring(0, 2),
      clampTwo(padded.substring(2, 4)),
      clampTwo(padded.substring(4, 6)),
    ].join(':');

    // Place the cursor after the formatted text.
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
