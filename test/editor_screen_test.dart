import 'dart:io';

import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/app_settings_repository.dart';
import 'package:crispcoder/data/repositories/history_repository.dart';
import 'package:crispcoder/data/repositories/preset_repository.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:crispcoder/features/editor/editor_screen.dart';
import 'package:crispcoder/features/editor/widgets/editor_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('editor_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());
    await AppSettingsRepository.instance.bootstrap();
    await PresetRepository.instance.bootstrap();
    await QueueRepository.instance.bootstrap();
    await HistoryRepository.instance.bootstrap();
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EditorScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('initial view shows welcome and hides the action bar',
      (tester) async {
    await pumpEditor(tester);

    // Welcome view visible
    expect(find.text('Start a new encode'), findsOneWidget);
    expect(find.text('Select source video'), findsOneWidget);

    // No Preview / Start Encode buttons before a source is picked
    expect(find.byType(EditorActionBar), findsNothing);
    expect(find.text('Preview'), findsNothing);
    expect(find.text('Start Encode'), findsNothing);
  });
}
