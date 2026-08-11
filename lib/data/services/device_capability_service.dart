import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_capability.dart';

/// Detects SoC capabilities (HW codec availability, ABI, SDK) at startup.
///
/// SDK/ABI heuristics are only used as a first-pass filter. Actual support is
/// verified at runtime by querying the FFmpeg build's encoder list — a device
/// may have a high SDK level yet no usable MediaCodec encoder for a codec,
/// and assuming it does produces broken encodes.
class DeviceCapabilityService {
  /// Parses `ffmpeg -encoders` output for MediaCodec encoder names.
  /// Pure function so it can be unit-tested without a device.
  static Set<String> parseMediacodecEncoders(String output) {
    return <String>{
      if (output.contains('h264_mediacodec')) 'h264_mediacodec',
      if (output.contains('hevc_mediacodec')) 'hevc_mediacodec',
      if (output.contains('av1_mediacodec')) 'av1_mediacodec',
    };
  }

  /// Queries the FFmpeg build for the names of MediaCodec encoders it
  /// actually ships with (e.g. `h264_mediacodec`).
  Future<Set<String>> detectAvailableMediacodecEncoders() async {
    try {
      final session = await FFmpegKit.execute('-hide_banner -encoders');
      final logs = await session.getAllLogsAsString(5000);
      return parseMediacodecEncoders(logs ?? '');
    } catch (_) {
      // Detection is best-effort; caller falls back to heuristics.
      return const {};
    }
  }

  Future<DeviceCapability> detect() async {
    var manufacturer = 'unknown';
    var model = 'unknown';
    var sdkInt = 30;
    var abis = <String>['arm64-v8a'];

    try {
      final plugin = DeviceInfoPlugin();
      final info = await plugin.androidInfo;
      manufacturer = info.manufacturer;
      model = info.model;
      sdkInt = info.version.sdkInt;
      abis = info.supportedAbis.toList();
    } catch (_) {
      // Conservative defaults if detection fails
    }

    // Heuristic pre-filter (what the device *could* support).
    final heuristicH264 = sdkInt >= 23;
    final heuristicHevc =
        sdkInt >= 24 && abis.any((a) => a.startsWith('arm64'));
    final heuristicAv1 = sdkInt >= 34;

    // Runtime verification: only claim support for encoders the FFmpeg build
    // actually contains. If detection fails, fall back to heuristics.
    final available = await detectAvailableMediacodecEncoders();
    final hasRealCheck = available.isNotEmpty;

    return DeviceCapability(
      manufacturer: manufacturer,
      model: model,
      sdkInt: sdkInt,
      abis: abis,
      supportsH264Hw: hasRealCheck
          ? available.contains('h264_mediacodec')
          : heuristicH264,
      supportsHevcHw: hasRealCheck
          ? available.contains('hevc_mediacodec')
          : heuristicHevc,
      supportsAv1Hw: hasRealCheck
          ? available.contains('av1_mediacodec')
          : heuristicAv1,
      recommendedThreadCount: Platform.numberOfProcessors,
    );
  }
}

final deviceCapabilityServiceProvider = Provider<DeviceCapabilityService>(
  (ref) => DeviceCapabilityService(),
);
