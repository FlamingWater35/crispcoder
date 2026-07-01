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
  static Future<void> clearAppCache() async {
    try {
      final base = await getTemporaryDirectory();
      if (base.existsSync()) {
        // Delete contents recursively, but keep the base directory itself
        for (final entity in base.listSync()) {
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
