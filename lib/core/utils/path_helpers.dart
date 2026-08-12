import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/models/transcode_preset.dart';

/// Helpers for resolving temp/cache dirs and deriving safe output paths.
class PathHelpers {
  PathHelpers._();

  /// Returns the app cache dir, creating it if missing.
  /// Used for FFmpeg two-pass log files and intermediate proxies.
  static Future<Directory> ensureCacheDir(String sub) async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(p.join(base.path, sub));
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (e) {
      // Fall back to in-app temp dir if external cache is unavailable
      final base = await getTemporaryDirectory();
      return Directory(p.join(base.path, sub))..createSync(recursive: true);
    }
  }

  /// Clears the app's temporary cache directory to prevent storage bloat
  /// from leftover FFmpeg logs, intermediate video files, and two-pass
  /// encoding assets. Safe to call on startup; OS will recreate files as needed.
  ///
  /// [protect] lists absolute file paths that must survive the cleanup (e.g.
  /// completed encode outputs that are still referenced by the queue/history
  /// and sharable after an app relaunch). Protected entries are checked
  /// against the path being deleted (which may be a directory containing the
  /// file, so the match is prefix-based on the protected file's parent).
  static Future<void> clearAppCache({Set<String> protect = const {}}) async {
    try {
      final base = await getTemporaryDirectory();
      if (base.existsSync()) {
        // Delete contents recursively, but keep the base directory itself.
        // A protected file can live inside a subdirectory (e.g. file_picker
        // cache), so skip any directory that contains one.
        for (final entity in base.listSync()) {
          if (_containsProtected(entity, protect)) continue;
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // Ignore errors for individual files (e.g., locked files)
          }
        }
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  /// True if [entity] is a protected file, or a directory that contains one
  /// (directly or nested).
  static bool _containsProtected(
    FileSystemEntity entity,
    Set<String> protect,
  ) {
    for (final protectedPath in protect) {
      if (entity.path == protectedPath) return true;
      // A directory "contains" the protected file only when it is an actual
      // ancestor. Requiring a path separator prevents `/a/cache/file` from
      // protecting the sibling `/a/cache/file2`.
      if (entity is Directory &&
          entity.path.length < protectedPath.length &&
          protectedPath.startsWith(
            '${entity.path}${Platform.pathSeparator}',
          )) {
        return true;
      }
    }
    return false;
  }

  /// Deletes processed (encoded) output files from the app data folder.
  ///
  /// When no custom output directory is configured, encode outputs are
  /// written into the app's cache directory (same base as [clearAppCache],
  /// e.g. the `file_picker` copy folder and any leftover FFmpeg artifacts).
  /// This removes those processed files while keeping transient picker cache
  /// entries that are still referenced by the queue/history (via [protect]).
  ///
  /// Best-effort: individual failures (locked files) are ignored.
  static Future<void> deleteProcessedFilesFromAppData({
    Set<String> protect = const {},
  }) async {
    try {
      final base = await getTemporaryDirectory();
      if (!base.existsSync()) return;
      for (final entity in base.listSync()) {
        if (_containsProtected(entity, protect)) continue;
        // Only delete regular files and the file_picker cache subfolder,
        // where picker copies of processed sources land. Directories such
        // as `passes` (FFmpeg two-pass logs) are not "processed files".
        if (entity is File) {
          try {
            await entity.delete();
          } catch (_) {
            // Ignore locked/in-use files
          }
        } else if (entity is Directory) {
          final name = p.basename(entity.path).toLowerCase();
          // file_picker cache (picker copies of processed sources) and the
          // native picker's crispcoder_picked cache (copies of picked videos
          // under their display names) are both transient. Directories such
          // as `passes` (FFmpeg two-pass logs) are not "processed files".
          if (name == 'file_picker' || name == 'crispcoder_picked') {
            try {
              await entity.delete(recursive: true);
            } catch (_) {
              // Ignore locked/in-use files
            }
          }
        }
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  /// Builds a non-colliding output filename by appending (1), (2), etc.
  static String uniqueOutputPath({
    required String directory,
    required String baseName,
    required String extension,
  }) {
    var attempt = 0;
    var path = p.join(directory, '$baseName.$extension');
    while (File(path).existsSync()) {
      attempt++;
      path = p.join(directory, '$baseName ($attempt).$extension');
    }
    return path;
  }

  /// Sanitizes a user-supplied filename to avoid invalid characters.
  static String sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// True when [value] is a bare number (e.g. "29"), which is the pattern
  /// Android's file_picker cache uses for copied files. Such names carry no
  /// user-meaningful information, so they must not be used as output names.
  static bool isBareNumber(String value) {
    return RegExp(r'^\d+$').hasMatch(value.trim());
  }

  /// Derives a user-facing source name from the picker-reported name and the
  /// raw path.
  ///
  /// On Android, `file_picker` may copy the selected file into an app-private
  /// cache directory and report both a numeric path (`.../file_picker/29`)
  /// and a numeric `PlatformFile.name` ("29"). [pickerName] (the picker's
  /// display name) wins when it looks real; otherwise the path basename is
  /// used. If both are bare numbers or empty, a readable timestamped name is
  /// generated so the queue/history/notifications never show "29".
  static String deriveDisplayName({
    required String? pickerName,
    required String path,
    String? metadataTitle,
  }) {
    // A meaningful path basename is better than a bare-number picker name
    // (the Android photo picker can hand back a numeric id as the "name").
    // Evaluate both and prefer whichever carries information.
    final picker = pickerName?.trim() ?? '';
    final pathBase = p.basename(path);
    final String rawName;
    if (picker.isNotEmpty && !isBareNumber(p.basenameWithoutExtension(picker))) {
      rawName = picker;
    } else if (pathBase.isNotEmpty && !isBareNumber(p.basenameWithoutExtension(pathBase))) {
      rawName = pathBase;
    } else if (picker.isNotEmpty) {
      rawName = picker;
    } else {
      rawName = pathBase;
    }
    final base = p.basenameWithoutExtension(rawName);

    if (!isBareNumber(base) && base.trim().isNotEmpty) {
      return rawName;
    }

    if (metadataTitle != null && metadataTitle.trim().isNotEmpty) {
      return metadataTitle.trim();
    }

    final now = DateTime.now();
    final stamp = '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';

    // No fake extension: the picker gave us nothing real, so inventing a
    // ".mp4" here would mislabel audio/subtitle extractions (their output
    // name is derived from this value and gets its own real extension).
    return 'video_$stamp';
  }

  /// Returns a non-empty, non-numeric base name (without extension) safe for
  /// use in output filenames. Falls back to a timestamped name when the
  /// sanitized result is empty or a bare number (e.g. "29"), so output files
  /// are never `29_encoded.mp4`.
  static String safeOutputBaseName(String sourceFileName) {
    final safe = sanitizeFileName(
      p.basenameWithoutExtension(sourceFileName),
    );
    if (safe.isNotEmpty && !isBareNumber(safe)) {
      return safe;
    }
    return 'video_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Default output directory when the user has not configured a custom one.
  ///
  /// Video outputs go into the app documents folder; audio/subtitle outputs
  /// into a dedicated subfolder. Neither ever defaults to the gallery or the
  /// volatile file_picker cache (which may be cleared at any time). The
  /// caller must create the directory before use.
  static Future<String> defaultOutputDirectory(OutputType outputType) async {
    final docs = await getApplicationDocumentsDirectory();
    final sub = switch (outputType) {
      OutputType.video => 'Videos',
      OutputType.audio => 'Audio',
      OutputType.subtitle => 'Subtitles',
    };
    return p.join(docs.path, 'CrispCoder', sub);
  }

  /// Resolves the directory an encode output is written to.
  ///
  /// A user-configured [customDirectory] wins for **all** output types —
  /// video, audio, and subtitle outputs all land in the chosen folder. When
  /// no custom directory is set, video outputs stay next to the source (and
  /// are inserted into the device gallery on completion), while audio and
  /// subtitle outputs go to a dedicated app-documents subfolder so they are
  /// never written into the volatile file_picker cache or treated as gallery
  /// videos. The caller must create the returned directory before use.
  static Future<String> resolveOutputDirectory({
    required OutputType outputType,
    required String? customDirectory,
    required String sourcePath,
  }) async {
    if (customDirectory != null && customDirectory.trim().isNotEmpty) {
      return customDirectory.trim();
    }
    if (outputType == OutputType.video) {
      return p.dirname(sourcePath);
    }
    return defaultOutputDirectory(outputType);
  }
}
