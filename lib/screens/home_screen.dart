import 'package:flutter/material.dart';

import '../services/agent_service.dart';
import '../services/device_executor.dart';
import '../services/headless_benchmark_runner.dart';
import '../tools/device_controls.dart';
import '../widgets/metrics_panel.dart';
import '../widgets/model_selector.dart';
import '../widgets/onboarding_card.dart';
import 'recording_screen.dart';

/// The main interactive screen: pick a model, send a spoken/typed command,
/// watch it map to a device action, and run the benchmark suite.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AgentService _agent = AgentService();
  final DeviceExecutor _executor = DeviceExecutor();
  final TextEditingController _messageController = TextEditingController();

  String _status = 'Not initialized';
  String _response = '';
  bool _isInitializing = false;
  bool _isBenchmarkRunning = false;
  bool _showOnboarding = true;

  /// Which eval condition the Record button and benchmark run target.
  /// 'main' = the 120-command English paper benchmark (default, unchanged
  /// output files). 'pilot_en'/'pilot_cs' = the 12-command matched
  /// multilingual pilot (English baseline vs Hinglish/Kanglish code-switch).
  String _conditionKey = 'main';
  static const Map<String, ({String label, String dataset, String tag})>
      _conditions = {
    'main': (
      label: 'Main (English, 120)',
      dataset: 'assets/realistic_dataset.json',
      tag: 'en',
    ),
    'pilot_en': (
      label: 'Pilot — English (12)',
      dataset: 'assets/pilot_en.json',
      tag: 'pilot_en',
    ),
    'pilot_cs': (
      label: 'Pilot — Code-switched (12)',
      dataset: 'assets/pilot_codeswitch.json',
      tag: 'codeswitch',
    ),
  };

  int _commandCount = 0;
  int _successCount = 0;
  int _failCount = 0;
  int _totalLatencyMs = 0;

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _initialize() async {
    if (_isInitializing) return;
    setState(() => _isInitializing = true);
    try {
      await _agent.initialize(onStatus: _setStatus);
    } catch (e) {
      _setStatus('Failed to initialize: $e');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _switchModel(String id) async {
    setState(() => _isInitializing = true);
    try {
      await _agent.switchModel(id, onStatus: _setStatus);
    } catch (e) {
      _setStatus('Model switch failed: $e');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _send(String message) async {
    if (!_agent.isLoaded) {
      _setStatus('Model not initialized');
      return;
    }
    setState(() {
      _status = 'Processing…';
      _response = '';
    });

    final result = await _agent.send(message);

    if (!result.success) {
      setState(() {
        _commandCount++;
        _failCount++;
        _totalLatencyMs += result.latencyMs;
        _status = 'No function call';
        _response = 'The model did not call a function for "$message".\n'
            '${result.error ?? ''}';
      });
      return;
    }

    final messages = <String>[];
    for (final call in result.toolCalls) {
      final exec = await _executor.execute(call.name, call.arguments);
      messages.add(exec.message);
      _setStatus(exec.status);
    }

    setState(() {
      _commandCount++;
      _successCount++;
      _totalLatencyMs += result.latencyMs;
      _response = messages.join('\n');
    });
  }

  Future<void> _runBenchmark() async {
    if (_isBenchmarkRunning) return;
    setState(() {
      _isBenchmarkRunning = true;
      _status = 'Starting benchmark…';
    });
    final cond = _conditions[_conditionKey]!;
    try {
      await HeadlessBenchmarkRunner.run(
        onProgress: _setStatus,
        datasetPath: cond.dataset,
        condition: cond.tag,
      );
      setState(() {
        _status = 'Benchmark complete.';
        _response = 'Results saved to results/headless_benchmark_results'
            '${cond.tag == 'en' ? '' : '_${cond.tag}'}.csv and '
            'results/headless_benchmark_summary'
            '${cond.tag == 'en' ? '' : '_${cond.tag}'}.md.';
      });
    } catch (e) {
      setState(() {
        _status = 'Benchmark failed: $e';
        _response = 'Error during benchmark: $e';
      });
    } finally {
      if (mounted) setState(() => _isBenchmarkRunning = false);
    }
  }

  /// Quick end-to-end validation before committing to the multi-hour full run:
  /// exercises Phase 1 (Whisper), Phase 2 (one text model) and Phase 3 (one
  /// audio model) over 2 commands, reusing the recorded English clips but
  /// writing to isolated *_smoke result files so the real run stays clean.
  Future<void> _runSmokeTest() async {
    if (_isBenchmarkRunning) return;
    setState(() {
      _isBenchmarkRunning = true;
      _status = 'Smoke test: Whisper + 1 text + 1 audio model, 2 commands…';
    });
    try {
      await HeadlessBenchmarkRunner.run(
        onProgress: _setStatus,
        // qwen3-0.6 (not functiongemma-270m) is the pipeline-arm probe: it uses
        // the multi-component graph format the pinned engine can load.
        // functiongemma-270m fails cactus_init: the converter emits it as a
        // single-`decoder`-component bundle the pinned v2.0 engine can't init,
        // and a 2026-07-07 re-transpile reproduced a byte-identical graph — so
        // it's a dead end on this engine, not a stale bundle. Keep it out.
        modelIds: const ['qwen3-0.6', 'gemma-4-e2b'],
        commandsPerModel: 2,
        condition: 'smoke',
        audioCondition: 'en',
      );
      setState(() {
        _status = 'Smoke test complete — check results/*_smoke files.';
        _response = 'Both arms produced rows with no fatal error → the '
            'pipeline is wired correctly and the full benchmark is safe to run.';
      });
    } catch (e) {
      setState(() {
        _status = 'Smoke test FAILED — fix before the full run.';
        _response = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _isBenchmarkRunning = false);
    }
  }

  /// One-command load probe of models not yet load-proven on the v2.0
  /// engine, so the paper's pipeline-arm count rests on observed loads, not
  /// bundle format. The original 8+1 set was verified 2026-07-08; the list
  /// now targets the two Liquid 1.2B additions pushed 2026-07-09
  /// (lfm2-1.2b-tool, lfm2.5-1.2b). functiongemma-270m stays excluded (see
  /// the smoke-test note). Writes to isolated *_loadsweep result files; any
  /// model that fails to init is listed in the thrown error.
  Future<void> _runLoadSweep() async {
    if (_isBenchmarkRunning) return;
    setState(() {
      _isBenchmarkRunning = true;
      _status = 'Load sweep: 2 new models × 1 command…';
    });
    try {
      await HeadlessBenchmarkRunner.run(
        onProgress: _setStatus,
        modelIds: const [
          'lfm2-1.2b-tool',
          'lfm2.5-1.2b',
        ],
        commandsPerModel: 1,
        condition: 'loadsweep',
        audioCondition: 'en',
      );
      setState(() {
        _status = 'Load sweep complete — both new models loaded and ran.';
        _response = 'lfm2-1.2b-tool and lfm2.5-1.2b initialized and produced '
            'rows → the 10-model pipeline arm is fully load-verified.';
      });
    } catch (e) {
      setState(() {
        _status = 'Load sweep: some models FAILED to load.';
        _response = 'Failures (other models still verified, rows saved): $e';
      });
    } finally {
      if (mounted) setState(() => _isBenchmarkRunning = false);
    }
  }

  Future<void> _showRules() async {
    final exec = await _executor.execute('listRules', const {});
    setState(() {
      _status = exec.status;
      _response = exec.message;
    });
  }

  void _resetMetrics() {
    setState(() {
      _commandCount = 0;
      _successCount = 0;
      _failCount = 0;
      _totalLatencyMs = 0;
      _status = 'Metrics reset';
    });
  }

  @override
  void dispose() {
    _agent.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isInitializing || _isBenchmarkRunning;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('On-Device Voice Agent'),
        actions: [
          DropdownButton<String>(
            value: _conditionKey,
            dropdownColor: Theme.of(context).colorScheme.surface,
            underline: const SizedBox.shrink(),
            items: _conditions.entries
                .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value.label,
                          style: const TextStyle(fontSize: 12)),
                    ))
                .toList(),
            onChanged: busy
                ? null
                : (key) {
                    if (key != null) setState(() => _conditionKey = key);
                  },
          ),
          IconButton(
            icon: const Icon(Icons.mic),
            tooltip: 'Record benchmark audio clips',
            onPressed: () {
              final cond = _conditions[_conditionKey]!;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => RecordingScreen(
                    datasetPath: cond.dataset,
                    condition: cond.tag,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            tooltip: 'Smoke test (1 text + 1 audio model, 2 commands)',
            onPressed: busy ? null : _runSmokeTest,
          ),
          IconButton(
            icon: const Icon(Icons.playlist_add_check),
            tooltip: 'Load sweep (2 new models × 1 command)',
            onPressed: busy ? null : _runLoadSweep,
          ),
          if (_commandCount > 0)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Reset metrics',
              onPressed: _resetMetrics,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showOnboarding)
              OnboardingCard(
                  onDismiss: () => setState(() => _showOnboarding = false)),
            ModelSelector(
              currentModelId: _agent.currentModelId,
              isBusy: busy,
              isLoaded: _agent.isLoaded,
              onChanged: _switchModel,
            ),
            if (_commandCount > 0)
              MetricsPanel(
                modelId: _agent.currentModelId,
                commandCount: _commandCount,
                successCount: _successCount,
                failCount: _failCount,
                totalLatencyMs: _totalLatencyMs,
              ),
            Text('Status: $_status',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (_response.isNotEmpty) ...[
              Text('Response',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_response),
              ),
              const SizedBox(height: 20),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : _initialize,
                    child: const Text('Initialize'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await DeviceControls.requestDndPermission();
                      _setStatus('DND permission requested');
                    },
                    child: const Text('Request DND Permission'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _isBenchmarkRunning ? null : _runBenchmark,
              icon: _isBenchmarkRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.speed),
              label: Text(_isBenchmarkRunning
                  ? 'Running benchmark…'
                  : 'Run benchmark (30 cmds × ${HeadlessBenchmarkRunner.availableModels.length} models)'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Type a command',
                hintText: 'e.g. "I need silence for 2 hours"',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.chat_bubble_outline),
              ),
              maxLines: 2,
              onSubmitted: (text) {
                if (text.trim().isNotEmpty) _send(text.trim());
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final text = _messageController.text.trim();
                      if (text.isNotEmpty) _send(text);
                    },
                    child: const Text('Send'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _showRules,
                  child: Text('Rules (${_executor.rules.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
