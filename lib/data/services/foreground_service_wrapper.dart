import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';

/// Wraps flutter_foreground_task lifecycle so UI code stays declarative.
/// Configures a mediaProcessing service with a customizable progress text.
class ForegroundServiceWrapper {
  ForegroundServiceWrapper._();
  static final ForegroundServiceWrapper instance = ForegroundServiceWrapper._();

  bool _initialized = false;

  /// Must be called during app bootstrap, before any startService call.
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    // FlutterForegroundTask.init is synchronous and returns void
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: AppConstants.fgNotificationChannelId,
        channelName: AppConstants.fgNotificationChannelName,
        channelDescription: 'Shows progress while videos are transcoding.',
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _initialized = true;
  }

  /// Starts the foreground service. The FGS notification is the Android
  /// "app is running" requirement — it stays minimal because the rich
  /// progress notification (id 777, with the Cancel action) carries the
  /// actual progress details.
  Future<void> start({required String title, required String text}) async {
    try {
      await FlutterForegroundTask.startService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (_) {
      // Foreground service may be denied; encode will still continue in-process
    }
  }

  /// Updates only the notification text without restarting the service.
  /// Currently unused: the FGS notification stays minimal because the rich
  /// id-777 progress notification carries the details. Kept for callers that
  /// want to customize the FGS line (e.g. the active task name).
  Future<void> updateText(String text) async {
    try {
      FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {
      // ignore — best-effort UI update
    }
  }

  Future<void> stop() async {
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {
      // ignore
    }
  }
}

final foregroundServiceProvider = Provider<ForegroundServiceWrapper>(
  (ref) => ForegroundServiceWrapper.instance,
);
