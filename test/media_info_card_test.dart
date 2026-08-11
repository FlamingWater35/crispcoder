import 'package:crispcoder/data/models/media_info.dart';
import 'package:crispcoder/features/editor/widgets/media_info_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MediaInfo info({
    String? container,
    String? videoCodec = 'h264',
    String? audioCodec = 'aac',
  }) {
    return MediaInfo(
      path: '/tmp/video.mp4',
      duration: const Duration(minutes: 5),
      width: 1920,
      height: 1080,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
      container: container,
    );
  }

  Future<void> pumpCard(WidgetTester tester, MediaInfo mediaInfo) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MediaInfoCard(info: mediaInfo))),
    );
    await tester.pump();
  }

  testWidgets('collapsed by default; expanding reveals all stats',
      (tester) async {
    await pumpCard(
      tester,
      info(container: 'mov,mp4,m4a,3gp,3g2,mj2'),
    );

    // Header uses the new title.
    expect(find.text('Source File Details'), findsOneWidget);

    // Collapsed by default → stats hidden.
    expect(find.text('Resolution'), findsNothing);
    expect(find.text('Duration'), findsNothing);

    // Expand to reveal the stats.
    await tester.tap(find.text('Source File Details'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('Duration'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Container'), findsOneWidget);

    // Values
    expect(find.text('1080p (1920x1080)'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
    expect(find.text('h264'), findsOneWidget);
    expect(find.text('aac'), findsOneWidget);

    // Up to 3 containers, uppercased and joined in the stat card
    expect(find.text('MOV · MP4 · M4A'), findsOneWidget);
    // 4th token not shown
    expect(find.text('3GP'), findsNothing);
  });

  testWidgets('tapping the header collapses and re-expands the stats',
      (tester) async {
    await pumpCard(tester, info(container: 'mp4'));

    // Expand first (collapsed by default).
    await tester.tap(find.text('Source File Details'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);

    // Collapse
    await tester.tap(find.text('Source File Details'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resolution'), findsNothing);
    expect(find.text('05:00'), findsNothing);

    // Expand again
    await tester.tap(find.text('Source File Details'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('05:00'), findsOneWidget);
  });
}
