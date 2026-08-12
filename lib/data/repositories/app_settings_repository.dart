import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/hive_box_util.dart';
import '../models/transcode_preset.dart';

/// Hive-backed store for user-level app settings (theme, encoder preference).
/// Falls back to defaults if Hive is unavailable.
class AppSettingsRepository {
  AppSettingsRepository._();
  static final AppSettingsRepository instance = AppSettingsRepository._();

  late Box _box;
  bool _initialized = false;

  /// Opens the settings box; safe to call multiple times.
  Future<void> bootstrap() async {
    if (_initialized) return;
    // openHiveBox never throws: falls back to an in-memory box if the
    // on-disk box cannot be opened.
    _box = await openHiveBox(AppConstants.boxSettings);
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

  /// Returns the persisted theme mode; defaults to system.
  ThemeMode get themeMode {
    try {
      final idx = _box.get(AppConstants.keyThemeMode) as int?;
      if (idx == null || idx < 0 || idx >= ThemeMode.values.length) {
        return ThemeMode.system;
      }
      return ThemeMode.values[idx];
    } catch (_) {
      return ThemeMode.system;
    }
  }

  /// Persists the theme mode selection.
  Future<void> setThemeMode(ThemeMode mode) async {
    try {
      await _box.put(AppConstants.keyThemeMode, mode.index);
    } catch (_) {
      // Best-effort write
    }
  }

  /// Returns the custom output directory path; null if not set.
  String? get outputDirectory {
    try {
      return _box.get(AppConstants.keyOutputDirectory) as String?;
    } catch (_) {
      return null;
    }
  }

  /// Persists the custom output directory path.
  Future<void> setOutputDirectory(String? path) async {
    try {
      await _box.put(AppConstants.keyOutputDirectory, path);
    } catch (_) {
      // Best-effort write
    }
  }
}
