import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transcode_preset.dart';
import '../data/repositories/preset_repository.dart';

/// Reactive list of presets backed by Hive. Use `.upsert`/`.delete` to mutate.
final presetProvider = NotifierProvider<PresetNotifier, List<TranscodePreset>>(
  PresetNotifier.new,
);

class PresetNotifier extends Notifier<List<TranscodePreset>> {
  @override
  List<TranscodePreset> build() {
    return PresetRepository.instance.all;
  }

  Future<void> upsert(TranscodePreset preset) async {
    await PresetRepository.instance.upsert(preset);
    state = PresetRepository.instance.all;
  }

  Future<void> delete(String id) async {
    await PresetRepository.instance.delete(id);
    state = PresetRepository.instance.all;
  }

  TranscodePreset? byId(String id) => state.firstWhereOrNull((p) => p.id == id);
}
