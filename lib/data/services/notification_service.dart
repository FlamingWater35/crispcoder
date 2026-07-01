import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handles local notifications for encode progress and completion alerts.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _progressChannelId = 'crispcoder_encode_progress';
  static const _progressChannelName = 'Encode Progress';
  static const _operationsChannelId = 'crispcoder_operations';
  static const _operationsChannelName = 'Operations';
  static const _progressNotificationId = 777;

  /// Initializes the notification plugin and creates required channels.
  Future<void> init() async {
    if (_initialized) return;
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/launcher_icon',
      );
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(settings);

      // Create channels for Android 8.0+
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _progressChannelId,
              _progressChannelName,
              description: 'Shows progress bar while videos are transcoding.',
              importance: Importance.low,
            ),
          );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _operationsChannelId,
              _operationsChannelName,
              description: 'Alerts for completed or failed encodes.',
              importance: Importance.high,
            ),
          );

      _initialized = true;
    } catch (_) {
      // Best effort initialization
    }
  }

  /// Displays or updates a progress notification with a progress bar.
  Future<void> showProgress({
    required int percent,
    required String content,
  }) async {
    if (!_initialized) return;
    try {
      final androidDetails = AndroidNotificationDetails(
        _progressChannelId,
        _progressChannelName,
        channelDescription: 'Shows progress bar while videos are transcoding.',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: true,
        maxProgress: 100,
        progress: percent.clamp(0, 100),
        onlyAlertOnce: true,
        ongoing: true,
        icon: '@mipmap/launcher_icon',
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(
        _progressNotificationId,
        'Transcoding Video',
        content,
        details,
      );
    } catch (_) {}
  }

  /// Cancels the ongoing progress notification.
  Future<void> cancelProgress() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(_progressNotificationId);
    } catch (_) {}
  }

  /// Shows a completion alert notification.
  Future<void> showCompleted(String title) async {
    if (!_initialized) return;
    try {
      final androidDetails = AndroidNotificationDetails(
        _operationsChannelId,
        _operationsChannelName,
        channelDescription: 'Alerts for completed or failed encodes.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        title.hashCode,
        'Encode Completed',
        '$title has finished transcoding successfully.',
        details,
      );
    } catch (_) {}
  }

  /// Shows a failure alert notification.
  Future<void> showFailed(String title, String error) async {
    if (!_initialized) return;
    try {
      final androidDetails = AndroidNotificationDetails(
        _operationsChannelId,
        _operationsChannelName,
        channelDescription: 'Alerts for completed or failed encodes.',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/launcher_icon',
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        title.hashCode,
        'Encode Failed',
        '$title failed: $error',
        details,
      );
    } catch (_) {}
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);
