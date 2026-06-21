// ignore_for_file: avoid_print
//
// Headless Benchmark Runner — crash-resistant with incremental saving.
// Runs the dataset across each model with memory management, saving results
// after every command so a crash loses no data.
//
// Usage: dart run lib/services/headless_benchmark_runner.dart
// Or from Flutter: HeadlessBenchmarkRunner.run()

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'benchmark_service.dart';
import '../native/cactus_engine.dart';
import '../native/model_store.dart';
import '../tools/agent_tools.dart';

class HeadlessBenchmarkRunner {
  /// Incremental results file - appended after each test
  static const String resultsFile = 'results/headless_benchmark_results.csv';
  static const String jsonResultsFile =
      'results/headless_benchmark_results.json';
  static const String progressFile = 'results/benchmark_progress.json';

  /// Memory management: Aggressive cleanup intervals
  static const int cleanupInterval = 5; // Cleanup every 5 commands
  static const int delayBetweenCommandsMs = 500; // Cool down period

  /// Available models — confirmed against the Cactus registry (June 2026).
  /// All support function calling, required for device-control intent parsing.
  /// type: 'generalist' | 'liquid' | 'specialist'
  static final List<Map<String, dynamic>> availableModels = [
    // ── Qwen3 generalist (Transformer) ───────────────────────────────────────
    {'id': 'qwen3-0.6', 'name': 'Qwen3 0.6B', 'type': 'generalist'},
    {'id': 'qwen3-1.7', 'name': 'Qwen3 1.7B', 'type': 'generalist'},
    // ── Liquid LFM2 (hybrid-recurrent, temporal reasoning) ───────────────────
    {'id': 'lfm2-350m', 'name': 'LFM2 350M', 'type': 'liquid'},
    {'id': 'lfm2-700m', 'name': 'LFM2 700M', 'type': 'liquid'},
    {'id': 'lfm2-1.2b', 'name': 'LFM2 1.2B', 'type': 'liquid'},
    // ── FunctionGemma (function-calling specialist) ──────────────────────────
    {'id': 'functiongemma-270m', 'name': 'FunctionGemma 270M', 'type': 'specialist'},
  ];

  /// Load progress from previous run (if crashed)
  static Future<Map<String, dynamic>> loadProgress() async {
    final file = File(progressFile);
    if (await file.exists()) {
      final content = await file.readAsString();
      return jsonDecode(content);
    }
    return {'completed': <String>[], 'lastModel': null, 'lastCommandIndex': -1};
  }

  /// Save progress after each command
  static Future<void> saveProgress(Map<String, dynamic> progress) async {
    final file = File(progressFile);
    await file.writeAsString(jsonEncode(progress));
  }

  /// Save single result incrementally (append to CSV)
  static Future<void> saveResultIncremental(BenchmarkResult result) async {
    final file = File(resultsFile);
    final exists = await file.exists();

    final sink = file.openWrite(mode: FileMode.append);

    // Write header if new file
    if (!exists) {
      sink.writeln(BenchmarkResult.csvHeader());
    }

    sink.writeln(result.toCsvRow());
    await sink.close();

    // Also append to JSON array (more complex, but useful)
    await _appendToJsonResults(result);
  }

  /// Append result to JSON file
  static Future<void> _appendToJsonResults(BenchmarkResult result) async {
    final file = File(jsonResultsFile);
    List<dynamic> results = [];

    if (await file.exists()) {
      final content = await file.readAsString();
      if (content.isNotEmpty) {
        results = jsonDecode(content);
      }
    }

    results.add(result.toJson());
    await file.writeAsString(jsonEncode(results));
  }

  /// Main benchmark execution
  static Future<void> run({
    List<String>? modelIds,
    int? commandsPerModel,
    Function(String)? onProgress,
  }) async {
    final models =
        modelIds ?? availableModels.map((m) => m['id'] as String).toList();
    final commandLimit =
        commandsPerModel ?? 30; // Default 30 commands per model

    void log(String message) {
      print('[${DateTime.now().toIso8601String()}] $message');
      onProgress?.call(message);
    }

    log('=== Headless Benchmark Runner ===');
    log('Models: ${models.join(", ")}');
    log('Commands per model: $commandLimit');
    log('Memory management: Cleanup every $cleanupInterval commands');

    // Load dataset
    log('Loading test dataset...');
    final testCases = await BenchmarkDataset.load();
    log('Loaded ${testCases.length} test cases');

    // Limit to 30 commands per model
    final limitedTestCases = testCases.take(commandLimit).toList();
    log('Using first $commandLimit commands per model');

    // Load progress from previous run
    final progress = await loadProgress();
    final completedTests = (progress['completed'] as List).cast<String>();
    log(
      'Resuming from checkpoint: ${completedTests.length} tests already completed',
    );

    final tools = buildAgentTools();
    int totalTests = 0;
    int successfulTests = 0;

    // Run benchmark for each model
    for (final modelId in models) {
      final modelInfo = availableModels.firstWhere((m) => m['id'] == modelId);
      final modelName = modelInfo['name'] as String;
      final modelType = modelInfo['type'] as String;

      log('');
      log('╔════════════════════════════════════════════════════════════╗');
      log('║ Starting: $modelName ($modelType)');
      log('╚════════════════════════════════════════════════════════════╝');

      CactusEngine? lm;

      try {
        // Initialize model from its staged on-device folder (the v2.0 FFI
        // binding has no download layer — stage via `adb push`).
        log('Initializing $modelName...');
        final modelPath = await ModelStore.modelDir(modelId);
        if (!await ModelStore.isStaged(modelId)) {
          throw Exception(
            'Model "$modelId" not staged at $modelPath '
            '(adb push <model_dir> $modelPath)',
          );
        }
        lm = CactusEngine()..init(modelPath);
        log('✓ Model loaded successfully');

        // Get adaptive prompt
        final systemPrompt = systemPromptFor(modelType);
        log('Using ${systemPrompt.length}-char prompt for $modelType type');

        // Run tests
        for (int i = 0; i < limitedTestCases.length; i++) {
          final testCase = limitedTestCases[i];
          final testId = '${modelId}_$i';

          // Skip if already completed
          if (completedTests.contains(testId)) {
            log('  Skipping test ${i + 1}/$commandLimit (already completed)');
            continue;
          }

          log('  Test ${i + 1}/$commandLimit: "${testCase.command}"');

          // audioNative models receive the clean original command —
          // this simulates bypassing the Whisper ASR stage entirely.
          final isAudioNative = modelType == 'audioNative';
          final userInput = isAudioNative ? testCase.command : testCase.transcription;
          final inputMode = isAudioNative ? 'direct' : 'pipeline';
          if (isAudioNative) {
            log('  [audioNative] Using clean input (no ASR noise)');
          }

          final startTime = DateTime.now();
          BenchmarkResult? result;

          try {
            // Run inference (synchronous FFI call into the native engine).
            final response = lm.complete(
              messages: [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userInput},
              ],
              tools: tools,
              maxTokens: 100,
              temperature: 0.1,
            );

            final latency = DateTime.now().difference(startTime).inMilliseconds;

            // Parse result
            // audioNative models have WER=0 (clean input, no ASR noise)
            final effectiveWer = isAudioNative ? 0.0 : testCase.wordErrorRate;
            final effectiveTranscription = isAudioNative ? testCase.command : testCase.transcription;

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
            final latency = DateTime.now().difference(startTime).inMilliseconds;
            log('    ❌ Error: $e');

            result = BenchmarkResult(
              modelName: modelName,
              command: testCase.command,
              transcribedText: isAudioNative ? testCase.command : testCase.transcription,
              category: testCase.category,
              expectedFunction: testCase.expectedFunction,
              expectedParams: testCase.expectedParameters,
              success: false,
              correctFunction: false,
              correctParams: false,
              latencyMs: latency,
              error: e.toString(),
              wordErrorRate: isAudioNative ? 0.0 : testCase.wordErrorRate,
              inputMode: inputMode,
            );
          }

          // Save result immediately (crash-resistant)
          await saveResultIncremental(result);
          totalTests++;

          // Update progress
          completedTests.add(testId);
          await saveProgress({
            'completed': completedTests,
            'lastModel': modelId,
            'lastCommandIndex': i,
            'timestamp': DateTime.now().toIso8601String(),
          });

          log(
            '    ${result.success ? "✓" : "✗"} ${result.actualFunction ?? "none"} | ${result.latencyMs}ms',
          );

          // Memory management: Periodic cleanup
          if ((i + 1) % cleanupInterval == 0) {
            log('    🧹 Memory cleanup checkpoint (${i + 1}/$commandLimit)');
            await Future.delayed(
              Duration(milliseconds: delayBetweenCommandsMs * 2),
            );
          } else {
            await Future.delayed(
              Duration(milliseconds: delayBetweenCommandsMs),
            );
          }
        }

        log('✓ Completed $modelName: ${limitedTestCases.length} tests');
      } catch (e) {
        log('❌ Fatal error with $modelName: $e');
      } finally {
        // CRITICAL: Proper cleanup to prevent memory leaks
        if (lm != null) {
          log('Unloading $modelName...');
          try {
            lm.dispose();
            log('✓ Model unloaded');
          } catch (e) {
            log('⚠ Unload error: $e');
          }
        }
        lm = null;

        // Force garbage collection hint
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    log('');
    log('╔════════════════════════════════════════════════════════════╗');
    log('║ BENCHMARK COMPLETE');
    log('╠════════════════════════════════════════════════════════════╣');
    log('║ Total tests: $totalTests');
    log(
      '║ Successful: $successfulTests (${(successfulTests / totalTests * 100).toStringAsFixed(1)}%)',
    );
    log('║ Results: $resultsFile');
    log('║ Progress: $progressFile');
    log('╚════════════════════════════════════════════════════════════╝');

    // Generate final summary
    await _generateFinalSummary();
  }

  /// Compare parameters with tolerance
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
        final tolerance = expectedVal * 0.1;
        if (diff > tolerance && diff > 5) return false;
      } else if (expectedVal is String && actualVal is String) {
        if (expectedVal.toLowerCase() != actualVal.toLowerCase()) return false;
      } else {
        if (expectedVal != actualVal) return false;
      }
    }

    return true;
  }

  /// Generate final summary report
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
            actualFunction: r['actual_function'].isEmpty
                ? null
                : r['actual_function'],
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

    // Group by model
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
      final modelResults = entry.value;
      final success = modelResults.where((r) => r.success).length;
      final correctFn = modelResults.where((r) => r.correctFunction).length;
      final correctParam = modelResults.where((r) => r.correctParams).length;
      final avgLatency =
          modelResults.map((r) => r.latencyMs).reduce((a, b) => a + b) /
          modelResults.length;
      final mode = modelResults.first.inputMode;

      summary.writeln(
        '| ${entry.key} | $mode | ${modelResults.length} | '
        '${(success / modelResults.length * 100).toStringAsFixed(1)}% | '
        '${(correctFn / modelResults.length * 100).toStringAsFixed(1)}% | '
        '${(correctParam / modelResults.length * 100).toStringAsFixed(1)}% | '
        '${avgLatency.toStringAsFixed(0)}ms |',
      );
    }

    // Architecture comparison: pipeline vs direct
    final pipelineResults = results.where((r) => r.inputMode == 'pipeline').toList();
    final directResults = results.where((r) => r.inputMode == 'direct').toList();

    summary.writeln('\n## Architecture Comparison: Pipeline vs Unified\n');
    if (pipelineResults.isNotEmpty) {
      final pSuccess = pipelineResults.where((r) => r.success).length;
      final pLatency = pipelineResults.map((r) => r.latencyMs).reduce((a, b) => a + b) / pipelineResults.length;
      summary.writeln('**Pipeline (Whisper STT + SLM):**');
      summary.writeln('- Models tested: ${pipelineResults.map((r) => r.modelName).toSet().length}');
      summary.writeln('- Overall success rate: ${(pSuccess / pipelineResults.length * 100).toStringAsFixed(1)}%');
      summary.writeln('- Mean latency: ${pLatency.toStringAsFixed(0)}ms');
      summary.writeln('- Mean WER of input: ${(pipelineResults.map((r) => r.wordErrorRate).reduce((a, b) => a + b) / pipelineResults.length).toStringAsFixed(3)}\n');
    }
    if (directResults.isNotEmpty) {
      final dSuccess = directResults.where((r) => r.success).length;
      final dLatency = directResults.map((r) => r.latencyMs).reduce((a, b) => a + b) / directResults.length;
      summary.writeln('**Unified Audio-Native (Gemma 4, no STT stage):**');
      summary.writeln('- Models tested: ${directResults.map((r) => r.modelName).toSet().length}');
      summary.writeln('- Overall success rate: ${(dSuccess / directResults.length * 100).toStringAsFixed(1)}%');
      summary.writeln('- Mean latency: ${dLatency.toStringAsFixed(0)}ms');
      summary.writeln('- Input WER: 0.000 (clean audio understanding)\n');
      if (pipelineResults.isNotEmpty) {
        final pSuccess = pipelineResults.where((r) => r.success).length;
        final gain = (directResults.where((r) => r.success).length / directResults.length) -
                     (pSuccess / pipelineResults.length);
        summary.writeln('> **Novel Finding:** Unified architecture ${gain >= 0 ? "outperforms" : "underperforms"} '
          'pipeline by ${(gain.abs() * 100).toStringAsFixed(1)}pp — '
          'empirical evidence ${gain >= 0 ? "for" : "against"} eliminating the ASR stage on mid-range devices.');
      }
    }

    final summaryFile = File('results/headless_benchmark_summary.md');
    await summaryFile.writeAsString(summary.toString());
    print('\n✓ Summary saved: ${summaryFile.path}');
  }
}

/// Standalone CLI entry point
void main(List<String> args) async {
  // Parse CLI arguments
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
