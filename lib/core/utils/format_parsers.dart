import 'package:ffmpeg_kit_flutter_new/statistics.dart';

/// Parses raw FFmpeg statistics + log lines into typed progress values.
class FormatParsers {
  FormatParsers._();

  /// Converts a Statistics object into a 0..100 percent given total seconds.
  static double percent(Statistics stats, double totalDurationSeconds) {
    if (totalDurationSeconds <= 0) {
      return 0;
    }
    final ms = stats.getTime().toDouble();
    final pct = (ms / 1000.0) / totalDurationSeconds * 100.0;
    return pct.clamp(0.0, 100.0);
  }

  /// Estimates remaining seconds based on speed multiplier (1.0x = realtime).
  static int? etaSeconds({
    required double currentSeconds,
    required double totalSeconds,
    required double speed,
  }) {
    if (speed <= 0 || currentSeconds >= totalSeconds) {
      return 0;
    }
    final remainingMedia = (totalSeconds - currentSeconds).clamp(
      0,
      double.infinity,
    );
    return (remainingMedia / speed).round();
  }

  /// Parses a framerate string like "30/1" or "30000/1001" into a double.
  static double? parseFramerate(String? value) {
    if (value == null || value.isEmpty) return null;
    if (value.contains('/')) {
      final parts = value.split('/');
      if (parts.length == 2) {
        final num = double.tryParse(parts[0]);
        final den = double.tryParse(parts[1]);
        if (num != null && den != null && den != 0) {
          return num / den;
        }
      }
      return null;
    }
    return double.tryParse(value);
  }

  /// Formats a bitrate (bits/sec) into a human readable kbps/Mbps string.
  static String formatBitrate(double? bitsPerSecond) {
    if (bitsPerSecond == null || bitsPerSecond <= 0) {
      return '—';
    }
    if (bitsPerSecond >= 1e6) {
      return '${(bitsPerSecond / 1e6).toStringAsFixed(2)} Mbps';
    }
    return '${(bitsPerSecond / 1e3).toStringAsFixed(0)} kbps';
  }

  /// Formats seconds as h:mm:ss for ETA display.
  static String formatDuration(int totalSeconds) {
    if (totalSeconds < 0) {
      totalSeconds = 0;
    }
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
