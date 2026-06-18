import 'package:flutter/material.dart';

/// Brief quick-start shown on first launch.
class OnboardingCard extends StatelessWidget {
  final VoidCallback onDismiss;

  const OnboardingCard({super.key, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.lightbulb_outline, color: Colors.orange),
                SizedBox(width: 8),
                Text('Quick start',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('1. Press "Initialize" (downloads the model, ~30s).'),
            const Text('2. Press "Request DND Permission".'),
            const Text('3. Type a command, or run the benchmark.'),
            const SizedBox(height: 12),
            const Text('Try:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const Text('  • "I need silence for 2 hours"',
                style: TextStyle(fontSize: 11)),
            const Text('  • "Turn on the flashlight"',
                style: TextStyle(fontSize: 11)),
            const Text('  • "Set volume to 73 percent"',
                style: TextStyle(fontSize: 11)),
            const Text('  • "Mute when I\'m in class"',
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onDismiss, child: const Text('Got it')),
          ],
        ),
      ),
    );
  }
}
