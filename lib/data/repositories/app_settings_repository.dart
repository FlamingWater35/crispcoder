import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../models/transcode_preset.dart';

/// Hive-backed store for user-level app settings (encoder preference, etc.).
/// Falls back to defaults if Hive is unavailable.
class AppSettingsRepository {
  AppSettingsRepository._();
  static final AppSettingsRepository instance = AppSettingsRepository._();

  late Box _box;
  bool _initialized = false;

  /// Opens the settings box; safe to call multiple times.
  Future<void> bootstrap() async {
    if (_initialized) return;
    try {
      _box = await Hive.openBox(AppConstants.boxSettings);
    } catch (_) {
      // Re-attempt open; Hive will provide an in-memory box on failure
      _box = await Hive.openBox(AppConstants.boxSettings);
    }
    _initialized = true;
  }

  /// Returns the persisted encoder preference; defaults to auto.
  EncoderPreference get encoderPreference {
    try {
      final idx = _box.get(AppConstants.keyEncoderPref) as int?;
      if (idx == null || idx < 0 || idx >= EncoderPreference.values.length) {
        return EncoderPreference.auto;
      }
      return EncoderPreference.values[idx];
    } catch (_) {
      return EncoderPreference.auto;
    }
  }

  /// Persists the encoder preference selection.
  Future<void> setEncoderPreference(EncoderPreference pref) async {
    try {
      await _box.put(AppConstants.keyEncoderPref, pref.index);
    } catch (_) {
      // Best-effort write; value won't persist but in-memory state stays correct
    }
  }
}
