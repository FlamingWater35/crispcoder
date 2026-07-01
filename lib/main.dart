import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import 'app.dart';
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
    for (final line in event.lines) {
      LogsScreen.push(line);
    }
  }
}

/// Global logger instance. Use ProviderScope override in tests to swap.
final loggerProvider = Provider<Logger>((ref) {
  return Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 100,
      colors: false, // Disable ANSI colors for clean console and UI output
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
    // Send logs to both the standard console and the in-app UI
    output: MultiOutput([ConsoleOutput(), InAppLogOutput()]),
  );
});

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive before any repository reads boxes
  await Hive.initFlutter();
  Hive.registerAdapter(TranscodePresetAdapter());
  Hive.registerAdapter(EncodeTaskAdapter());
  Hive.registerAdapter(EncodeStatusAdapter());

  try {
    // Clear temporary video cache to prevent unbounded storage growth
    await PathHelpers.clearAppCache();

    await PresetRepository.instance.bootstrap();
    await QueueRepository.instance.bootstrap();
    await HistoryRepository.instance.bootstrap();
    await AppSettingsRepository.instance.bootstrap();
    await ForegroundServiceWrapper.instance.init();

    // Clean up any leftover downloaded update APKs from previous sessions
    await UpdateService().cleanupUpdateFile();
  } catch (e, st) {
    // Bootstrap failure must not hard-crash; allow app to start with in-memory fallback
    debugPrint('Bootstrap error: $e\n$st');
  }

  runApp(const ProviderScope(child: CrispCoderApp()));
}
