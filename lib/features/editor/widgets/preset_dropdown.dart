import 'package:flutter/material.dart';

import '../../../data/models/transcode_preset.dart';

/// Dropdown for selecting a built-in or custom preset.
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
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: 'Preset',
        border: OutlineInputBorder(),
      ),
      initialValue: selectedPresetId,
      items: [
        const DropdownMenuItem(
          value: 'custom',
          child: Text('Custom (Match Source)'),
        ),
        for (final p in presets)
          DropdownMenuItem(value: p.id, child: Text(p.name)),
      ],
      onChanged: onChanged,
    );
  }
}
