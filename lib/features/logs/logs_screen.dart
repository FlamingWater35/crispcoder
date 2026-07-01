import 'dart:async';

import 'package:flutter/material.dart';

/// Parsed representation of a single log event.
class LogEntry {
  final String timecode;
  final String message;

  const LogEntry(this.timecode, this.message);
}

/// Lightweight in-memory log viewer. Listens to a global notifier for updates.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  static final List<LogEntry> _buffer = <LogEntry>[];
  static final ValueNotifier<int> _notifier = ValueNotifier<int>(0);
  static Timer? _debounceTimer;

  /// Parses a raw multi-line log block from PrettyPrinter into a [LogEntry].
  /// Strips ALL box-drawing characters and ANSI escape codes.
  static LogEntry? _parseLogBlock(String rawBlock) {
    final lines = rawBlock
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .replaceAll(RegExp(r'[\u2500-\u257F]'), '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return null;

    // Heuristic: First line is usually the timestamp (e.g., "20:42:57.299...")
    final timeRegex = RegExp(r'^\d{2}:\d{2}:\d{2}');
    if (timeRegex.hasMatch(lines.first)) {
      final message = lines.skip(1).join('\n').trim();
      return LogEntry(lines.first, message);
    }

    // Fallback if no timestamp is found
    return LogEntry('', lines.join('\n'));
  }

  /// Append a log block; called by the logger's output sink at app level.
  static void push(String rawBlock) {
    final entry = _parseLogBlock(rawBlock);
    if (entry == null) return;

    _buffer.add(entry);
    // Prevent buffer from eating all memory
    if (_buffer.length > 500) {
      _buffer.removeRange(0, _buffer.length - 500);
    }

    // Throttle UI updates to prevent jank when FFmpeg spams logs rapidly.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _notifier.value = _buffer.length;
    });
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
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _showFab = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Shows/hides the jump-to-bottom FAB based on scroll position.
  void _onScroll() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final shouldShow = maxScroll - currentScroll > 250;

    if (shouldShow != _showFab) {
      setState(() => _showFab = shouldShow);
    }
  }

  /// Smoothly scrolls to the latest log entry.
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
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
            onPressed: () => LogsScreen.clear(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: SearchBar(
                controller: _searchController,
                hintText: 'Search logs...',
                leading: const Icon(Icons.search_rounded),
                elevation: const WidgetStatePropertyAll(2.0),
                trailing: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _searchQuery = value.trim()),
              ),
            ),
            // Log List
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: LogsScreen._notifier,
                builder: (context, count, _) {
                  if (LogsScreen._buffer.isEmpty) {
                    return const Center(child: Text('No log output yet.'));
                  }

                  // Filter logs based on search query
                  final filteredLogs = _searchQuery.isEmpty
                      ? LogsScreen._buffer
                      : LogsScreen._buffer.where((e) {
                          final q = _searchQuery.toLowerCase();
                          return e.message.toLowerCase().contains(q) ||
                              e.timecode.toLowerCase().contains(q);
                        }).toList();

                  if (filteredLogs.isEmpty) {
                    return const Center(
                      child: Text('No logs match your search.'),
                    );
                  }

                  return Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    interactive: true, // Makes the scrollbar draggable
                    thickness: 10,
                    radius: Radius.circular(6),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, i) {
                        final entry = filteredLogs[i];
                        return _LogTile(entry: entry);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton(
              tooltip: 'Jump to bottom',
              mini: true,
              onPressed: _scrollToBottom,
              child: const Icon(Icons.arrow_downward_rounded),
            )
          : null,
    );
  }
}

/// Visual representation of a single [LogEntry].
/// Shows the timecode at the top, and the actual log message below it.
class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});
  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.timecode.isNotEmpty)
            Text(
              entry.timecode,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          if (entry.message.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.message,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }
}
