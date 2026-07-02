/// Lightweight representation of a subtitle stream.
class SubtitleTrack {
  /// Absolute stream index as reported by FFprobe (e.g., 0, 1, 2).
  /// Used only for display so the label matches FFprobe output.
  final int index;

  /// Zero-based index among subtitle streams only (0, 1, 2, …).
  /// Passed to FFmpeg's `subtitles` filter `si` parameter, which
  /// counts only streams of type AVMEDIA_TYPE_SUBTITLE.
  final int subtitleStreamIndex;

  final String? language;
  final String? codec;

  const SubtitleTrack({
    required this.index,
    required this.subtitleStreamIndex,
    this.language,
    this.codec,
  });

  /// Human-readable label using the absolute index for familiarity.
  String get label {
    final lang = language ?? 'Unknown';
    final cod = codec ?? 'sub';
    return 'Track $index ($lang, $cod)';
  }
}

/// Lightweight probed metadata for a source media file.
class MediaInfo {
  final String path;
  final Duration? duration;
  final int? width;
  final int? height;
  final String? videoCodec;
  final String? audioCodec;
  final double? frameRate;
  final int? bitrateBitsPerSec;
  final int? audioBitrateBitsPerSec;
  final String? container;
  final List<SubtitleTrack> subtitleTracks;

  const MediaInfo({
    required this.path,
    this.duration,
    this.width,
    this.height,
    this.videoCodec,
    this.audioCodec,
    this.frameRate,
    this.bitrateBitsPerSec,
    this.audioBitrateBitsPerSec,
    this.container,
    this.subtitleTracks = const [],
  });

  /// Detects the standard resolution label (e.g., 1080, 720) by finding
  /// the smallest standard 16:9 box that contains the video. Handles both
  /// landscape and portrait orientations by checking both box orientations.
  /// A 1920x800 video is detected as 1080p because it fits in a 1920x1080 box.
  int? get detectedResolution {
    final w = width;
    final h = height;
    if (w == null || h == null) return null;

    // Standard 16:9 boxes, smallest to largest: (height, width)
    const boxes = [
      (240, 426),
      (360, 640),
      (480, 854),
      (576, 1024),
      (720, 1280),
      (1080, 1920),
      (1440, 2560),
      (2160, 3840),
    ];

    for (final (boxH, boxW) in boxes) {
      // Check landscape box (boxW x boxH)
      if (w <= boxW && h <= boxH) return boxH;
      // Check portrait box (boxH x boxW)
      if (w <= boxH && h <= boxW) return boxH;
    }
    // Larger than 2160p
    return 2160;
  }

  /// Returns raw dimension string like "1920x1080" or "Unknown".
  String get dimensionsLabel {
    if (width == null || height == null) {
      return 'Unknown';
    }
    return '${width}x$height';
  }

  /// Returns resolution badge + dimensions, e.g. "1080p (1920x1080)".
  /// Falls back to just dimensions if detection fails.
  String get resolutionLabel {
    final dims = dimensionsLabel;
    final res = detectedResolution;
    if (res != null && dims != 'Unknown') {
      return '${res}p ($dims)';
    }
    return dims;
  }

  /// Computes output dimensions when scaling [sourceWidth]×[sourceHeight]
  /// to fit within a standard 16:9 box for [targetResolution].
  /// Uses force_original_aspect_ratio=decrease logic: the video is never
  /// upscaled, only downscaled to fit. Handles portrait by swapping the box.
  static (int, int)? computeOutputDimensions({
    required int targetResolution,
    required int sourceWidth,
    required int sourceHeight,
  }) {
    const resToWidth = {
      2160: 3840,
      1440: 2560,
      1080: 1920,
      720: 1280,
      576: 1024,
      480: 854,
      360: 640,
      240: 426,
    };
    final boxW = resToWidth[targetResolution];
    if (boxW == null) return null;
    final boxH = targetResolution;

    // Swap box dimensions for portrait sources so the box matches orientation
    final isLandscape = sourceWidth >= sourceHeight;
    final effectiveBoxW = isLandscape ? boxW : boxH;
    final effectiveBoxH = isLandscape ? boxH : boxW;

    final srcAR = sourceWidth / sourceHeight;
    final boxAR = effectiveBoxW / effectiveBoxH;

    int outW, outH;
    if (srcAR > boxAR) {
      // Source wider than box → fit to width
      outW = effectiveBoxW;
      outH = (effectiveBoxW / srcAR).round();
    } else {
      // Source narrower or equal → fit to height
      outH = effectiveBoxH;
      outW = (effectiveBoxH * srcAR).round();
    }
    // Ensure even dimensions (required by most encoders)
    outW = outW ~/ 2 * 2;
    outH = outH ~/ 2 * 2;
    return (outW, outH);
  }

  String get durationLabel {
    if (duration == null) {
      return '—';
    }
    final s = duration!.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}'
        : '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
