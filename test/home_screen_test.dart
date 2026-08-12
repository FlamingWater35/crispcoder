import 'dart:io';

import 'package:crispcoder/data/models/encode_progress.dart';
import 'package:crispcoder/data/models/encode_task.dart';
import 'package:crispcoder/data/models/transcode_preset.dart';
import 'package:crispcoder/data/repositories/queue_repository.dart';
import 'package:crispcoder/features/home/home_screen.dart';
import 'package:crispcoder/features/home/widgets/status_summary.dart';
import 'package:crispcoder/providers/active_encode_provider.dart';
import 'package:crispcoder/providers/queue_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

/// Notifier override that reports a fixed progress value.
class _FixedProgressNotifier extends ActiveEncodeNotifier {
  _FixedProgressNotifier(this._progress);

  final EncodeProgress? _progress;

  @override
  EncodeProgress? build() => _progress;
}

/// Notifier override whose value can be updated mid-test to simulate live
/// progress ticks from the transcoder.
class _MutableProgressNotifier extends ActiveEncodeNotifier {
  EncodeProgress? _progress;

  void update(EncodeProgress? progress) => state = progress;

  @override
  EncodeProgress? build() => _progress;
}

/// Seeds tasks via real Hive I/O. Must run inside tester.runAsync because
/// testWidgets bodies execute in a FakeAsync zone where real async I/O
/// (file writes) never completes.
Future<void> seed(WidgetTester tester, List<EncodeTask> tasks) async {
  await tester.runAsync(() async {
    for (final t in tasks) {
      await QueueRepository.instance.upsert(t);
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('crispcoder_home_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TranscodePresetAdapter());
    Hive.registerAdapter(EncodeTaskAdapter());
    Hive.registerAdapter(EncodeStatusAdapter());

    await QueueRepository.instance.bootstrap();
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    await Hive.deleteBoxFromDisk('queue');
    QueueRepository.instance.resetForTesting();
    await QueueRepository.instance.bootstrap();
  });

  EncodeTask task({
    required String id,
    EncodeStatus status = EncodeStatus.pending,
    String name = 'movie.mp4',
    DateTime? createdAt,
    DateTime? finishedAt,
    String? errorMessage,
    bool savedToGallery = false,
    OutputType outputType = OutputType.video,
    String? outputPath,
    String? publishedUri,
  }) {
    return EncodeTask(
      id: id,
      sourcePath: '/tmp/$name',
      sourceName: name,
      outputPath: outputPath ?? '/tmp/out_$name',
      preset: TranscodePreset(
        id: 'p',
        name: 'P',
        category: 'Test',
        outputType: outputType,
        videoCodec: VideoCodec.h264,
        crf: 23,
        audioCodec: AudioCodec.aac,
        audioBitrate: 160,
        container: ContainerFormat.mp4,
      ),
      createdAt: createdAt ?? DateTime(2024, 1, 1),
      finishedAt: finishedAt,
      status: status,
      startedAt: status == EncodeStatus.running ? DateTime(2024, 1, 1) : null,
      savedToGallery: savedToGallery,
      publishedUri: publishedUri,
      totalDurationSeconds: 60,
      errorMessage: errorMessage,
    );
  }

  Future<void> pumpHome(
    WidgetTester tester, {
    EncodeProgress? progress,
    Size size = const Size(800, 2400),
  }) async {
    // Tall viewport so every section of the home screen is visible without
    // scrolling (ListView children are lazily built). Callers may pass a
    // narrower size to exercise the compact (phone) layout.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: progress != null
            ? [
                activeEncodeProvider.overrideWith(
                  () => _FixedProgressNotifier(progress),
                ),
              ]
            : const [],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    // Settle entrance animations (staggered fade+slide) and let the
    // flutter_animate zero-delay timers fire before assertions.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('empty queue shows stats and a New Encode CTA',
      (tester) async {
    await pumpHome(tester);

    // Status summary all zeros
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);

    // Empty state
    expect(find.text('No encodes queued'), findsOneWidget);
    expect(find.text('New Encode'), findsNWidgets(2)); // CTA + FAB
  });

  testWidgets('populated queue shows stats, sections, and tiles',
      (tester) async {
    await seed(tester, [
      task(id: 'pending-1', name: 'alpha.mp4'),
      task(
        id: 'done-1',
        name: 'bravo.mp4',
        status: EncodeStatus.completed,
        finishedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ]);

    await pumpHome(tester);

    // Stats reflect the queue: 1 queued, 1 completed (scoped to the status
    // chips — the section-header count badges render extra "1" digits).
    expect(
      find.descendant(
        of: find.byType(StatusSummary),
        matching: find.text('1'),
      ),
      findsNWidgets(2),
    );
    // Single pending task → header is the singular form
    expect(find.text('In queue'), findsOneWidget);

    // Nothing running + pending work → resume banner is shown
    expect(find.text('Resume encode'), findsOneWidget);
    expect(find.text('One task waiting'), findsOneWidget);

    // The pending task appears twice: in the "Up next" card and in the
    // "In queue" tile. The completed task appears only in its tile.
    expect(find.text('alpha.mp4'), findsNWidgets(2));
    expect(find.text('bravo.mp4'), findsOneWidget);

    // Up next card (nothing running, pending first)
    expect(find.text('Up next'), findsOneWidget);

    // Completed section header
    expect(find.text('Completed'), findsNWidgets(2)); // stat chip + header
  });

  testWidgets('completed tasks are sorted newest-first', (tester) async {
    await seed(tester, [
      task(
        id: 'done-old',
        name: 'older.mp4',
        status: EncodeStatus.completed,
        finishedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      task(
        id: 'done-new',
        name: 'newest.mp4',
        status: EncodeStatus.completed,
        finishedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
    ]);

    await pumpHome(tester);

    // Both tiles render
    expect(find.text('older.mp4'), findsOneWidget);
    expect(find.text('newest.mp4'), findsOneWidget);

    // Newest (finished later) must be rendered ABOVE the older one.
    final newestY = tester.getTopLeft(find.text('newest.mp4')).dy;
    final olderY = tester.getTopLeft(find.text('older.mp4')).dy;
    expect(newestY, lessThan(olderY));
  });

  testWidgets('running task shows spotlight with cancel', (tester) async {
    await seed(tester, [
      task(id: 'run-1', name: 'live.mp4', status: EncodeStatus.running),
    ]);

    await pumpHome(tester);

    expect(find.text('Encoding'), findsOneWidget);
    expect(find.text('live.mp4'), findsOneWidget);
    // No progress yet → starting hint, no cancel button
    expect(find.text('Starting the process...'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);

    // A running task means there is nothing to resume — no banner.
    expect(find.text('Resume encode'), findsNothing);

    // Cancel is only shown once progress arrives (not covered here)
  });

  testWidgets('running audio extraction spotlights the artifact, not the source',
      (tester) async {
    // The screenshot bug: while the job runs the spotlight showed the source
    // "Perfect_World.mp4" and only flipped to "…_encoded.m4a" on completion.
    await seed(tester, [
      task(
        id: 'run-audio',
        name: 'Perfect_World.mp4',
        outputType: OutputType.audio,
        outputPath: '/docs/CrispCoder/Audio/Perfect_World_encoded.m4a',
        status: EncodeStatus.running,
      ),
    ]);

    await pumpHome(tester);

    // Spotlight title is the artifact immediately, never the source .mp4.
    expect(find.text('Perfect_World_encoded.m4a'), findsOneWidget);
    expect(find.text('Perfect_World.mp4'), findsNothing);
  });

  testWidgets(
      'running task with live progress shows the progress ring and stats',
      (tester) async {
    await seed(tester, [
      task(id: 'run-2', name: 'live2.mp4', status: EncodeStatus.running),
    ]);

    await pumpHome(
      tester,
      progress: const EncodeProgress(
        taskId: 'run-2',
        percent: 42.5,
        fps: 30.0,
        speed: 2.5,
        etaSeconds: 90,
        bitrateBitsPerSec: 1_500_000,
        frameNumber: 0,
        bytesProcessed: 0,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 42.5% rounds to 43% with toStringAsFixed(0) in the ring
    expect(find.text('43%'), findsOneWidget); // ring center
    // Stats now live in labeled cards: values are separate from their labels.
    expect(find.text('FPS'), findsOneWidget);
    expect(find.text('30.0 fps'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('2.50x'), findsOneWidget);
    expect(find.text('ETA'), findsOneWidget);
    expect(find.text('01:30'), findsOneWidget);
    expect(find.text('Bitrate'), findsOneWidget);
    expect(find.text('1.50 Mbps'), findsOneWidget);
    expect(find.text('Starting the process...'), findsNothing);
  });

  testWidgets('progress ring survives multiple live progress ticks',
      (tester) async {
    await seed(tester, [
      task(id: 'run-3', name: 'live3.mp4', status: EncodeStatus.running),
    ]);

    // Mutable notifier so we can push successive progress values, like the
    // real transcoder does at ~1 Hz.
    final notifier = _MutableProgressNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeEncodeProvider.overrideWith(() => notifier),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // First tick
    notifier.update(
      const EncodeProgress(
        taskId: 'run-3',
        percent: 10,
        fps: 30.0,
        speed: 2.5,
        etaSeconds: 90,
        bitrateBitsPerSec: 1_500_000,
        frameNumber: 0,
        bytesProcessed: 0,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('10%'), findsOneWidget);

    // Second tick — previously crashed with LateInitializationError because
    // the ring reassigned a `late final` animation field.
    notifier.update(
      const EncodeProgress(
        taskId: 'run-3',
        percent: 42.5,
        fps: 30.0,
        speed: 2.5,
        etaSeconds: 90,
        bitrateBitsPerSec: 1_500_000,
        frameNumber: 0,
        bytesProcessed: 0,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Let the ring animation finish so no timers stay pending.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('43%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clear finished action removes completed tasks',
      (tester) async {
    await seed(tester, [
      task(
        id: 'done-2',
        name: 'done.mp4',
        status: EncodeStatus.completed,
        finishedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);

    await pumpHome(tester);

    expect(find.byIcon(Icons.cleaning_services_outlined), findsOneWidget);

    // clearFinished() does real Hive I/O and updates the Riverpod state —
    // run it inside runAsync to escape the FakeAsync zone.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await tester.runAsync(() async {
      await container.read(queueProvider.notifier).clearFinished();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // AnimatedSwitcher

    // Queue emptied → empty state returns
    expect(find.text('No encodes queued'), findsOneWidget);
  });

  testWidgets('failed and cancelled tasks are visible with a section header',
      (tester) async {
    await seed(tester, [
      task(
        id: 'fail-1',
        name: 'broken.mp4',
        status: EncodeStatus.failed,
        errorMessage: 'FFmpeg exit code 1',
        finishedAt: DateTime.now().subtract(const Duration(minutes: 3)),
      ),
      task(
        id: 'cancel-1',
        name: 'aborted.mp4',
        status: EncodeStatus.cancelled,
        finishedAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ]);

    await pumpHome(tester);

    // Section header groups both
    expect(find.text('Failed / Cancelled'), findsOneWidget);
    expect(find.text('broken.mp4'), findsOneWidget);
    expect(find.text('aborted.mp4'), findsOneWidget);
    // The failure message is surfaced on the tile
    expect(find.text('FFmpeg exit code 1'), findsOneWidget);

    // The Failed stat chip reflects the count
    final chipCount = find.descendant(
      of: find.byType(StatusSummary),
      matching: find.text('2'),
    );
    expect(chipCount, findsOneWidget);
  });

  testWidgets('queue tile shows the real path unless saved to DCIM',
      (tester) async {
    // Seeded via Hive: savedToGallery=false → real path shown; true →
    // 'Saved to DCIM/Videolation'.
    await seed(tester, [
      task(id: 'gallery-1', name: 'g.mp4', status: EncodeStatus.completed),
      task(
        id: 'gallery-2',
        name: 'h.mp4',
        status: EncodeStatus.completed,
        savedToGallery: true,
        publishedUri: 'content://media/external/video/media/7',
      ),
    ]);

    await pumpHome(tester);

    // Expand both completed tiles to reveal the details panel.
    await tester.tap(find.text('g.mp4'));
    await tester.tap(find.text('h.mp4'));
    await tester.pump();

    expect(find.text('/tmp/out_g.mp4'), findsOneWidget);
    expect(
      find.text('Saved to DCIM/Videolation (out_h.mp4)'),
      findsOneWidget,
    );
  });

  testWidgets('audio/subtitle tiles title the output artifact, not the source',
      (tester) async {
    // The audio task's source video is "clip.mp4" but the artifact is
    // "clip_encoded.m4a" — the tile title must show the artifact so the
    // queue never shouts ".mp4" for an audio extraction.
    await seed(tester, [
      task(
        id: 'audio-1',
        name: 'clip.mp4',
        outputType: OutputType.audio,
        outputPath: '/docs/CrispCoder/Audio/clip_encoded.m4a',
        status: EncodeStatus.completed,
      ),
      task(
        id: 'sub-1',
        name: 'movie.mp4',
        outputType: OutputType.subtitle,
        outputPath: '/docs/CrispCoder/Subtitles/movie_encoded.srt',
        status: EncodeStatus.completed,
      ),
      // A published audio task: label must show Music/CrispCoder, not DCIM
      // (the Audio MediaStore collection rejects DCIM as a relative path).
      task(
        id: 'audio-pub',
        name: 'song.mp4',
        outputType: OutputType.audio,
        outputPath: '/docs/CrispCoder/Audio/song_encoded.m4a',
        publishedUri: 'content://media/external/audio/media/9',
        status: EncodeStatus.completed,
      ),
    ]);

    await pumpHome(tester);

    // Titles are the output basenames — never the source .mp4.
    expect(find.text('clip_encoded.m4a'), findsOneWidget);
    expect(find.text('movie_encoded.srt'), findsOneWidget);
    expect(find.text('song_encoded.m4a'), findsOneWidget);
    expect(find.text('clip.mp4'), findsNothing);
    expect(find.text('movie.mp4'), findsNothing);

    // The details panel's Source row still shows the real source name.
    await tester.tap(find.text('clip_encoded.m4a'));
    await tester.pump();
    expect(find.text('clip.mp4'), findsOneWidget);

    // Published audio shows the Music/CrispCoder location, not DCIM.
    await tester.tap(find.text('song_encoded.m4a'));
    await tester.pump();
    expect(
      find.text('Saved to Music/CrispCoder (song_encoded.m4a)'),
      findsOneWidget,
    );
  });

  testWidgets('status chips lay out as a 2×2 grid on phone widths',
      (tester) async {
    // 360 logical px is a typical phone width — below the 600px single-row
    // threshold, so the four chips must wrap into two rows of two.
    await seed(tester, [
      task(id: 'r', name: 'r.mp4', status: EncodeStatus.running),
      task(id: 'q', name: 'q.mp4'),
      task(
        id: 'c',
        name: 'c.mp4',
        status: EncodeStatus.completed,
        finishedAt: DateTime.now(),
      ),
      task(
        id: 'f',
        name: 'f.mp4',
        status: EncodeStatus.failed,
        errorMessage: 'boom',
        finishedAt: DateTime.now(),
      ),
    ]);

    await pumpHome(tester, size: const Size(360, 800));

    final summary = find.byType(StatusSummary);
    expect(summary, findsOneWidget);

    // Scope to the status chips: the section header also renders
    // "Completed" (and the queue tiles their own titles).
    Finder inSummary(String label) =>
        find.descendant(of: summary, matching: find.text(label));

    // Two rows: "Running"/"Queued" share the top row, "Completed"/"Failed"
    // the bottom row. Same-row chips have equal vertical centers; the rows
    // are vertically separated.
    final runningY = tester.getCenter(inSummary('Running')).dy;
    final queuedY = tester.getCenter(inSummary('Queued')).dy;
    final completedY = tester.getCenter(inSummary('Completed')).dy;
    final failedY = tester.getCenter(inSummary('Failed')).dy;
    expect(runningY, moreOrLessEquals(queuedY, epsilon: 0.01));
    expect(completedY, moreOrLessEquals(failedY, epsilon: 0.01));
    expect(completedY, greaterThan(runningY));

    // All four labels render untruncated (each chip is ~half the width, so
    // the labels have room — no "R…"/"0…" glyphs).
    expect(inSummary('Running'), findsOneWidget);
    expect(inSummary('Queued'), findsOneWidget);
    expect(inSummary('Completed'), findsOneWidget);
    expect(inSummary('Failed'), findsOneWidget);
  });

  testWidgets('status chips stay in a single row on wide screens',
      (tester) async {
    await pumpHome(tester, size: const Size(1000, 1200));

    final summary = find.byType(StatusSummary);
    Finder inSummary(String label) =>
        find.descendant(of: summary, matching: find.text(label));

    // All four chips share one horizontal line.
    final runningY = tester.getCenter(inSummary('Running')).dy;
    final queuedY = tester.getCenter(inSummary('Queued')).dy;
    final completedY = tester.getCenter(inSummary('Completed')).dy;
    final failedY = tester.getCenter(inSummary('Failed')).dy;
    expect(runningY, moreOrLessEquals(queuedY, epsilon: 0.01));
    expect(runningY, moreOrLessEquals(completedY, epsilon: 0.01));
    expect(runningY, moreOrLessEquals(failedY, epsilon: 0.01));
  });
}
