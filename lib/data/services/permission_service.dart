import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/errors/app_exceptions.dart';

/// Centralizes runtime permission requests: notifications, battery, media.
class PermissionService {
  Future<void> requireNotifications() async {
    final status = await Permission.notification.request();
    if (!status.isGranted) {
      throw MissingPermissionException('notifications');
    }
  }

  /// Requests battery exemption. Returns true if already granted or successfully requested.
  Future<bool> requireBatteryExemption() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;

      final requested = await Permission.ignoreBatteryOptimizations.request();
      return requested.isGranted;
    } catch (_) {
      // Some OEMs don't honor this permission; safe to ignore
      return false;
    }
  }

  Future<void> requireMediaRead() async {
    final video = await Permission.videos.request();
    if (!video.isGranted) {
      // Fallback to legacy storage on Android <= 12
      final storage = await Permission.storage.request();
      if (!storage.isGranted) {
        throw MissingPermissionException('media read');
      }
    }
  }

  /// Requests audio read access. Needed on API 33+ for MediaStore audio
  /// inserts (publishing audio extractions to DCIM/Videolation), which some
  /// OEMs reject without READ_MEDIA_AUDIO. Android-only: on iOS this maps to
  /// microphone access, which would crash without an NSMicrophoneUsageDescription
  /// — so it is a no-op there. Best-effort: returns whether audio access was
  /// granted (a denial only means the audio output stays in app storage).
  Future<bool> requireAudioRead() async {
    if (Platform.isIOS) return false;
    final audio = await Permission.audio.request();
    return audio.isGranted;
  }

  /// Requests the permissions the app needs on first launch: media read
  /// access (for picking sources) and notification permission (for encode
  /// progress in the background). Best-effort: each request is isolated so a
  /// denial of one never blocks the other, and the app remains fully usable
  /// because both can be granted later from Settings or when an encode
  /// actually starts.
  Future<void> requestBootPermissions() async {
    try {
      await requireNotifications();
    } catch (_) {
      // Notifications are optional — progress just won't show if denied.
    }
    try {
      await requireMediaRead();
    } catch (_) {
      // Media read is optional at boot — the file picker requests it again
      // when the user actually selects a source.
    }
  }
}

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);
