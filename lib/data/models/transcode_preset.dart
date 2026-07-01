import 'package:hive_ce/hive_ce.dart';

/// Video codec selection. `copy` bypasses re-encoding (passthrough).
enum VideoCodec { h264, hevc, av1, copy }

/// Audio codec selection.
enum AudioCodec { aac, opus, mp3, ac3, copy }

/// Output container format.
enum ContainerFormat { mp4, mkv, webm }

/// Encoder preference: hardware (MediaCodec), software (libx*), or auto.
enum EncoderPreference { hardware, software, auto }

/// Defines the media type to extract/transcode.
enum OutputType { video, audio, subtitle }

/// Handbrake-style preset describing the full encode pipeline.
class TranscodePreset {
  final String id;
  final String name;
  final String category;
  final OutputType outputType;
  final VideoCodec videoCodec;
  final int? crf;
  final int? videoBitrate;
  final int? resolution; // Height in pixels (e.g., 1080, 720)
  final String? aspectRatio; // e.g., "16:9", "4:3", "1:1"
  final int? framerate;
  final AudioCodec audioCodec;
  final int audioBitrate;
  final ContainerFormat container;
  final EncoderPreference encoderPref;
  final String? filterChain;
  final bool faststart;
  final bool twoPass;
  final bool isBuiltIn;

  // Editing Fields
  final bool removeAudio;
  final int? burnSubtitleIndex;
  final String? startTime;
  final String? endTime;

  // Visual Crop Fields (Fractions from 0.0 to 1.0)
  final double? cropLeft;
  final double? cropTop;
  final double? cropWidth;
  final double? cropHeight;

  const TranscodePreset({
    required this.id,
    required this.name,
    required this.category,
    this.outputType = OutputType.video,
    required this.videoCodec,
    this.crf,
    this.videoBitrate,
    this.resolution,
    this.aspectRatio,
    this.framerate,
    required this.audioCodec,
    required this.audioBitrate,
    required this.container,
    this.encoderPref = EncoderPreference.auto,
    this.filterChain,
    this.faststart = true,
    this.twoPass = false,
    this.isBuiltIn = false,
    this.removeAudio = false,
    this.burnSubtitleIndex,
    this.startTime,
    this.endTime,
    this.cropLeft,
    this.cropTop,
    this.cropWidth,
    this.cropHeight,
  });

  TranscodePreset copyWith({
    String? id,
    String? name,
    String? category,
    OutputType? outputType,
    VideoCodec? videoCodec,
    int? crf,
    int? videoBitrate,
    int? resolution,
    String? aspectRatio,
    int? framerate,
    AudioCodec? audioCodec,
    int? audioBitrate,
    ContainerFormat? container,
    EncoderPreference? encoderPref,
    String? filterChain,
    bool? faststart,
    bool? twoPass,
    bool? isBuiltIn,
    bool? removeAudio,
    int? burnSubtitleIndex,
    String? startTime,
    String? endTime,
    double? cropLeft,
    double? cropTop,
    double? cropWidth,
    double? cropHeight,
  }) {
    return TranscodePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      outputType: outputType ?? this.outputType,
      videoCodec: videoCodec ?? this.videoCodec,
      crf: crf ?? this.crf,
      videoBitrate: videoBitrate ?? this.videoBitrate,
      resolution: resolution ?? this.resolution,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      framerate: framerate ?? this.framerate,
      audioCodec: audioCodec ?? this.audioCodec,
      audioBitrate: audioBitrate ?? this.audioBitrate,
      container: container ?? this.container,
      encoderPref: encoderPref ?? this.encoderPref,
      filterChain: filterChain ?? this.filterChain,
      faststart: faststart ?? this.faststart,
      twoPass: twoPass ?? this.twoPass,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      removeAudio: removeAudio ?? this.removeAudio,
      burnSubtitleIndex: burnSubtitleIndex ?? this.burnSubtitleIndex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      cropLeft: cropLeft ?? this.cropLeft,
      cropTop: cropTop ?? this.cropTop,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
    );
  }

  /// Determines the output file extension based on the selected output type.
  String get fileExtension {
    if (outputType == OutputType.audio) {
      return switch (audioCodec) {
        AudioCodec.aac => 'm4a',
        AudioCodec.opus => 'opus',
        AudioCodec.mp3 => 'mp3',
        AudioCodec.ac3 => 'ac3',
        AudioCodec.copy => 'm4a', // Fallback for copied audio
      };
    }
    if (outputType == OutputType.subtitle) return 'srt';
    return switch (container) {
      ContainerFormat.mp4 => 'mp4',
      ContainerFormat.mkv => 'mkv',
      ContainerFormat.webm => 'webm',
    };
  }
}

/// Manual Hive adapter. Handles schema migrations gracefully.
class TranscodePresetAdapter extends TypeAdapter<TranscodePreset> {
  @override
  final int typeId = 1;

  @override
  TranscodePreset read(BinaryReader r) {
    return TranscodePreset(
      id: r.readString(),
      name: r.readString(),
      category: r.readString(),
      // V4 Migration: OutputType added
      outputType: r.readByte() == 1
          ? OutputType.values[r.readByte()]
          : OutputType.video,
      videoCodec: VideoCodec.values[r.readByte()],
      crf: r.readByte() == 1 ? r.readInt() : null,
      videoBitrate: r.readByte() == 1 ? r.readInt() : null,
      resolution: r.readByte() == 1 ? r.readInt() : null,
      aspectRatio: r.readByte() == 1 ? r.readString() : null,
      framerate: r.readByte() == 1 ? r.readInt() : null,
      audioCodec: AudioCodec.values[r.readByte()],
      audioBitrate: r.readInt(),
      container: ContainerFormat.values[r.readByte()],
      encoderPref: EncoderPreference.values[r.readByte()],
      filterChain: r.readByte() == 1 ? r.readString() : null,
      faststart: r.readBool(),
      twoPass: r.readBool(),
      isBuiltIn: r.readBool(),
      removeAudio: r.readBool(),
      burnSubtitleIndex: r.readByte() == 1 ? r.readInt() : null,
      startTime: r.readByte() == 1 ? r.readString() : null,
      endTime: r.readByte() == 1 ? r.readString() : null,
      cropLeft: r.readByte() == 1 ? r.readDouble() : null,
      cropTop: r.readByte() == 1 ? r.readDouble() : null,
      cropWidth: r.readByte() == 1 ? r.readDouble() : null,
      cropHeight: r.readByte() == 1 ? r.readDouble() : null,
    );
  }

  @override
  void write(BinaryWriter w, TranscodePreset p) {
    w.writeString(p.id);
    w.writeString(p.name);
    w.writeString(p.category);
    w.writeByte(1); // Flag: outputType is present
    w.writeByte(p.outputType.index);
    w.writeByte(p.videoCodec.index);
    _writeNullableInt(w, p.crf);
    _writeNullableInt(w, p.videoBitrate);
    _writeNullableInt(w, p.resolution);
    _writeNullableString(w, p.aspectRatio);
    _writeNullableInt(w, p.framerate);
    w.writeByte(p.audioCodec.index);
    w.writeInt(p.audioBitrate);
    w.writeByte(p.container.index);
    w.writeByte(p.encoderPref.index);
    _writeNullableString(w, p.filterChain);
    w.writeBool(p.faststart);
    w.writeBool(p.twoPass);
    w.writeBool(p.isBuiltIn);
    w.writeBool(p.removeAudio);
    _writeNullableInt(w, p.burnSubtitleIndex);
    _writeNullableString(w, p.startTime);
    _writeNullableString(w, p.endTime);
    _writeNullableDouble(w, p.cropLeft);
    _writeNullableDouble(w, p.cropTop);
    _writeNullableDouble(w, p.cropWidth);
    _writeNullableDouble(w, p.cropHeight);
  }

  static void _writeNullableInt(BinaryWriter w, int? v) {
    if (v == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(v);
    }
  }

  static void _writeNullableString(BinaryWriter w, String? v) {
    if (v == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(v);
    }
  }

  static void _writeNullableDouble(BinaryWriter w, double? v) {
    if (v == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeDouble(v);
    }
  }
}
