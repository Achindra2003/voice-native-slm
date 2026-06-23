// ignore_for_file: avoid_print
//
// Headless Benchmark Runner — crash-resistant with incremental saving.
// Runs the dataset across each model with memory management, saving results
// after every command so a crash loses no data.
//
// Two pipelines are benchmarked:
//   pipeline — text models (Specialist / Liquid / Transformer): receives the
//              simulated Whisper transcription (with WER noise from dataset).
//   direct   — audio-native models (LFM2-audio, Gemma 4): receives raw PCM
//              bytes from pre-recorded WAV clips in benchmark_audio/.
//
// Usage: HeadlessBenchmarkRunner.run()  (from Flutter)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'benchmark_service.dart';
import '../native/cactus_engine.dart';
import '../native/model_store.dart';
import '../tools/agent_tools.dart';

class HeadlessBenchmarkRunner {
  static const String resultsFile = 'results/headless_benchmark_results.csv';
  static const String jsonResultsFile =
      'results/headless_benchmark_results.json';
  static const String progressFile = 'results/benchmark_progress.json';

  static const int cleanupInterval = 5;
  static const int delayBetweenCommandsMs = 500;

  /// Full paper model set. Folder name on device = model id (push with
  /// `adb push <weights-cq4-dir> .../models/<id>`).
  static final List<Map<String, dynamic>> availableModels = [
    // ── Specialist ────────────────────────────────────────────────────────────
    {'id': 'functiongemma-270m', 'name': 'FunctionGemma 270M', 'type': 'specialist'},
    // ── Liquid / LFM2 ────────────────────────────────────────────────────────
    {'id': 'lfm2-350m',   'name': 'LFM2 350M',   'type': 'liquid'},
    {'id': 'lfm2.5-350m', 'name': 'LFM2.5 350M', 'type': 'liquid'},
    {'id': 'lfm2-700m',   'name': 'LFM2 700M',   'type': 'liquid'},
    {'id': 'lfm2-1.2b',   'name': 'LFM2 1.2B',   'type': 'liquid'},
    // ── Transformer (Qwen3 / Qwen3.5) ────────────────────────────────────────
    {'id': 'qwen3-0.6',   'name': 'Qwen3 0.6B',   'type': 'generalist'},
    {'id': 'qwen3-1.7',   'name': 'Qwen3 1.7B',   'type': 'generalist'},
    {'id': 'qwen3.5-0.8', 'name': 'Qwen3.5 0.8B', 'type': 'generalist'},
    {'id': 'qwen3.5-2b',  'name': 'Qwen3.5 2B',   'type': 'generalist'},
    // ── Audio-native ──────────────────────────────────────────────────────────
    {'id': 'lfm2-audio-350m', 'name': 'LFM2-audio 350M', 'type': 'audio'},
    {'id': 'gemma-4-1b',      'name': 'Gemma 4 1B',      'type': 'audio'},
  ];

  static Future<Map<String, dynamic>> loadProgress() async {
    final file = File(progressFile);
    if (await file.exists()) {
      final content = await file.readAsString();
      return jsonDecode(content);
    }
    return {'completed': <String>[], 'lastModel': null, 'lastCommandIndex': -1};
  }

  static Future<void> saveProgress(Map<String, dynamic> progress) async {
    final file = File(progressFile);
    await file.writeAsString(jsonEncode(progress));
  }

  static Future<void> saveResultIncremental(BenchmarkResult result) async {
    final file = File(resultsFile);
    final exists = await file.exists();
    final sink = file.openWrite(mode: FileMode.append);
    if (!exists) sink.writeln(BenchmarkResult.csvHeader());
    sink.writeln(result.toCsvRow());
    await sink.close();
    await _appendToJsonResults(result);
  }

  static Future<void> _appendToJsonResults(BenchmarkResult result) async {
    final file = File(jsonResultsFile);
    List<dynamic> results = [];
    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) results = jsonDecode(content);
    }
    results.add(result.toJson());
    await file.writeAsString(jsonEncode(results));
  }

  static Future<void> run({
    List<String>? modelIds,
    int? commandsPerModel,
    Function(String)? onProgress,
  }) async {
    final models =
        modelIds ?? availableModels.map((m) => m['id'] as String).toList();
    final commandLimit = commandsPerModel ?? 30;

    void log(String message) {
      print('[${DateTime.now().toIso8601String()}] $message');
      onProgress?.call(message);
    }

    log('=== Headless Benchmark Runner ===');
    log('Models: ${models.join(", ")}');
    log('Commands per model: $commandLimit');

    log('Loading test dataset...');
    final testCases = await BenchmarkDataset.load();
    log('Loaded ${testCases.length} test cases');
    final limitedTestCases = testCases.take(commandLimit).toList();

    // Resolve the audio-clip directory once for audio-native models.
    final audioDir = await ModelStore.audioDir();

    final progress = await loadProgress();
    final completedTests = (progress['completed'] as List).cast<String>();
    log('Resuming: ${completedTests.length} tests already completed');

    final tools = buildAgentTools();
    int totalTests = 0;
    int successfulTests = 0;

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
              final pcm = Uint8List.fromList(wavBytes.sublist(44));

              log('  [audio] ${pcm.length} bytes PCM from clip $i');
              response = await lm.complete(
                messages: [
                  {'role': 'system', 'content': systemPrompt},
                ],
                tools: tools,
                maxTokens: 100,
                temperature: 0.1,
                pcmBytes: pcm,
              );
            } else {
              response = await lm.complete(
                messages: [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': testCase.transcription},
                ],
                tools: tools,
                maxTokens: 100,
                temperature: 0.1,
              );
            }

            final latency =
                DateTime.now().difference(startTime).inMilliseconds;
            final effectiveWer =
                isAudioNative ? 0.0 : testCase.wordErrorRate;
            final effectiveTranscription =
                isAudioNative ? testCase.command : testCase.transcription;
            final inputMode = isAudioNative ? 'direct' : 'pipeline';

            if (!response.success || response.toolCalls.isEmpty) {
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
                error: 'No tool calls generated',
                wordErrorRate: effectiveWer,
                inputMode: inputMode,
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
                  isAudioNative ? testCase.command : testCase.transcription,
              category: testCase.category,
              expectedFunction: testCase.expectedFunction,
              expectedParams: testCase.expectedParameters,
              success: false,
              correctFunction: false,
              correctParams: false,
              latencyMs: latency,
              error: e.toString(),
              wordErrorRate: isAudioNative ? 0.0 : testCase.wordErrorRate,
              inputMode: isAudioNative ? 'direct' : 'pipeline',
            );
          }

          await saveResultIncremental(result);
          totalTests++;
          completedTests.add(testId);
          await saveProgress({
            'completed': completedTests,
            'lastModel': modelId,
            'lastCommandIndex': i,
            'timestamp': DateTime.now().toIso8601String(),
          });
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
    log('║ Results: $resultsFile');
    log('╚════════════════════════════════════════════════════════════╝');

    await _generateFinalSummary();
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

  static Future<void> _generateFinalSummary() async {
    final resultsFile = File(jsonResultsFile);
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
          ),
        )
        .toList();

    final summary = StringBuffer();
    summary.writeln('# Headless Benchmark Summary');
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

    final summaryFile = File('results/headless_benchmark_summary.md');
    await summaryFile.writeAsString(summary.toString());
    print('\n✓ Summary saved: ${summaryFile.path}');
  }
}

void main(List<String> args) async {
  List<String>? models;
  int? commandsPerModel;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--models' && i + 1 < args.length) {
      models = args[i + 1].split(',');
    } else if (args[i] == '--commands' && i + 1 < args.length) {
      commandsPerModel = int.tryParse(args[i + 1]);
    }
  }
  await HeadlessBenchmarkRunner.run(
    modelIds: models,
    commandsPerModel: commandsPerModel,
  );
  exit(0);
}
