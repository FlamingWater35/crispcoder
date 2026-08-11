import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/responsive.dart';
import '../../data/models/encode_task.dart';
import '../../providers/queue_provider.dart';
import '../editor/editor_screen.dart';
import 'widgets/active_encode_card.dart';
import 'widgets/empty_queue_state.dart';
import 'widgets/queue_tile.dart';
import 'widgets/resume_queue_banner.dart';
import 'widgets/section_header.dart';
import 'widgets/status_summary.dart';

/// Main queue screen: status summary, active-encode spotlight, pending queue,
/// completed tasks, and the "New Encode" action.
///
/// Animations: cards enter with a staggered slide+fade as they are added to
/// their sections, and sections collapse/expand with an animated size + header
/// chevron. Layout adapts to wide screens by constraining content to a
/// comfortable column width.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _queueExpanded = true;
  bool _completedExpanded = true;

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditorScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(queueProvider);
    final hasFinished = queue.any(
      (t) =>
          t.status == EncodeStatus.completed ||
          t.status == EncodeStatus.cancelled,
    );

    final runningCount = queue
        .where((t) => t.status == EncodeStatus.running)
        .length;
    final queuedCount = queue
        .where(
          (t) =>
              t.status == EncodeStatus.pending ||
              t.status == EncodeStatus.paused,
        )
        .length;
    final completedCount = queue
        .where((t) => t.status == EncodeStatus.completed)
        .length;

    final pending = queue
        .where(
          (t) =>
              t.status == EncodeStatus.pending ||
              t.status == EncodeStatus.paused,
        )
        .toList();
    final completed = queue
        .where((t) => t.status == EncodeStatus.completed)
        .toList()
      // Newest completions first: `finishedAt` reflects when the encode
      // actually finished (createdAt is the enqueue time).
      ..sort(
        (a, b) => (b.finishedAt ?? b.createdAt).compareTo(
          a.finishedAt ?? a.createdAt,
        ),
      );

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrispCoder'),
        actions: [
          if (hasFinished)
            IconButton(
              tooltip: 'Clear finished',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () => ref.read(queueProvider.notifier).clearFinished(),
            ),
        ],
      ),
      body: SafeArea(
        child: centeredContent(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
          child: queue.isEmpty
              ? ListView(
                  key: const ValueKey('empty'),
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    StatusSummary(
                      running: runningCount,
                      queued: queuedCount,
                      completed: completedCount,
                    ),
                    const SizedBox(height: 24),
                    EmptyQueueState(
                      onNewEncode: () => _openEditor(context),
                    ),
                  ],
                )
              : ListView(
                  key: const ValueKey('queue'),
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    StatusSummary(
                      running: runningCount,
                      queued: queuedCount,
                      completed: completedCount,
                    ),
                    const ActiveEncodeCard(),
                    if (pending.isNotEmpty && runningCount == 0) ...[
                      ResumeQueueBanner(
                        count: pending.length,
                        onResume: () => ref
                            .read(queueProvider.notifier)
                            .resume(),
                      ),
                    ],
                    if (pending.isNotEmpty) ...[
                      SectionHeader(
                        title: 'In queue',
                        count: pending.length,
                        icon: Icons.schedule_rounded,
                        isExpanded: _queueExpanded,
                        onToggle: () => setState(
                          () => _queueExpanded = !_queueExpanded,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _queueExpanded
                            ? Column(
                                children: [
                                  for (var i = 0; i < pending.length; i++)
                                    QueueTile(
                                      key: ValueKey(pending[i].id),
                                      task: pending[i],
                                      onCancel:
                                          pending[i].status ==
                                              EncodeStatus.running
                                          ? () => ref
                                                .read(
                                                  queueProvider.notifier,
                                                )
                                                .cancelActive()
                                          : null,
                                      onRemove:
                                          pending[i].status !=
                                              EncodeStatus.running
                                          ? () => ref
                                                .read(
                                                  queueProvider.notifier,
                                                )
                                                .remove(pending[i].id)
                                          : null,
                                    ).animate(
                                      key: ValueKey(
                                        'queue-${pending[i].id}',
                                      ),
                                    ).fadeIn(
                                      delay: (i * 70).ms,
                                      duration: 320.ms,
                                      curve: Curves.easeOut,
                                    ).slideY(
                                      begin: 0.12,
                                      end: 0,
                                      delay: (i * 70).ms,
                                      duration: 320.ms,
                                      curve: Curves.easeOutCubic,
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                    if (completed.isNotEmpty) ...[
                      SectionHeader(
                        title: 'Completed',
                        count: completed.length,
                        icon: Icons.check_circle_rounded,
                        isExpanded: _completedExpanded,
                        onToggle: () => setState(
                          () => _completedExpanded = !_completedExpanded,
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _completedExpanded
                            ? Column(
                                children: [
                                  for (var i = 0; i < completed.length; i++)
                                    QueueTile(
                                      key: ValueKey(completed[i].id),
                                      task: completed[i],
                                      onRemove: () => ref
                                          .read(queueProvider.notifier)
                                          .remove(completed[i].id),
                                    ).animate(
                                      key: ValueKey(
                                        'completed-${completed[i].id}',
                                      ),
                                    ).fadeIn(
                                      delay: (i * 70).ms,
                                      duration: 320.ms,
                                      curve: Curves.easeOut,
                                    ).slideY(
                                      begin: 0.12,
                                      end: 0,
                                      delay: (i * 70).ms,
                                      duration: 320.ms,
                                      curve: Curves.easeOutCubic,
                                    ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
          ),
        ),
      ),
      floatingActionButton: _PulseFab(
        onPressed: () => _openEditor(context),
      ),
    );
  }
}

/// "New Encode" FAB with a subtle scale-on-press animation.
///
/// Pressing the FAB briefly scales it down for tactile feedback. Rotation is
/// intentionally absent — a hold must not leave the icon at an angle.
class _PulseFab extends StatefulWidget {
  const _PulseFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PulseFab> createState() => _PulseFabState();
}

class _PulseFabState extends State<_PulseFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    lowerBound: 0,
    upperBound: 1,
  );
  late final Animation<double> _scale = Tween(begin: 1.0, end: 0.92).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _controller.forward();
  void _onTapUp(_) => _controller.reverse();
  void _onTapCancel() => _controller.reverse();

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        child: FloatingActionButton.extended(
          // Unique hero tag: the shell keeps the Logs screen's FAB mounted in
          // the same route subtree (IndexedStack), so a default tag would
          // collide and throw "multiple heroes share the same tag".
          heroTag: 'fab-new-encode',
          icon: const Icon(Icons.add),
          label: const Text('New Encode'),
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}
