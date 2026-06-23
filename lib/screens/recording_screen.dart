import 'dart:io';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../native/model_store.dart';
import '../services/benchmark_service.dart';

/// Records the 30 benchmark commands as 16 kHz mono WAV clips for the
/// audio-native pipeline. Files are saved to
/// `<externalFilesDir>/benchmark_audio/<index>.wav` and read by the
/// benchmark runner without re-recording.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final AudioRecorder _recorder = AudioRecorder();

  List<TestCase> _commands = [];
  List<bool> _recorded = [];
  String? _audioDir;

  int _recordingIndex = -1;
  bool _isRecording = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final cases = await BenchmarkDataset.load();
    final dir = await ModelStore.audioDir();
    final limited = cases.take(30).toList();
    final recordedFlags = List.generate(
        limited.length, (i) => File('$dir/$i.wav').existsSync());

    if (!mounted) return;
    setState(() {
      _commands = limited;
      _recorded = recordedFlags;
      _audioDir = dir;
      _loading = false;
    });
  }

  Future<void> _startRecording(int index) async {
    if (_isRecording || _audioDir == null) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    final path = '$_audioDir/$index.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _recordingIndex = index;
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    await _recorder.stop();
    final idx = _recordingIndex;
    setState(() {
      _isRecording = false;
      _recordingIndex = -1;
      if (idx >= 0 && idx < _recorded.length) _recorded[idx] = true;
    });
  }

  @override
  void dispose() {
    if (_isRecording) _recorder.stop();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordedCount = _recorded.where((r) => r).length;
    final total = _commands.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text('Record Commands ($recordedCount/$total)'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : recordedCount / total,
                    minHeight: 6,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                    'Tap the mic icon next to each command, speak it clearly, '
                    'then tap stop. Saves as 16 kHz mono WAV.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_isRecording)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fiber_manual_record,
                            color: Colors.red, size: 14),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Recording command ${_recordingIndex + 1}: '
                            '"${_commands[_recordingIndex].command}"',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: _stopRecording,
                          child: const Text('STOP'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: ListView.separated(
                    itemCount: _commands.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (context, i) {
                      final cmd = _commands[i];
                      final isThisRecording =
                          _isRecording && _recordingIndex == i;
                      final isDone = _recorded[i];

                      return ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: isDone
                              ? Colors.green
                              : isThisRecording
                                  ? Colors.red
                                  : Colors.grey.shade300,
                          child: isDone
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 16)
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isThisRecording
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        title: Text(
                          cmd.command,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          cmd.category,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: isThisRecording
                            ? IconButton(
                                icon: const Icon(Icons.stop_circle,
                                    color: Colors.red, size: 32),
                                onPressed: _stopRecording,
                              )
                            : IconButton(
                                icon: Icon(
                                  isDone ? Icons.replay : Icons.mic,
                                  color: _isRecording
                                      ? Colors.grey
                                      : Colors.deepOrange,
                                ),
                                onPressed: _isRecording
                                    ? null
                                    : () => _startRecording(i),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _isRecording
          ? FloatingActionButton.extended(
              backgroundColor: Colors.red,
              onPressed: _stopRecording,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Recording'),
            )
          : recordedCount == total && total > 0
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.green,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.check),
                  label: const Text('All Done'),
                )
              : null,
    );
  }
}
