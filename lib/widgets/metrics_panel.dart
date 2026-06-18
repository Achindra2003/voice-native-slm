import 'package:flutter/material.dart';

/// Live session metrics for the active model (command count, success/fail,
/// average latency).
class MetricsPanel extends StatelessWidget {
  final String modelId;
  final int commandCount;
  final int successCount;
  final int failCount;
  final int totalLatencyMs;

  const MetricsPanel({
    super.key,
    required this.modelId,
    required this.commandCount,
    required this.successCount,
    required this.failCount,
    required this.totalLatencyMs,
  });

  @override
  Widget build(BuildContext context) {
    String pct(int n) =>
        commandCount > 0 ? (n / commandCount * 100).toStringAsFixed(0) : '0';
    final avgLatency =
        commandCount > 0 ? (totalLatencyMs / commandCount).toStringAsFixed(0) : '0';

    return Card(
      color: Colors.deepPurple.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.analytics, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Session metrics',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Model: $modelId',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple)),
            const SizedBox(height: 8),
            Text('Total commands: $commandCount',
                style: const TextStyle(fontSize: 13)),
            Text('├─ Succeeded: $successCount (${pct(successCount)}%)',
                style: const TextStyle(fontSize: 13, color: Colors.green)),
            Text('└─ Failed: $failCount (${pct(failCount)}%)',
                style: const TextStyle(fontSize: 13, color: Colors.red)),
            const SizedBox(height: 8),
            Text('Average latency: ${avgLatency}ms',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
