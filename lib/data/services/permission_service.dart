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
}

final permissionServiceProvider = Provider<PermissionService>(
  (ref) => PermissionService(),
);
