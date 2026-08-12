import 'package:hive_ce/hive_ce.dart';

import 'transcode_preset.dart';

/// Lifecycle states for an encode task. Persisted for crash recovery.
enum EncodeStatus { pending, running, paused, completed, failed, cancelled }

/// Represents a single transcode job in the queue.
class EncodeTask {
  final String id;
  final String sourcePath;
  final String? sourceName;
  final String outputPath;
  final TranscodePreset preset; // Embedded preset for custom configurations
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final EncodeStatus status;
  final String? errorMessage;
  final double totalDurationSeconds;

  /// Source video framerate in fps (e.g. 23.976, 29.97) captured at enqueue
  /// time from the probe. Used when no explicit output framerate is set: the
  /// hardware encoder path and the GOP calculation fall back to this instead
  /// of assuming 30 fps.
  final double? sourceFrameRate;

  /// True when the finished output was successfully inserted into the device
  /// gallery (MediaStore). Only video outputs are ever saved to the gallery;
  /// audio/subtitle outputs always remain files. Used by the queue UI to
  /// display "Saved to Device Gallery" instead of guessing from the path.
  final bool savedToGallery;

  /// MediaStore URI (e.g. `content://media/external/audio/media/123`) of the
  /// published copy in DCIM/Videolation, when `saveToDCIM` succeeded. When
  /// set, the private `outputPath` copy is deleted on publish and Share reads
  /// from this URI instead. Null when the output was never published (custom
  /// output directory, publish failure, or an older persisted record).
  final String? publishedUri;

  EncodeTask({
    required this.id,
    required this.sourcePath,
    this.sourceName,
    required this.outputPath,
    required this.preset,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.status = EncodeStatus.pending,
    this.errorMessage,
    this.totalDurationSeconds = 0,
    this.sourceFrameRate,
    this.savedToGallery = false,
    this.publishedUri,
  });

  /// Canonical user-facing title for this task.
  ///
  /// Video encodes are identified by their source; extractions (audio /
  /// subtitle) by their artifact, so a running audio job never shows as
  /// "Song.mp4". Used consistently by the queue tiles, the active-encode
  /// spotlight, the foreground service and the notifications.
  String get displayTitle => preset.outputType == OutputType.video
      ? (sourceName ?? outputPath.split('/').last)
      : outputPath.split('/').last;

  EncodeTask copyWith({
    String? id,
    String? sourcePath,
    String? sourceName,
    String? outputPath,
    TranscodePreset? preset,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? finishedAt,
    EncodeStatus? status,
    String? errorMessage,
    double? totalDurationSeconds,
    double? sourceFrameRate,
    bool? savedToGallery,
    String? publishedUri,
  }) {
    return EncodeTask(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      sourceName: sourceName ?? this.sourceName,
      outputPath: outputPath ?? this.outputPath,
      preset: preset ?? this.preset,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      sourceFrameRate: sourceFrameRate ?? this.sourceFrameRate,
      savedToGallery: savedToGallery ?? this.savedToGallery,
      publishedUri: publishedUri ?? this.publishedUri,
    );
  }
}

class EncodeTaskAdapter extends TypeAdapter<EncodeTask> {
  @override
  final int typeId = 2;

  @override
  EncodeTask read(BinaryReader r) {
    return EncodeTask(
      id: r.readString(),
      sourcePath: r.readString(),
      sourceName: r.readByte() == 1 ? r.readString() : null,
      outputPath: r.readString(),
      preset: r.read() as TranscodePreset,
      createdAt: DateTime.fromMillisecondsSinceEpoch(r.readInt()),
      startedAt: r.readByte() == 1
          ? DateTime.fromMillisecondsSinceEpoch(r.readInt())
          : null,
      finishedAt: r.readByte() == 1
          ? DateTime.fromMillisecondsSinceEpoch(r.readInt())
          : null,
      status: EncodeStatus.values[r.readByte()],
      errorMessage: r.readByte() == 1 ? r.readString() : null,
      totalDurationSeconds: r.readDouble(),
      // Optional field appended at the end; absent in records written by
      // older app versions, so only read it when bytes remain.
      sourceFrameRate: r.availableBytes > 0 && r.readByte() == 1
          ? r.readDouble()
          : null,
      // Optional field appended at the very end; absent in records written
      // by older app versions, so only read it when bytes remain.
      savedToGallery: r.availableBytes > 0 && r.readByte() == 1,
      // Optional field appended after savedToGallery; absent in records
      // written by older app versions, so only read it when bytes remain.
      publishedUri: r.availableBytes > 0 && r.readByte() == 1
          ? r.readString()
          : null,
    );
  }

  @override
  void write(BinaryWriter w, EncodeTask t) {
    w.writeString(t.id);
    w.writeString(t.sourcePath);
    if (t.sourceName == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(t.sourceName!);
    }
    w.writeString(t.outputPath);
    w.write(t.preset); // Hive resolves the adapter automatically
    w.writeInt(t.createdAt.millisecondsSinceEpoch);
    if (t.startedAt == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(t.startedAt!.millisecondsSinceEpoch);
    }
    if (t.finishedAt == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeInt(t.finishedAt!.millisecondsSinceEpoch);
    }
    w.writeByte(t.status.index);
    if (t.errorMessage == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(t.errorMessage!);
    }
    w.writeDouble(t.totalDurationSeconds);
    if (t.sourceFrameRate == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeDouble(t.sourceFrameRate!);
    }
    w.writeByte(t.savedToGallery ? 1 : 0);
    if (t.publishedUri == null) {
      w.writeByte(0);
    } else {
      w.writeByte(1);
      w.writeString(t.publishedUri!);
    }
  }
}

class EncodeStatusAdapter extends TypeAdapter<EncodeStatus> {
  @override
  final int typeId = 3;

  @override
  EncodeStatus read(BinaryReader r) => EncodeStatus.values[r.readByte()];

  @override
  void write(BinaryWriter w, EncodeStatus obj) => w.writeByte(obj.index);
}
