import 'dart:io';

import 'package:crispcoder/app.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/app_settings_repository.dart';
import 'package:crispcoder/data/repositories/history_repository.dart';
import 'package:crispcoder/data/repositories/preset_repository.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    PackageInfo.setMockInitialValues(
      appName: 'crispcoder',
      packageName: 'com.flamingwater.crispcoder',
      version: '1.2.3',
      buildNumber: '1',
      buildSignature: '',
    );

    final tempDir = await Directory.systemTemp.createTemp(
      'crispcoder_widget_test',
    );
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());

    // Mirror main()'s bootstrap for the in-memory Hive stores the app reads.
    await AppSettingsRepository.instance.bootstrap();
    await PresetRepository.instance.bootstrap();
    await QueueRepository.instance.bootstrap();
    await HistoryRepository.instance.bootstrap();
  });

  testWidgets('App boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CrispCoderApp()));
    await tester.pump();

    expect(find.text('CrispCoder'), findsOneWidget);
  });
}
