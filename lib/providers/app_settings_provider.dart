import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transcode_preset.dart';
import '../data/repositories/app_settings_repository.dart';

/// Immutable state holding app-wide settings.
class AppSettingsState {
  final EncoderPreference encoderPreference;
  final ThemeMode themeMode;

  const AppSettingsState({
    required this.encoderPreference,
    required this.themeMode,
  });

  AppSettingsState copyWith({
    EncoderPreference? encoderPreference,
    ThemeMode? themeMode,
  }) {
    return AppSettingsState(
      encoderPreference: encoderPreference ?? this.encoderPreference,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

/// Reactive global app settings. Tracks encoder preference and theme mode.
final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(
      AppSettingsNotifier.new,
    );

class AppSettingsNotifier extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() {
    final repo = AppSettingsRepository.instance;
    return AppSettingsState(
      encoderPreference: repo.encoderPreference,
      themeMode: repo.themeMode,
    );
  }

  /// Updates and persists the encoder preference.
  Future<void> setEncoderPreference(EncoderPreference pref) async {
    await AppSettingsRepository.instance.setEncoderPreference(pref);
    state = state.copyWith(encoderPreference: pref);
  }

  /// Updates and persists the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    await AppSettingsRepository.instance.setThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }
}
