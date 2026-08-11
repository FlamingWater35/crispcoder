import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/encode_task.dart';
import '../../providers/queue_provider.dart';
import '../editor/editor_screen.dart';
import 'widgets/active_encode_card.dart';
import 'widgets/empty_queue_state.dart';
import 'widgets/queue_tile.dart';
import 'widgets/status_summary.dart';

/// Main queue screen: status summary, active-encode spotlight, pending queue,
/// completed tasks, and the "New Encode" action.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const EditorScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
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
                    if (pending.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          pending.length == 1
                              ? 'In queue'
                              : 'In queue (${pending.length})',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final task in pending)
                        QueueTile(
                          key: ValueKey(task.id),
                          task: task,
                          onCancel: task.status == EncodeStatus.running
                              ? () => ref
                                    .read(queueProvider.notifier)
                                    .cancelActive()
                              : null,
                          onRemove: task.status != EncodeStatus.running
                              ? () => ref
                                    .read(queueProvider.notifier)
                                    .remove(task.id)
                              : null,
                        ),
                    ],
                    if (completed.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Completed',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      for (final task in completed)
                        QueueTile(
                          key: ValueKey(task.id),
                          task: task,
                          onRemove: () => ref
                              .read(queueProvider.notifier)
                              .remove(task.id),
                        ),
                    ],
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Encode'),
        onPressed: () => _openEditor(context),
      ),
    );
  }
}
