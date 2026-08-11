import 'dart:io';

import 'package:crispcoder/app.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/app_settings_repository.dart';
import 'package:crispcoder/data/repositories/history_repository.dart';
import 'package:crispcoder/data/repositories/preset_repository.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:crispcoder/features/logs/logs_screen.dart';
import 'package:flutter/material.dart';
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
    // Settle entrance animations (flutter_animate zero-delay timers) so no
    // timers are left pending when the test tears down.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('CrispCoder'), findsWidgets);
  });

  testWidgets('navigating between tabs does not throw duplicate-hero errors',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CrispCoderApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Go to Logs and scroll so the jump-to-bottom FAB appears — both FABs
    // (home + logs) now live in the same IndexedStack subtree, so they must
    // have distinct hero tags or pressing New Encode throws a
    // "multiple heroes share the same tag" error.
    await tester.tap(find.text('Logs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    for (var i = 0; i < 100; i++) {
      LogsScreen.push('12:00:00.000\nmessage number $i');
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    // Back to Queue (the log FAB is still mounted in the IndexedStack) and
    // open the editor via the New Encode FAB — the reported crash path.
    // (There are two "New Encode" labels — the empty-state CTA and the FAB —
    // so target the FAB by type.)
    await tester.tap(find.text('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });

  testWidgets('About card shows the new subtitle and opens the licenses page',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CrispCoderApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Go to Settings.
    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Scroll to the About card and check the new subtitle.
    await tester.scrollUntilVisible(find.text('A transcoder powered by FFmpeg'), 300);
    expect(find.text('A transcoder powered by FFmpeg'), findsOneWidget);

    // Tapping opens the licenses page (showLicensePage).
    await tester.tap(find.text('A transcoder powered by FFmpeg'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The license page has an app bar with the application name.
    expect(find.text('Licenses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
