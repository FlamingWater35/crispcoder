import 'package:flutter/material.dart';

/// Lightweight in-memory log viewer. Listens to a global notifier for updates.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  static final List<String> _buffer = <String>[];
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  /// Append a log line; called by the logger's output sink at app level.
  /// Strips ANSI codes, box-drawing characters, and extra spaces for readability.
  static void push(String line) {
    final cleanLine = line
        .replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '') // ANSI codes
        .replaceAll(RegExp(r'[┌┐└┘│─]'), '') // Box drawing chars
        .replaceAll(RegExp(r'\s{2,}'), ' ') // Collapse spaces
        .trim();

    if (cleanLine.isEmpty) return;

    _buffer.add(cleanLine);
    if (_buffer.length > 500) _buffer.removeRange(0, _buffer.length - 500);
    _notifier.value = _buffer.length; // Trigger UI rebuild
  }

  /// Clears the log buffer.
  static void clear() {
    _buffer.clear();
    _notifier.value = 0;
  }

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => LogsScreen.clear(),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: LogsScreen._notifier,
        builder: (context, count, _) {
          if (LogsScreen._buffer.isEmpty) {
            return const Center(child: Text('No log output yet.'));
          }
          return ListView.builder(
            itemCount: LogsScreen._buffer.length,
            itemBuilder: (context, i) {
              final line = LogsScreen._buffer[i];
              return ListTile(
                dense: true,
                title: Text(
                  line,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
