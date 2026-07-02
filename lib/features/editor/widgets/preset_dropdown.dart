import 'package:flutter/material.dart';

import '../../../data/models/transcode_preset.dart';

/// Selector for choosing a built-in or custom preset using ChoiceChips.
class PresetDropdown extends StatelessWidget {
  const PresetDropdown({
    super.key,
    required this.presets,
    required this.selectedPresetId,
    required this.onChanged,
  });

  final List<TranscodePreset> presets;
  final String? selectedPresetId;
  final void Function(String?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8.0,
      runSpacing: 8.0,
      children: [
        ChoiceChip(
          label: const Text('Custom (Match Source)'),
          selected: selectedPresetId == 'custom',
          onSelected: (_) => onChanged('custom'),
        ),
        for (final p in presets)
          ChoiceChip(
            label: Text(p.name),
            selected: selectedPresetId == p.id,
            onSelected: (_) => onChanged(p.id),
          ),
      ],
    );
  }
}
