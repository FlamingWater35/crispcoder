import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/transcode_preset.dart';
import '../data/repositories/app_settings_repository.dart';

/// Reactive global app settings. Currently tracks the encoder preference
/// that the editor applies to every new encode.
final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, EncoderPreference>(
      AppSettingsNotifier.new,
    );

class AppSettingsNotifier extends Notifier<EncoderPreference> {
  @override
  EncoderPreference build() {
    return AppSettingsRepository.instance.encoderPreference;
  }

  /// Updates and persists the encoder preference.
  Future<void> setEncoderPreference(EncoderPreference pref) async {
    await AppSettingsRepository.instance.setEncoderPreference(pref);
    state = pref;
  }
}
