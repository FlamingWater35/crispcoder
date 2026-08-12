import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transcode_preset.dart';
import '../data/repositories/app_settings_repository.dart';

/// Immutable state holding app-wide settings.
class AppSettingsState {
  final EncoderPreference encoderPreference;
  final ThemeMode themeMode;
  final String? outputDirectory;
  final bool useFilePickerPackage;

  const AppSettingsState({
    required this.encoderPreference,
    required this.themeMode,
    this.outputDirectory,
    this.useFilePickerPackage = false,
  });

  AppSettingsState copyWith({
    EncoderPreference? encoderPreference,
    ThemeMode? themeMode,
    String? outputDirectory,
    bool? useFilePickerPackage,
  }) {
    return AppSettingsState(
      encoderPreference: encoderPreference ?? this.encoderPreference,
      themeMode: themeMode ?? this.themeMode,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      useFilePickerPackage: useFilePickerPackage ?? this.useFilePickerPackage,
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
      outputDirectory: repo.outputDirectory,
      useFilePickerPackage: repo.useFilePickerPackage,
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

  /// Updates and persists the custom output directory.
  Future<void> setOutputDirectory(String? path) async {
    await AppSettingsRepository.instance.setOutputDirectory(path);
    state = state.copyWith(outputDirectory: path);
  }

  /// Updates and persists the source-picker preference.
  Future<void> setUseFilePickerPackage(bool value) async {
    await AppSettingsRepository.instance.setUseFilePickerPackage(value);
    state = state.copyWith(useFilePickerPackage: value);
  }
}
