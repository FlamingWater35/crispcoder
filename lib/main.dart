import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/path_helpers.dart';
import 'data/models/encode_task.dart';
import 'data/models/transcode_preset.dart';
import 'data/repositories/app_settings_repository.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/preset_repository.dart';
import 'data/repositories/queue_repository.dart';
import 'data/services/foreground_service_wrapper.dart';
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
    // DB Migration V4: Added OutputType enum
    final settingsBox = await Hive.openBox(AppConstants.boxSettings);
    final schemaVersion =
        settingsBox.get(AppConstants.keySchemaVersion) as int? ?? 1;
    if (schemaVersion < 4) {
      await Hive.deleteBoxFromDisk(AppConstants.boxPresets);
      await settingsBox.put(AppConstants.keySchemaVersion, 4);
    }

    await PathHelpers.clearAppCache();

    await PresetRepository.instance.bootstrap();
    await QueueRepository.instance.bootstrap();
    await HistoryRepository.instance.bootstrap();
    await AppSettingsRepository.instance.bootstrap();
    await ForegroundServiceWrapper.instance.init();

    await UpdateService().cleanupUpdateFile();
  } catch (e, st) {
    debugPrint('Bootstrap error: $e\n$st');
  }

  runApp(const ProviderScope(child: CrispCoderApp()));
}
