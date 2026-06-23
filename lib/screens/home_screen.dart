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
    try {
      await HeadlessBenchmarkRunner.run(onProgress: _setStatus);
      setState(() {
        _status = 'Benchmark complete.';
        _response = 'Results saved to results/headless_benchmark_results.csv '
            'and results/headless_benchmark_summary.md.';
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
          IconButton(
            icon: const Icon(Icons.mic),
            tooltip: 'Record benchmark audio clips',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const RecordingScreen()),
            ),
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
