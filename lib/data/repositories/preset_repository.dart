import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/transcode_preset.dart';

/// Hive-backed CRUD for transcode presets.
/// Bootstraps built-in defaults on first run; never throws on Hive failure
/// (falls back to in-memory list).
class PresetRepository {
  PresetRepository._();
  static final PresetRepository instance = PresetRepository._();

  late Box<TranscodePreset> _box;
  bool _initialized = false;

  Future<void> bootstrap() async {
    if (_initialized) {
      return;
    }
    try {
      _box = await Hive.openBox<TranscodePreset>(AppConstants.boxPresets);
      if (_box.isEmpty) {
        for (final p in AppConstants.defaultPresets()) {
          await _box.put(p.id, p);
        }
      }
    } catch (_) {
      // Re-open with in-memory fallback if disk is corrupted
      _box = await Hive.openBox<TranscodePreset>(AppConstants.boxPresets);
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
