import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/features/editor/widgets/editor_welcome_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpWelcome(
    WidgetTester tester, {
    OutputType type = OutputType.video,
    ValueChanged<OutputType>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorWelcomeView(
            outputType: type,
            onOutputTypeChanged: onChanged ?? (_) {},
            probing: false,
            onPick: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows heading, mode chips, and source picker', (tester) async {
    await pumpWelcome(tester);

    expect(find.text('Start a new encode'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Subtitles'), findsOneWidget);
    expect(find.text('Select source video'), findsOneWidget);
    expect(find.text('Tap to choose a video file'), findsOneWidget);
  });

  testWidgets('tapping a mode chip reports the selection', (tester) async {
    OutputType? selected;
    await pumpWelcome(tester, onChanged: (t) => selected = t);

    await tester.tap(find.text('Audio'));
    await tester.pump();

    expect(selected, OutputType.audio);
  });

  testWidgets('mode selector uses a segmented control', (tester) async {
    await pumpWelcome(tester);

    // The three output modes are side-by-side segments in one control.
    expect(find.byType(SegmentedButton<OutputType>), findsOneWidget);
    final videoX = tester.getCenter(find.text('Video')).dx;
    final audioX = tester.getCenter(find.text('Audio')).dx;
    final subsX = tester.getCenter(find.text('Subtitles')).dx;
    expect(audioX, greaterThan(videoX));
    expect(subsX, greaterThan(audioX));
  });

  testWidgets('probing shows the reading state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorWelcomeView(
            outputType: OutputType.video,
            onOutputTypeChanged: (_) {},
            probing: true,
            onPick: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Reading source…'), findsOneWidget);
  });
}
