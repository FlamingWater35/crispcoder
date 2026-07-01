/// SoC capability flags driving auto-encoder selection.
class DeviceCapability {
  final String manufacturer;
  final String model;
  final int sdkInt;
  final List<String> abis;
  final bool supportsH264Hw;
  final bool supportsHevcHw;
  final bool supportsAv1Hw;
  final int recommendedThreadCount;

  const DeviceCapability({
    required this.manufacturer,
    required this.model,
    required this.sdkInt,
    required this.abis,
    required this.supportsH264Hw,
    required this.supportsHevcHw,
    required this.supportsAv1Hw,
    required this.recommendedThreadCount,
  });

  /// Heuristic: prefer HW only on 64-bit ARM, SDK >= 23.
  bool get preferHardware =>
      abis.any((a) => a.startsWith('arm64')) && sdkInt >= 23;

  String get summary => '$manufacturer $model (SDK $sdkInt)';
}
