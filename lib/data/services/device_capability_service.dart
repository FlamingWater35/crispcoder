import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device_capability.dart';

/// Detects SoC capabilities (HW codec availability, ABI, SDK) at startup.
class DeviceCapabilityService {
  Future<DeviceCapability> detect() async {
    try {
      final plugin = DeviceInfoPlugin();
      final info = await plugin.androidInfo;

      // AV1 HW decode is supported on Android 14+ on most chipsets; encode rarer.
      final supportsAv1Hw = info.version.sdkInt >= 34;
      // HEVC HW encode is universally available on 64-bit Android >= 24
      final supportsHevcHw =
          info.version.sdkInt >= 24 &&
          info.supportedAbis.any((a) => a.startsWith('arm64'));
      final supportsH264Hw = info.version.sdkInt >= 23;

      return DeviceCapability(
        manufacturer: info.manufacturer,
        model: info.model,
        sdkInt: info.version.sdkInt,
        abis: info.supportedAbis.toList(),
        supportsH264Hw: supportsH264Hw,
        supportsHevcHw: supportsHevcHw,
        supportsAv1Hw: supportsAv1Hw,
        recommendedThreadCount: Platform.numberOfProcessors,
      );
    } catch (_) {
      // Conservative defaults if detection fails
      return const DeviceCapability(
        manufacturer: 'unknown',
        model: 'unknown',
        sdkInt: 30,
        abis: ['arm64-v8a'],
        supportsH264Hw: true,
        supportsHevcHw: false,
        supportsAv1Hw: false,
        recommendedThreadCount: 4,
      );
    }
  }
}

final deviceCapabilityServiceProvider = Provider<DeviceCapabilityService>(
  (ref) => DeviceCapabilityService(),
);
