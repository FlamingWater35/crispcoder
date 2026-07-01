import '../../data/models/transcode_preset.dart';

/// Static FFmpeg flags and Handbrake-style default presets.
class AppConstants {
  AppConstants._();

  // FFmpeg tuning flags
  static const flagFaststart = '-movflags';
  static const flagFaststartValue = '+faststart';
  static const flagYes = '-y';
  static const flagOverwrite = '-y';

  // Hive box names
  static const boxPresets = 'presets';
  static const boxQueue = 'queue';
  static const boxHistory = 'history';
  static const boxSettings = 'app_settings';

  // App settings keys
  static const keyEncoderPref = 'encoder_preference';

  // Foreground service
  static const fgNotificationChannelId = 'videocode_encode';
  static const fgNotificationChannelName = 'Active Encodes';

  /// Default Handbrake-equivalent presets inserted on first run.
  static List<TranscodePreset> defaultPresets() => [
    TranscodePreset(
      id: 'builtin_fast_1080p30',
      name: 'Fast 1080p30',
      category: 'General',
      videoCodec: VideoCodec.h264,
      crf: 22,
      resolution: '1920x1080',
      framerate: 30,
      audioCodec: AudioCodec.aac,
      audioBitrate: 160,
      container: ContainerFormat.mp4,
      encoderPref: EncoderPreference.auto,
      faststart: true,
      isBuiltIn: true,
    ),
    TranscodePreset(
      id: 'builtin_hq_4k_hevc',
      name: 'HQ 4K HEVC',
      category: 'General',
      videoCodec: VideoCodec.hevc,
      crf: 23,
      resolution: '3840x2160',
      framerate: null,
      audioCodec: AudioCodec.aac,
      audioBitrate: 192,
      container: ContainerFormat.mp4,
      encoderPref: EncoderPreference.auto,
      faststart: true,
      isBuiltIn: true,
    ),
    TranscodePreset(
      id: 'builtin_compatible_720p',
      name: 'Compatible 720p',
      category: 'Devices',
      videoCodec: VideoCodec.h264,
      crf: 24,
      resolution: '1280x720',
      framerate: 30,
      audioCodec: AudioCodec.aac,
      audioBitrate: 128,
      container: ContainerFormat.mp4,
      encoderPref: EncoderPreference.software,
      faststart: true,
      isBuiltIn: true,
    ),
    TranscodePreset(
      id: 'builtin_max_compression',
      name: 'Max Compression',
      category: 'Web',
      videoCodec: VideoCodec.hevc,
      crf: 28,
      resolution: null,
      framerate: null,
      audioCodec: AudioCodec.opus,
      audioBitrate: 96,
      container: ContainerFormat.mkv,
      encoderPref: EncoderPreference.software,
      faststart: false,
      twoPass: true,
      isBuiltIn: true,
    ),
  ];
}
