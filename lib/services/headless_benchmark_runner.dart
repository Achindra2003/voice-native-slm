// ignore_for_file: avoid_print
//
// Headless Benchmark Runner — crash-resistant with incremental saving.
// Runs the dataset across each model with memory management, saving results
// after every command so a crash loses no data.
//
// One spoken input, two architectures, fed from the SAME recorded audio clips
// in benchmark_audio/ (record them once via the Record screen):
//   pipeline — Phase 1 runs real Whisper STT over each clip to produce a
//              transcript (with genuine ASR errors, measured WER); Phase 2 feeds
//              that transcript to each text model (Specialist / Liquid / Transformer).
//   direct   — Phase 3 feeds the raw PCM of the same clip straight to the
//              audio-native model (Gemma 4 E2B), with no ASR stage.
//
// Usage: HeadlessBenchmarkRunner.run()  (from Flutter)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'benchmark_service.dart';
import 'wer.dart';
import '../models/agent_model.dart' show kWhisperModelId;
import '../native/cactus_engine.dart';
import '../native/model_store.dart';
import '../tools/agent_tools.dart';

/// One clip's real Whisper transcription plus its measured WER vs the reference.
class _Transcript {
  final int index;
  final String command; // reference (ground-truth) command
  final String transcript; // what Whisper heard
  final double wer;

  _Transcript(this.index, this.command, this.transcript, this.wer);

  Map<String, dynamic> toJson() => {
        'index': index,
        'command': command,
        'transcript': transcript,
        'wer': wer,
      };

  factory _Transcript.fromJson(Map<String, dynamic> j) => _Transcript(
        j['index'] as int,
        j['command'] as String,
        j['transcript'] as String,
        (j['wer'] as num).toDouble(),
      );
}

class HeadlessBenchmarkRunner {
  // File names are suffixed by [condition] so the multilingual pilot
  // ('codeswitch') never overwrites the English baseline's ('en') results —
  // 'en' keeps the original unsuffixed names for backward compatibility.
  // All output paths are anchored to ModelStore.resultsDir() (an absolute,
  // adb-pullable external files dir). A bare relative 'results/...' has no
  // writable working directory on Android and throws PathNotFoundException.
  static Future<String> _resultsFile(String condition) async =>
      '${await ModelStore.resultsDir()}/headless_benchmark_results'
      '${condition == 'en' ? '' : '_$condition'}.csv';
  static Future<String> _jsonResultsFile(String condition) async =>
      '${await ModelStore.resultsDir()}/headless_benchmark_results'
      '${condition == 'en' ? '' : '_$condition'}.json';
  static Future<String> _progressFile(String condition) async =>
      '${await ModelStore.resultsDir()}/benchmark_progress'
      '${condition == 'en' ? '' : '_$condition'}.json';
  static Future<String> _transcriptsFile(String condition) async =>
      '${await ModelStore.resultsDir()}/transcripts'
      '${condition == 'en' ? '' : '_$condition'}.json';
  static Future<String> _summaryFile(String condition) async =>
      '${await ModelStore.resultsDir()}/headless_benchmark_summary'
      '${condition == 'en' ? '' : '_$condition'}.md';

  static const int cleanupInterval = 5;
  static const int delayBetweenCommandsMs = 500;

  /// Full paper model set. Folder name on device = model id (push with
  /// `adb push <weights-cq4-dir> .../models/<id>`).
  static final List<Map<String, dynamic>> availableModels = [
    // ── Specialist ────────────────────────────────────────────────────────────
    // functiongemma-270m REMOVED from the run set (2026-07-08): it fails
    // cactus_init on the v2.0 engine (proven, byte-identical re-transpile),
    // so including it made every full run end in a thrown fatal-failure.
    // lfm2-1.2b-tool is its replacement (bundle pushed 2026-07-09).
    {'id': 'lfm2-1.2b-tool', 'name': 'LFM2 1.2B Tool', 'type': 'specialist'},
    // ── Liquid / LFM2 ────────────────────────────────────────────────────────
    {'id': 'lfm2-350m',   'name': 'LFM2 350M',   'type': 'liquid'},
    {'id': 'lfm2.5-350m', 'name': 'LFM2.5 350M', 'type': 'liquid'},
    {'id': 'lfm2-700m',   'name': 'LFM2 700M',   'type': 'liquid'},
    {'id': 'lfm2-1.2b',   'name': 'LFM2 1.2B',   'type': 'liquid'},
    {'id': 'lfm2.5-1.2b', 'name': 'LFM2.5 1.2B', 'type': 'liquid'},
    // ── Transformer (Qwen3 / Qwen3.5) ────────────────────────────────────────
    {'id': 'qwen3-0.6',   'name': 'Qwen3 0.6B',   'type': 'generalist'},
    {'id': 'qwen3-1.7',   'name': 'Qwen3 1.7B',   'type': 'generalist'},
    {'id': 'qwen3.5-0.8', 'name': 'Qwen3.5 0.8B', 'type': 'generalist'},
    {'id': 'qwen3.5-2b',  'name': 'Qwen3.5 2B',   'type': 'generalist'},
    // ── Audio-native (Gemma 3n dropped — Cactus cannot transpile it) ────────
    {'id': 'gemma-4-e2b', 'name': 'Gemma 4 E2B', 'type': 'audio'},
  ];

  static Future<Map<String, dynamic>> loadProgress(
      [String condition = 'en']) async {
    final file = File(await _progressFile(condition));
    if (await file.exists()) {
      final content = await file.readAsString();
      return jsonDecode(content);
    }
    return {'completed': <String>[], 'lastModel': null, 'lastCommandIndex': -1};
  }

  static Future<void> saveProgress(Map<String, dynamic> progress,
      [String condition = 'en']) async {
    final file = File(await _progressFile(condition));
    await file.writeAsString(jsonEncode(progress));
  }

  static Future<void> saveResultIncremental(BenchmarkResult result,
      [String condition = 'en']) async {
    final file = File(await _resultsFile(condition));
    final exists = await file.exists();
    final sink = file.openWrite(mode: FileMode.append);
    if (!exists) sink.writeln(BenchmarkResult.csvHeader());
    sink.writeln(result.toCsvRow());
    await sink.close();
    await _appendToJsonResults(result, condition);
  }

  static Future<void> _appendToJsonResults(BenchmarkResult result,
      String condition) async {
    final file = File(await _jsonResultsFile(condition));
    List<dynamic> results = [];
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) results = jsonDecode(content);
    }
    results.add(result.toJson());
    await file.writeAsString(jsonEncode(results));
  }

  static Future<void> _saveTranscripts(
      List<_Transcript> ts, String condition) async {
    await File(await _transcriptsFile(condition))
        .writeAsString(jsonEncode(ts.map((t) => t.toJson()).toList()));
  }

  /// Reuse a prior transcription pass if it covers at least [need] clips, so a
  /// crash mid-benchmark doesn't force re-running Whisper over every clip.
  static Future<List<_Transcript>?> _loadTranscripts(
      int need, String condition) async {
    final file = File(await _transcriptsFile(condition));
    if (!await file.exists()) return null;
    final raw = jsonDecode(await file.readAsString()) as List<dynamic>;
    if (raw.length < need) return null;
    return raw
        .map((e) => _Transcript.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Phase 1 — run real Whisper STT over the recorded clips, returning one
  /// transcript + measured WER per command. Throws with actionable guidance if
  /// the Whisper bundle or the audio clips are missing.
  static Future<List<_Transcript>> _transcribeAll(
    List<TestCase> testCases,
    String audioDir,
    String condition,
    void Function(String) log,
  ) async {
    final cached = await _loadTranscripts(testCases.length, condition);
    if (cached != null) {
      log('Reusing cached transcripts for ${cached.length} clips '
          '(delete ${await _transcriptsFile(condition)} to re-run Whisper)');
      return cached.take(testCases.length).toList();
    }

    final whisperPath = await ModelStore.modelDir(kWhisperModelId);
    if (!await ModelStore.isStaged(kWhisperModelId)) {
      throw Exception(
        'Whisper STT model "$kWhisperModelId" not staged at $whisperPath. '
        'Transpile a Whisper bundle to Cactus format and '
        'adb push it there before running the pipeline arm.',
      );
    }

    log('');
    log('── Phase 1: Whisper STT over ${testCases.length} clips ──');
    final stt = CactusEngine();
    await stt.init(whisperPath);

    final transcripts = <_Transcript>[];
    try {
      for (var i = 0; i < testCases.length; i++) {
        final wav = File('$audioDir/$i.wav');
        if (!await wav.exists()) {
          throw Exception(
            'Audio clip missing: benchmark_audio/$i.wav — record all '
            '${testCases.length} commands via the Record screen first.',
          );
        }
        final heard = (await stt.transcribe(wav.path)).trim();
        final wer = Wer.compute(testCases[i].command, heard);
        transcripts.add(_Transcript(i, testCases[i].command, heard, wer));
        log('  [$i] "${testCases[i].command}" → "$heard" (WER ${wer.toStringAsFixed(2)})');
        await _saveTranscripts(transcripts, condition); // incremental, crash-safe
      }
    } finally {
      stt.dispose();
      await Future.delayed(const Duration(seconds: 2));
    }

    final meanWer = transcripts.isEmpty
        ? 0.0
        : transcripts.map((t) => t.wer).reduce((a, b) => a + b) /
            transcripts.length;
    log('✓ Transcribed ${transcripts.length} clips, mean WER ${meanWer.toStringAsFixed(3)}');
    return transcripts;
  }

  static Future<void> run({
    List<String>? modelIds,
    int? commandsPerModel,
    Function(String)? onProgress,
    String datasetPath = 'assets/realistic_dataset.json',
    String condition = 'en',
    String? audioCondition,
  }) async {
    final models =
        modelIds ?? availableModels.map((m) => m['id'] as String).toList();
    final commandLimit = commandsPerModel ?? 30;

    void log(String message) {
      print('[${DateTime.now().toIso8601String()}] $message');
      onProgress?.call(message);
    }

    log('=== Headless Benchmark Runner ===');
    log('Condition: $condition');
    log('Models: ${models.join(", ")}');
    log('Commands per model: $commandLimit');

    log('Loading test dataset ($datasetPath)...');
    final testCases = await BenchmarkDataset.load(datasetPath);
    log('Loaded ${testCases.length} test cases');
    final limitedTestCases = testCases.take(commandLimit).toList();

    // The recorded clips feed BOTH arms: Whisper (pipeline) and Gemma (direct).
    // Each condition gets its own audio subdir so e.g. the code-switched
    // pilot's clips never overwrite the English baseline's. [audioCondition]
    // lets a run reuse another condition's clips (e.g. the smoke test reuses
    // the real English clips while writing to isolated result files).
    final audioDir =
        await ModelStore.audioDir(condition: audioCondition ?? condition);

    // Phase 1 — transcribe with real Whisper, but only if a text (pipeline)
    // model is actually in this run.
    final hasPipelineModel = models.any((id) =>
        availableModels.firstWhere((m) => m['id'] == id,
            orElse: () => {'type': 'audio'})['type'] !=
        'audio');
    List<_Transcript> transcripts = const [];
    if (hasPipelineModel) {
      transcripts =
          await _transcribeAll(limitedTestCases, audioDir, condition, log);
    }

    final progress = await loadProgress(condition);
    final completedTests = (progress['completed'] as List).cast<String>();
    log('Resuming: ${completedTests.length} tests already completed');

    final tools = buildAgentTools();
    int totalTests = 0;
    int successfulTests = 0;
    // Models that failed to load/run at all (vs. per-command errors, which are
    // recorded as result rows). Surfaced as a thrown error at the end so a
    // smoke test can't report success when an arm never ran.
    final fatalModels = <String, String>{};

    for (final modelId in models) {
      final modelInfo = availableModels.firstWhere((m) => m['id'] == modelId);
      final modelName = modelInfo['name'] as String;
      final modelType = modelInfo['type'] as String;
      final isAudioNative = modelType == 'audio';

      log('');
      log('╔════════════════════════════════════════════════════════════╗');
      log('║ Starting: $modelName ($modelType)');
      log('╚════════════════════════════════════════════════════════════╝');

      CactusEngine? lm;
      try {
        final modelPath = await ModelStore.modelDir(modelId);
        if (!await ModelStore.isStaged(modelId)) {
          throw Exception(
            'Model "$modelId" not staged at $modelPath '
            '(adb push <model_dir> $modelPath)',
          );
        }
        lm = CactusEngine();
        await lm.init(modelPath);
        log('✓ Model loaded');

        final systemPrompt = systemPromptFor(modelType);

        for (int i = 0; i < limitedTestCases.length; i++) {
          final testCase = limitedTestCases[i];
          final testId = '${modelId}_$i';

          if (completedTests.contains(testId)) {
            log('  Skipping ${i + 1}/$commandLimit (already done)');
            continue;
          }

          log('  Test ${i + 1}/$commandLimit: "${testCase.command}"');

          final startTime = DateTime.now();
          BenchmarkResult? result;

          try {
            CactusCompletionResult response;

            if (isAudioNative) {
              // Load pre-recorded WAV, strip 44-byte RIFF header → raw int16 PCM.
              final wavFile = File('$audioDir/$i.wav');
              if (!await wavFile.exists()) {
                throw Exception(
                  'Audio clip missing: benchmark_audio/$i.wav — '
                  'use the Record screen to capture it first.',
                );
              }
              final wavBytes = await wavFile.readAsBytes();
              final pcm = _pcmFromWav(wavBytes);

              log('  [audio] ${pcm.length} bytes PCM from clip $i');
              // The engine attaches the PCM's audio soft tokens to the LAST
              // user message (complete.cpp prepare_prompt, GEMMA4 path) and
              // silently drops the audio if no user message exists — a
              // system-only conversation makes the model reply "What would
              // you like me to do?". The user turn's text stays empty so the
              // model's only source of intent is the audio itself.
              response = await lm.complete(
                messages: [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': ''},
                ],
                tools: tools,
                maxTokens: 100,
                temperature: 0.1,
                pcmBytes: pcm,
              );
            } else {
              // Pipeline arm: feed the real Whisper transcript for this clip.
              response = await lm.complete(
                messages: [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': transcripts[i].transcript},
                ],
                tools: tools,
                maxTokens: 100,
                temperature: 0.1,
              );
            }

            final latency =
                DateTime.now().difference(startTime).inMilliseconds;
            final effectiveWer =
                isAudioNative ? 0.0 : transcripts[i].wer;
            final effectiveTranscription =
                isAudioNative ? testCase.command : transcripts[i].transcript;
            final inputMode = isAudioNative ? 'direct' : 'pipeline';

            if (!response.success || response.toolCalls.isEmpty) {
              // Surface what the model actually produced — without this, a
              // "No tool calls generated" row is indistinguishable between a
              // model that answered in prose, emitted malformed JSON, or said
              // nothing, which is exactly the error-taxonomy distinction the
              // paper needs.
              final raw = response.response.trim();
              final rawSnippet =
                  raw.length > 300 ? '${raw.substring(0, 300)}…' : raw;
              log('    [no-tool-call] raw response (${raw.length} ch): '
                  '"$rawSnippet"'
                  '${response.error != null ? ' | err: ${response.error}' : ''}');
              result = BenchmarkResult(
                modelName: modelName,
                command: testCase.command,
                transcribedText: effectiveTranscription,
                category: testCase.category,
                expectedFunction: testCase.expectedFunction,
                expectedParams: testCase.expectedParameters,
                success: false,
                correctFunction: false,
                correctParams: false,
                latencyMs: latency,
                // Keep what the model actually said: the error taxonomy needs
                // to tell prose answers from empty/malformed output, and OEM
                // logcat rotation makes the log line above unrecoverable.
                error: 'No tool calls generated; raw: "$rawSnippet"',
                wordErrorRate: effectiveWer,
                inputMode: inputMode,
                condition: condition,
              );
            } else {
              final toolCall = response.toolCalls.first;
              final correctFunction =
                  toolCall.name == testCase.expectedFunction;
              final correctParams = _compareParams(
                toolCall.arguments,
                testCase.expectedParameters,
              );
              result = BenchmarkResult(
                modelName: modelName,
                command: testCase.command,
                transcribedText: effectiveTranscription,
                category: testCase.category,
                expectedFunction: testCase.expectedFunction,
                expectedParams: testCase.expectedParameters,
                actualFunction: toolCall.name,
                actualParams: toolCall.arguments,
                success: correctFunction && correctParams,
                correctFunction: correctFunction,
                correctParams: correctParams,
                latencyMs: latency,
                wordErrorRate: effectiveWer,
                inputMode: inputMode,
                condition: condition,
              );
              if (result.success) successfulTests++;
            }
          } catch (e) {
            final latency =
                DateTime.now().difference(startTime).inMilliseconds;
            log('    ❌ Error: $e');
            result = BenchmarkResult(
              modelName: modelName,
              command: testCase.command,
              transcribedText:
                  isAudioNative ? testCase.command : transcripts[i].transcript,
              category: testCase.category,
              expectedFunction: testCase.expectedFunction,
              expectedParams: testCase.expectedParameters,
              success: false,
              correctFunction: false,
              correctParams: false,
              latencyMs: latency,
              error: e.toString(),
              wordErrorRate: isAudioNative ? 0.0 : transcripts[i].wer,
              inputMode: isAudioNative ? 'direct' : 'pipeline',
              condition: condition,
            );
          }

          await saveResultIncremental(result, condition);
          totalTests++;
          completedTests.add(testId);
          await saveProgress({
            'completed': completedTests,
            'lastModel': modelId,
            'lastCommandIndex': i,
            'timestamp': DateTime.now().toIso8601String(),
          }, condition);
          log(
            '    ${result.success ? "✓" : "✗"} '
            '${result.actualFunction ?? "none"} | ${result.latencyMs}ms',
          );

          if ((i + 1) % cleanupInterval == 0) {
            await Future.delayed(
                Duration(milliseconds: delayBetweenCommandsMs * 2));
          } else {
            await Future.delayed(
                Duration(milliseconds: delayBetweenCommandsMs));
          }
        }

        log('✓ Completed $modelName');
      } catch (e) {
        log('❌ Fatal error with $modelName: $e');
        fatalModels[modelName] = e.toString();
      } finally {
        if (lm != null) {
          try {
            lm.dispose();
          } catch (_) {}
        }
        lm = null;
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    log('');
    log('╔════════════════════════════════════════════════════════════╗');
    log('║ BENCHMARK COMPLETE');
    log('╠════════════════════════════════════════════════════════════╣');
    log('║ Total: $totalTests  Successful: $successfulTests '
        '(${totalTests > 0 ? (successfulTests / totalTests * 100).toStringAsFixed(1) : 0}%)');
    log('║ Results: ${await _resultsFile(condition)}');
    log('╚════════════════════════════════════════════════════════════╝');

    await _generateFinalSummary(condition);

    if (fatalModels.isNotEmpty) {
      throw Exception(
        'Completed with fatal model failures (results for other models are '
        'saved): ${fatalModels.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
      );
    }
  }

  /// Extract raw PCM samples from a WAV file by locating the `data` chunk,
  /// instead of assuming a fixed 44-byte header. The record package can emit
  /// extra chunks (LIST/fact) before `data`; skipping a hardcoded 44 bytes
  /// would then feed header bytes to the model as audio and corrupt the clip.
  static Uint8List _pcmFromWav(Uint8List wav) {
    // Needs at least "RIFF"(4)+size(4)+"WAVE"(4) then one chunk header (8).
    if (wav.length < 44 ||
        wav[0] != 0x52 || // R
        wav[1] != 0x49 || // I
        wav[2] != 0x46 || // F
        wav[3] != 0x46) {
      // Not a RIFF/WAVE header — assume it is already headerless PCM.
      return wav;
    }
    var off = 12; // skip "RIFF" + chunkSize + "WAVE"
    while (off + 8 <= wav.length) {
      final id = String.fromCharCodes(wav, off, off + 4);
      final size = wav[off + 4] |
          (wav[off + 5] << 8) |
          (wav[off + 6] << 16) |
          (wav[off + 7] << 24);
      final dataStart = off + 8;
      if (id == 'data') {
        final end =
            (dataStart + size <= wav.length) ? dataStart + size : wav.length;
        return Uint8List.sublistView(wav, dataStart, end);
      }
      // Chunks are word-aligned (pad byte if size is odd).
      off = dataStart + size + (size.isOdd ? 1 : 0);
    }
    // Fallback: no data chunk found — use the classic 44-byte offset.
    return Uint8List.sublistView(wav, 44);
  }

  static bool _compareParams(
    Map<String, dynamic> actual,
    Map<String, dynamic> expected,
  ) {
    for (final key in expected.keys) {
      if (!actual.containsKey(key)) return false;
      final expectedVal = expected[key];
      final actualVal = actual[key];
      if (expectedVal is num && actualVal is num) {
        final diff = (expectedVal - actualVal).abs();
        if (diff > expectedVal * 0.1 && diff > 5) return false;
      } else if (expectedVal is String && actualVal is String) {
        if (expectedVal.toLowerCase() != actualVal.toLowerCase()) return false;
      } else {
        if (expectedVal != actualVal) return false;
      }
    }
    return true;
  }

  static Future<void> _generateFinalSummary([String condition = 'en']) async {
    final resultsFile = File(await _jsonResultsFile(condition));
    if (!await resultsFile.exists()) return;

    final content = await resultsFile.readAsString();
    final List<dynamic> rawResults = jsonDecode(content);
    final results = rawResults
        .map(
          (r) => BenchmarkResult(
            modelName: r['model'],
            command: r['command'],
            transcribedText: r['transcribed_text'],
            category: r['category'],
            expectedFunction: r['expected_function'],
            expectedParams: jsonDecode(r['expected_params']),
            actualFunction:
                r['actual_function'].isEmpty ? null : r['actual_function'],
            actualParams: r['actual_params'].isEmpty
                ? null
                : jsonDecode(r['actual_params']),
            success: r['success'],
            correctFunction: r['correct_function'],
            correctParams: r['correct_params'],
            latencyMs: r['latency_ms'],
            error: r['error'].isEmpty ? null : r['error'],
            wordErrorRate: r['word_error_rate'],
            inputMode: r['input_mode'] as String? ?? 'pipeline',
            condition: r['condition'] as String? ?? 'en',
          ),
        )
        .toList();

    final summary = StringBuffer();
    summary.writeln('# Headless Benchmark Summary');
    summary.writeln('Condition: $condition');
    summary.writeln('Generated: ${DateTime.now()}');
    summary.writeln('Total Tests: ${results.length}\n');

    final byModel = <String, List<BenchmarkResult>>{};
    for (final result in results) {
      byModel.putIfAbsent(result.modelName, () => []).add(result);
    }

    summary.writeln('## Model Performance\n');
    summary.writeln(
      '| Model | Input Mode | Tests | Success Rate | Function Acc | Param Acc | Avg Latency |',
    );
    summary.writeln(
      '|-------|------------|-------|--------------|--------------|-----------|-------------|',
    );

    for (final entry in byModel.entries) {
      final m = entry.value;
      final success = m.where((r) => r.success).length;
      final correctFn = m.where((r) => r.correctFunction).length;
      final correctParam = m.where((r) => r.correctParams).length;
      final avgLatency =
          m.map((r) => r.latencyMs).reduce((a, b) => a + b) / m.length;
      final mode = m.first.inputMode;
      summary.writeln(
        '| ${entry.key} | $mode | ${m.length} | '
        '${(success / m.length * 100).toStringAsFixed(1)}% | '
        '${(correctFn / m.length * 100).toStringAsFixed(1)}% | '
        '${(correctParam / m.length * 100).toStringAsFixed(1)}% | '
        '${avgLatency.toStringAsFixed(0)}ms |',
      );
    }

    final pipelineResults =
        results.where((r) => r.inputMode == 'pipeline').toList();
    final directResults =
        results.where((r) => r.inputMode == 'direct').toList();

    summary.writeln('\n## Architecture Comparison: Pipeline vs Unified\n');
    if (pipelineResults.isNotEmpty) {
      final pSuccess = pipelineResults.where((r) => r.success).length;
      final pLatency = pipelineResults
              .map((r) => r.latencyMs)
              .reduce((a, b) => a + b) /
          pipelineResults.length;
      summary.writeln('**Pipeline (Whisper STT + SLM):**');
      summary.writeln(
          '- Models tested: ${pipelineResults.map((r) => r.modelName).toSet().length}');
      summary.writeln(
          '- Overall success rate: ${(pSuccess / pipelineResults.length * 100).toStringAsFixed(1)}%');
      summary.writeln('- Mean latency: ${pLatency.toStringAsFixed(0)}ms');
      summary.writeln(
          '- Mean WER: ${(pipelineResults.map((r) => r.wordErrorRate).reduce((a, b) => a + b) / pipelineResults.length).toStringAsFixed(3)}\n');
    }
    if (directResults.isNotEmpty) {
      final dSuccess = directResults.where((r) => r.success).length;
      final dLatency =
          directResults.map((r) => r.latencyMs).reduce((a, b) => a + b) /
              directResults.length;
      summary.writeln('**Unified Audio-Native (no STT stage):**');
      summary.writeln(
          '- Models tested: ${directResults.map((r) => r.modelName).toSet().length}');
      summary.writeln(
          '- Overall success rate: ${(dSuccess / directResults.length * 100).toStringAsFixed(1)}%');
      summary.writeln('- Mean latency: ${dLatency.toStringAsFixed(0)}ms');
      summary.writeln('- Input WER: 0.000 (direct audio understanding)\n');
      if (pipelineResults.isNotEmpty) {
        final pSuccess = pipelineResults.where((r) => r.success).length;
        final gain =
            (directResults.where((r) => r.success).length / directResults.length) -
                (pSuccess / pipelineResults.length);
        summary.writeln(
          '> **Novel Finding:** Unified architecture '
          '${gain >= 0 ? "outperforms" : "underperforms"} pipeline by '
          '${(gain.abs() * 100).toStringAsFixed(1)}pp — empirical evidence '
          '${gain >= 0 ? "for" : "against"} eliminating the ASR stage on mid-range devices.',
        );
      }
    }

    // ── Semantic Resilience: do models recover when Whisper mis-hears? ──
    // Defined only on the pipeline arm (the direct arm has no transcript to
    // corrupt). "Recovery rate" = of commands Whisper transcribed with errors
    // (WER > 0), the fraction the model still mapped to the correct call.
    if (pipelineResults.isNotEmpty) {
      final clean = pipelineResults.where((r) => r.wordErrorRate == 0).toList();
      final noisy = pipelineResults.where((r) => r.wordErrorRate > 0).toList();

      summary.writeln('\n## Semantic Resilience (pipeline arm)\n');
      summary.writeln(
          'Clean = WER 0 transcripts; Noisy = WER > 0 (real Whisper errors). '
          'Resilience gap = how much accuracy drops on mis-heard input; '
          'recovery rate = accuracy on the mis-heard subset.\n');
      summary.writeln(
          '| Model | Clean acc | Noisy acc | Resilience gap | Recovery rate (n) |');
      summary.writeln(
          '|-------|-----------|-----------|----------------|-------------------|');
      double rate(List<BenchmarkResult> rs) =>
          rs.isEmpty ? 0.0 : rs.where((r) => r.success).length / rs.length;
      for (final name in pipelineResults.map((r) => r.modelName).toSet()) {
        final mClean = clean.where((r) => r.modelName == name).toList();
        final mNoisy = noisy.where((r) => r.modelName == name).toList();
        final cAcc = rate(mClean), nAcc = rate(mNoisy);
        final recovered = mNoisy.where((r) => r.success).length;
        final recoveryCell = mNoisy.isEmpty
            ? '—'
            : '${(nAcc * 100).toStringAsFixed(1)}% ($recovered/${mNoisy.length})';
        summary.writeln('| $name | ${(cAcc * 100).toStringAsFixed(1)}% | '
            '${(nAcc * 100).toStringAsFixed(1)}% | '
            '${((cAcc - nAcc) * 100).toStringAsFixed(1)}pp | $recoveryCell |');
      }

      // Dose-response: accuracy as WER rises (all pipeline models pooled).
      summary.writeln('\n### Accuracy vs WER band (pooled pipeline models)\n');
      summary.writeln('| WER band | Commands | Success rate |');
      summary.writeln('|----------|----------|--------------|');
      const labels = ['0 (clean)', '0–25%', '25–50%', '>50%'];
      bool inBand(double w, int b) => switch (b) {
            0 => w == 0,
            1 => w > 0 && w <= 0.25,
            2 => w > 0.25 && w <= 0.5,
            _ => w > 0.5,
          };
      for (var b = 0; b < labels.length; b++) {
        final rows =
            pipelineResults.where((r) => inBand(r.wordErrorRate, b)).toList();
        if (rows.isEmpty) continue;
        final s = rows.where((r) => r.success).length;
        summary.writeln('| ${labels[b]} | ${rows.length} | '
            '${(s / rows.length * 100).toStringAsFixed(1)}% |');
      }
    }

    final summaryFile = File(await _summaryFile(condition));
    await summaryFile.writeAsString(summary.toString());
    print('\n✓ Summary saved: ${summaryFile.path}');
  }
}

void main(List<String> args) async {
  List<String>? models;
  int? commandsPerModel;
  String datasetPath = 'assets/realistic_dataset.json';
  String condition = 'en';
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--models' && i + 1 < args.length) {
      models = args[i + 1].split(',');
    } else if (args[i] == '--commands' && i + 1 < args.length) {
      commandsPerModel = int.tryParse(args[i + 1]);
    } else if (args[i] == '--dataset' && i + 1 < args.length) {
      datasetPath = args[i + 1];
    } else if (args[i] == '--condition' && i + 1 < args.length) {
      condition = args[i + 1];
    }
  }
  await HeadlessBenchmarkRunner.run(
    modelIds: models,
    commandsPerModel: commandsPerModel,
    datasetPath: datasetPath,
    condition: condition,
  );
  exit(0);
}
