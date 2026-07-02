import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Handles local notifications for encode progress and completion alerts.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Callback triggered when the "Cancel" action button is pressed.
  static void Function()? onCancelRequested;

  static const _progressChannelId = 'crispcoder_encode_progress';
  static const _progressChannelName = 'Encode Progress';
  static const _operationsChannelId = 'crispcoder_operations';
  static const _operationsChannelName = 'Operations';
  static const _progressNotificationId = 777;

  // Key used to group completion and failure notifications together
  static const _encodeGroupKey = 'com.flamingwater.crispcoder.ENCODES';

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

      // Initialize with a callback to handle notification action button presses
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Check if the pressed action matches our cancel ID
          if (response.actionId == 'cancel_encode') {
            onCancelRequested?.call();
          }
        },
      );

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

  /// Displays or updates a progress notification with a progress bar and Cancel button.
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
        // Add the Cancel action button directly to the notification
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            'cancel_encode',
            'Cancel',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );
      const iosDetails = DarwinNotificationDetails();
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(
        id: _progressNotificationId,
        title: 'Transcoding Video',
        body: content,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  /// Cancels the ongoing progress notification.
  Future<void> cancelProgress() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: _progressNotificationId);
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
        // Enable grouping so multiple completions bundle into a summary
        groupKey: _encodeGroupKey,
        setAsGroupSummary: false,
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id: title.hashCode,
        title: 'Encode Completed',
        body: '$title has finished transcoding successfully.',
        notificationDetails: details,
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
        // Enable grouping so multiple failures bundle into a summary
        groupKey: _encodeGroupKey,
        setAsGroupSummary: false,
      );
      final details = NotificationDetails(android: androidDetails);

      await _plugin.show(
        id: title.hashCode,
        title: 'Encode Failed',
        body: '$title failed: $error',
        notificationDetails: details,
      );
    } catch (_) {}
  }
}

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);
