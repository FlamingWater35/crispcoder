import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'data/models/encode_task.dart';
import 'data/models/transcode_preset.dart';
import 'data/repositories/app_settings_repository.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/preset_repository.dart';
import 'data/repositories/queue_repository.dart';
import 'data/services/foreground_service_wrapper.dart';
import 'data/services/notification_service.dart';
import 'data/services/permission_service.dart';
import 'data/services/update_service.dart';
import 'features/logs/logs_screen.dart';

/// Custom log output that forwards lines to the in-app LogsScreen buffer.
class InAppLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    LogsScreen.push(event.lines.join('\n'));
  }
}

/// Global logger instance.
final loggerProvider = Provider<Logger>((ref) {
  return Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 100,
      colors: false,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    output: MultiOutput([ConsoleOutput(), InAppLogOutput()]),
  );
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(TranscodePresetAdapter());
  Hive.registerAdapter(EncodeTaskAdapter());
  Hive.registerAdapter(EncodeStatusAdapter());

  try {
    // DB Migration V6: Added VP9, FLAC, Vorbis codecs
    final settingsBox = await Hive.openBox(AppConstants.boxSettings);
    final schemaVersion =
        settingsBox.get(AppConstants.keySchemaVersion) as int? ?? 1;
    if (schemaVersion < 6) {
      await Hive.deleteBoxFromDisk(AppConstants.boxPresets);
      await settingsBox.put(AppConstants.keySchemaVersion, 6);
    }
  } catch (e, st) {
    debugPrint('Settings migration error: $e\n$st');
  }

  // Bootstrap persistence (queue/history survive restarts). Each repository
  // is bootstrapped independently so a failure in one (e.g. a corrupt box)
  // can never skip the others or leave a repository uninitialized — the
  // repositories themselves fall back to in-memory storage via openHiveBox.
  await _bootstrapRepository(
    'presets',
    () => PresetRepository.instance.bootstrap(),
  );
  await _bootstrapRepository(
    'queue',
    () => QueueRepository.instance.bootstrap(),
  );
  await _bootstrapRepository(
    'history',
    () => HistoryRepository.instance.bootstrap(),
  );
  await _bootstrapRepository(
    'settings',
    () => AppSettingsRepository.instance.bootstrap(),
  );

  try {
    await ForegroundServiceWrapper.instance.init();
    await NotificationService.instance.init();

    await UpdateService().cleanupUpdateFile();
  } catch (e, st) {
    debugPrint('Bootstrap error: $e\n$st');
  }

  runApp(const ProviderScope(child: CrispCoderApp()));

  // Request boot permissions (media read + notifications) as soon as the UI
  // is up. Deliberately fire-and-forget: the requests surface the OS dialogs
  // without blocking first paint, and both permissions can also be granted
  // later (file picker re-requests media read; Settings has both).
  unawaited(PermissionService().requestBootPermissions());
}

/// Runs a repository bootstrap, logging instead of throwing so one failing
/// repository can never take down app startup.
Future<void> _bootstrapRepository(
  String name,
  Future<void> Function() bootstrap,
) async {
  try {
    await bootstrap();
  } catch (e, st) {
    debugPrint('$name repository bootstrap error: $e\n$st');
  }
}
