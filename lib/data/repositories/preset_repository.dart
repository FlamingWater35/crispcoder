import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/hive_box_util.dart';
import '../models/transcode_preset.dart';

/// Hive-backed CRUD for transcode presets.
/// Bootstraps built-in defaults on first run; never throws on Hive failure
/// (falls back to an in-memory box).
class PresetRepository {
  PresetRepository._();
  static final PresetRepository instance = PresetRepository._();

  late Box<TranscodePreset> _box;
  bool _initialized = false;

  Future<void> bootstrap() async {
    if (_initialized) {
      return;
    }
    // openHiveBox never throws: falls back to an in-memory box if the
    // on-disk box cannot be opened.
    _box = await openHiveBox<TranscodePreset>(AppConstants.boxPresets);
    if (_box.isEmpty) {
      for (final p in AppConstants.defaultPresets()) {
        await _box.put(p.id, p);
      }
    }
    _initialized = true;
  }

  List<TranscodePreset> get all =>
      _box.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  TranscodePreset? byId(String id) => _box.get(id);

  Future<void> upsert(TranscodePreset preset) async {
    await _box.put(preset.id, preset);
  }

  Future<void> delete(String id) async {
    final p = _box.get(id);
    if (p != null && p.isBuiltIn) {
      return; // protect built-in presets
    }
    await _box.delete(id);
  }
}
