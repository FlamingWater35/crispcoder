import '../../core/utils/format_parsers.dart';

/// Immutable snapshot of an encode's real-time progress, suitable for UI.
class EncodeProgress {
  final String taskId;
  final double percent;
  final double fps;
  final double speed;
  final int? etaSeconds;
  final double? bitrateBitsPerSec;
  final int frameNumber;
  final int bytesProcessed;

  const EncodeProgress({
    required this.taskId,
    required this.percent,
    required this.fps,
    required this.speed,
    this.etaSeconds,
    this.bitrateBitsPerSec,
    required this.frameNumber,
    required this.bytesProcessed,
  });

  String get formattedPercent => '${percent.toStringAsFixed(1)}%';
  String get formattedFps => fps > 0 ? '${fps.toStringAsFixed(1)} fps' : '—';
  String get formattedSpeed => speed > 0 ? '${speed.toStringAsFixed(2)}x' : '—';
  String get formattedEta =>
      etaSeconds == null ? '—' : FormatParsers.formatDuration(etaSeconds!);
  String get formattedBitrate => FormatParsers.formatBitrate(bitrateBitsPerSec);
}
