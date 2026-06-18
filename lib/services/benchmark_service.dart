// Data model and dataset loading for the benchmark suite.
// Inference itself lives in headless_benchmark_runner.dart.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

/// One benchmark outcome row (one command on one model).
class BenchmarkResult {
  final String modelName;
  final String command;
  final String transcribedText;
  final String category;
  final String expectedFunction;
  final Map<String, dynamic> expectedParams;
  final String? actualFunction;
  final Map<String, dynamic>? actualParams;
  final bool success;
  final bool correctFunction;
  final bool correctParams;
  final int latencyMs;
  final String? error;
  final double wordErrorRate;

  /// 'pipeline' = input went through Whisper ASR (has WER noise);
  /// 'direct'   = clean input, no separate ASR stage.
  final String inputMode;

  BenchmarkResult({
    required this.modelName,
    required this.command,
    required this.transcribedText,
    required this.category,
    required this.expectedFunction,
    required this.expectedParams,
    this.actualFunction,
    this.actualParams,
    required this.success,
    required this.correctFunction,
    required this.correctParams,
    required this.latencyMs,
    this.error,
    required this.wordErrorRate,
    this.inputMode = 'pipeline',
  });

  Map<String, dynamic> toJson() => {
        'model': modelName,
        'command': command,
        'transcribed_text': transcribedText,
        'category': category,
        'expected_function': expectedFunction,
        'expected_params': jsonEncode(expectedParams),
        'actual_function': actualFunction ?? '',
        'actual_params': jsonEncode(actualParams ?? {}),
        'success': success,
        'correct_function': correctFunction,
        'correct_params': correctParams,
        'latency_ms': latencyMs,
        'error': error ?? '',
        'word_error_rate': wordErrorRate,
        'input_mode': inputMode,
      };

  String toCsvRow() {
    return [
      modelName,
      _escapeCsv(command),
      _escapeCsv(transcribedText),
      category,
      expectedFunction,
      _escapeCsv(jsonEncode(expectedParams)),
      actualFunction ?? '',
      _escapeCsv(jsonEncode(actualParams ?? {})),
      success ? '1' : '0',
      correctFunction ? '1' : '0',
      correctParams ? '1' : '0',
      latencyMs.toString(),
      _escapeCsv(error ?? ''),
      wordErrorRate.toStringAsFixed(3),
      inputMode,
    ].join(',');
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String csvHeader() {
    return 'model,command,transcribed_text,category,expected_function,'
        'expected_params,actual_function,actual_params,success,'
        'correct_function,correct_params,latency_ms,error,word_error_rate,input_mode';
  }
}

/// One command from the evaluation dataset.
class TestCase {
  final String participant;
  final String command;
  final String transcription;
  final String category;
  final double wordErrorRate;
  final String expectedFunction;
  final Map<String, dynamic> expectedParameters;

  TestCase({
    required this.participant,
    required this.command,
    required this.transcription,
    required this.category,
    required this.wordErrorRate,
    required this.expectedFunction,
    required this.expectedParameters,
  });

  factory TestCase.fromJson(Map<String, dynamic> json) {
    return TestCase(
      participant: json['participant_id'].toString(),
      command: json['original_command'] as String,
      transcription: json['transcribed_text'] as String,
      category: json['category'] as String,
      wordErrorRate: (json['word_error_rate'] as num).toDouble(),
      expectedFunction: json['expected_function'] as String,
      expectedParameters:
          jsonDecode(json['expected_params'] as String) as Map<String, dynamic>,
    );
  }
}

class BenchmarkDataset {
  /// Load the evaluation dataset, preferring bundled assets (deployed APK) and
  /// falling back to the local file system (development).
  static Future<List<TestCase>> load() async {
    final raw = await _loadRaw();
    return raw
        .map((item) => TestCase.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<List<dynamic>> _loadRaw() async {
    try {
      final content =
          await rootBundle.loadString('assets/realistic_dataset.json');
      return jsonDecode(content) as List<dynamic>;
    } catch (_) {
      for (final path in const [
        'assets/realistic_dataset.json',
        'results/realistic_dataset.json',
      ]) {
        final file = File(path);
        if (await file.exists()) {
          return jsonDecode(await file.readAsString()) as List<dynamic>;
        }
      }
      throw Exception('Dataset not found in assets or file system');
    }
  }
}
