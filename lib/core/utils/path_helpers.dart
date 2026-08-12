import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
      if (entity is Directory &&
          entity.path.length < protectedPath.length &&
          protectedPath.startsWith(entity.path)) {
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
        } else if (entity is Directory &&
            p.basename(entity.path).toLowerCase() == 'file_picker') {
          try {
            await entity.delete(recursive: true);
          } catch (_) {
            // Ignore locked/in-use files
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
}
