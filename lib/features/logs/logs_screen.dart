import 'package:flutter/material.dart';

/// Lightweight in-memory log viewer. Real implementation would route the
/// `logger` output into a ring-buffer provider; here we surface a placeholder
/// with proper loading/empty states so the screen is robust by default.
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  static final List<String> _buffer = <String>[];

  /// Append a log line; called by the logger's output sink at app level.
  static void push(String line) {
    _buffer.add(line);
    if (_buffer.length > 500) _buffer.removeRange(0, _buffer.length - 500);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _buffer.clear(),
          ),
        ],
      ),
      body: _buffer.isEmpty
          ? const Center(child: Text('No log output yet.'))
          : ListView.builder(
              itemCount: _buffer.length,
              itemBuilder: (context, i) {
                final line = _buffer[i];
                return ListTile(
                  dense: true,
                  title: Text(
                    line,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
