import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transcode_preset.dart';

/// Post-encode output handlers: save to MediaStore via `gal` or share.
class GalleryService {
  /// Method channel to the Android MainActivity, which publishes finished
  /// files into `DCIM/Videolation` via MediaStore (the only way to target
  /// that folder under scoped storage; `gal` writes albums to Pictures/).
  static const _channel = MethodChannel('crispcoder/media_store');

  /// Picks a source video through the native Android SAF picker
  /// (`ACTION_OPEN_DOCUMENT`) and returns the display name plus a filesystem
  /// path FFmpeg can read.
  ///
  /// The native side recovers the original name via
  /// `OpenableColumns.DISPLAY_NAME` and, when the provider exposes no direct
  /// path, copies the file into the app cache **using the display name** —
  /// which permanently fixes the lost-original-name problem caused by
  /// `file_picker`'s numeric cache names (e.g. "29").
  ///
  /// Returns `null` when the user cancels. Throws on error so callers can
  /// fall back to `file_picker` when the native method is unavailable (e.g.
  /// a stale build or non-Android platforms).
  Future<({String name, String path})?> pickVideo() async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'pickVideo',
    );
    if (result == null) return null;
    final name = result['name']?.toString();
    final path = result['path']?.toString();
    if (name == null || path == null || path.isEmpty) {
      throw PlatformException(code: 'pickVideo', message: 'Invalid picker result');
    }
    return (name: name, path: path);
  }

  /// Publishes [path] into `DCIM/Videolation` on Android via the platform
  /// channel. [outputType] selects the MediaStore collection (video/audio/
  /// subtitle).
  ///
  /// Returns the MediaStore `content://` URI of the published copy on
  /// success, or `null` on failure (the native side logs the real exception
  /// so the Logs screen can surface it). The caller can then delete the
  /// private [path] copy and persist the URI for sharing.
  ///
  /// When the native channel is unavailable (desktop tests, stale build),
  /// returns `null` — never a fake URI, because a non-null return is
  /// interpreted by the caller as "published to MediaStore" and would delete
  /// the private copy. The output stays in [path] and remains shareable.
  Future<String?> saveToDCIM({
    required String path,
    required OutputType outputType,
    String? displayName,
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>('saveToDCIM', {
        'path': path,
        'displayName': displayName,
        'outputType': outputType.name,
      });
      // The channel returns the URI string on success, null on failure.
      return uri;
    } on MissingPluginException {
      return null;
    } catch (e) {
      // Log the underlying exception so the failure is diagnosable instead
      // of being silently swallowed (the original bug hid it at every layer).
      debugPrint('saveToDCIM failed for $path: $e');
      return null;
    }
  }

  /// Shares the output file via the system share sheet.
  ///
  /// Returns `true` when the share sheet was invoked without error, `false`
  /// when sharing failed (e.g. the MediaStore URI no longer resolves). The
  /// caller can then surface a message instead of silently doing nothing.
  Future<bool> share(String path, {String? subject}) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          subject: subject ?? 'CrispCoder output',
        ),
      );
      return true;
    } catch (_) {
      // Share sheet dismissed or unavailable — treat as failure so the
      // caller can inform the user.
      return false;
    }
  }
}

final galleryServiceProvider = Provider<GalleryService>(
  (ref) => GalleryService(),
);
