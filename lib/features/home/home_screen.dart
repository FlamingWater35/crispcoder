import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/encode_task.dart';
import '../../providers/queue_provider.dart';
import '../editor/editor_screen.dart';
import 'widgets/empty_queue_state.dart';
import 'widgets/queue_tile.dart';

/// Main queue screen: shows active encode, pending tasks, and add button.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CrispCoder'),
        actions: [
          if (queue.any(
            (t) =>
                t.status == EncodeStatus.completed ||
                t.status == EncodeStatus.cancelled,
          ))
            IconButton(
              tooltip: 'Clear finished',
              icon: const Icon(Icons.cleaning_services_outlined),
              onPressed: () => ref.read(queueProvider.notifier).clearFinished(),
            ),
        ],
      ),
      body: SafeArea(
        child: queue.isEmpty
            ? const EmptyQueueState()
            : ListView.builder(
                itemCount: queue.length,
                itemBuilder: (context, i) {
                  final task = queue[i];
                  return QueueTile(
                    key: ValueKey(task.id),
                    task: task,
                    onCancel: task.status == EncodeStatus.running
                        ? () => ref.read(queueProvider.notifier).cancelActive()
                        : null,
                    onRemove: task.status != EncodeStatus.running
                        ? () => ref.read(queueProvider.notifier).remove(task.id)
                        : null,
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Encode'),
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const EditorScreen()));
        },
      ),
    );
  }
}
