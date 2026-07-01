import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/errors/app_exceptions.dart';
import '../../core/utils/path_helpers.dart';
import '../../data/models/encode_task.dart';
import '../../data/models/media_info.dart';
import '../../data/services/media_probe_service.dart';
import '../../data/services/permission_service.dart';
import '../../providers/preset_provider.dart';
import '../../providers/queue_provider.dart';
import '../preview/preview_screen.dart';

/// Source + preset selection screen. Validates inputs before enqueue.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  String? _sourcePath;
  MediaInfo? _mediaInfo;
  String? _selectedPresetId;
  bool _probing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetProvider);
    _selectedPresetId ??= presets.isNotEmpty ? presets.first.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('New Encode')),
      body: _error != null
          ? _ErrorView(message: _error!, onRetry: _clearError)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SourcePicker(
                    path: _sourcePath,
                    probing: _probing,
                    onPick: _pickSource,
                  ),
                  if (_mediaInfo != null) ...[
                    const SizedBox(height: 12),
                    _MediaInfoCard(info: _mediaInfo!),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Preset',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPresetId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      for (final preset in presets)
                        DropdownMenuItem(
                          value: preset.id,
                          child: Text('${preset.name} (${preset.category})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _selectedPresetId = v),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (_mediaInfo != null)
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Preview'),
                            onPressed: _openPreview,
                          ),
                        ),
                      // Removed invalid curly braces that turned this into a Set
                      if (_mediaInfo != null) const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.queue),
                          label: const Text('Add to Queue'),
                          onPressed: _canSubmit ? _submit : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  bool get _canSubmit =>
      _sourcePath != null && _selectedPresetId != null && !_probing;

  Future<void> _pickSource() async {
    setState(() {
      _probing = true;
      _error = null;
    });
    try {
      await ref.read(permissionServiceProvider).requireMediaRead();
      final result = await FilePicker.pickFile(type: FileType.video);
      if (result == null || result.path == null) {
        setState(() => _probing = false);
        return;
      }
      final path = result.path!;
      final info = await ref.read(mediaProbeServiceProvider).probe(path);
      setState(() {
        _sourcePath = path;
        _mediaInfo = info;
        _probing = false;
      });
    } on AppException catch (e) {
      setState(() {
        _error = e.userMessage;
        _probing = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not load source video.';
        _probing = false;
      });
    }
  }

  void _openPreview() {
    if (_sourcePath == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreviewScreen(path: _sourcePath!)),
    );
  }

  Future<void> _submit() async {
    final sourcePath = _sourcePath;
    final presetId = _selectedPresetId;
    if (sourcePath == null || presetId == null) {
      return;
    }

    final preset = ref.read(presetProvider.notifier).byId(presetId);
    if (preset == null) {
      setState(() => _error = 'Selected preset is missing.');
      return;
    }

    final baseName = PathHelpers.sanitizeFileName(
      p.basenameWithoutExtension(sourcePath),
    );
    final outDir = p.dirname(sourcePath);
    final outputPath = PathHelpers.uniqueOutputPath(
      directory: outDir,
      baseName: '${baseName}_videocode',
      extension: preset.fileExtension,
    );

    final task = EncodeTask(
      id: 'task_${DateTime.now().millisecondsSinceEpoch}',
      sourcePath: sourcePath,
      sourceName: p.basename(sourcePath),
      outputPath: outputPath,
      presetId: presetId,
      createdAt: DateTime.now(),
      totalDurationSeconds: _mediaInfo?.duration?.inSeconds.toDouble() ?? 0,
    );

    await ref.read(queueProvider.notifier).enqueue(task);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _clearError() => setState(() => _error = null);
}

/// Source video selector: opens the platform file picker (SAF on Android).
class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.path,
    required this.probing,
    required this.onPick,
  });

  final String? path;
  final bool probing;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: probing ? null : onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              probing
                  ? Icons.hourglass_top
                  : (path == null ? Icons.folder_open : Icons.video_file),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                probing
                    ? 'Reading source…'
                    : (path == null
                          ? 'Tap to select a source video'
                          : path!.split('/').last),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only metadata summary card shown after probing the source.
class _MediaInfoCard extends StatelessWidget {
  const _MediaInfoCard({required this.info});
  final MediaInfo info;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Resolution', info.resolutionLabel),
      ('Duration', info.durationLabel),
      ('Video codec', info.videoCodec ?? '—'),
      ('Audio codec', info.audioCodec ?? '—'),
      ('Container', info.container ?? '—'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final (k, v) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(k, style: Theme.of(context).textTheme.bodySmall),
                    Text(v, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Inline error UI replacing the editor body when a hard error occurs.
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Dismiss')),
          ],
        ),
      ),
    );
  }
}
