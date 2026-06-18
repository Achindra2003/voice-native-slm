import 'package:flutter/material.dart';

import '../models/agent_model.dart';

/// Dropdown for choosing the active on-device model.
class ModelSelector extends StatelessWidget {
  final String currentModelId;
  final bool isBusy;
  final bool isLoaded;
  final ValueChanged<String> onChanged;

  const ModelSelector({
    super.key,
    required this.currentModelId,
    required this.isBusy,
    required this.isLoaded,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final current = agentModelById(currentModelId);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.psychology, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('Model',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: currentModelId,
              decoration: const InputDecoration(
                labelText: 'Active model',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: kAgentModels
                  .map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name, style: const TextStyle(fontSize: 13)),
                      ))
                  .toList(),
              onChanged: isBusy
                  ? null
                  : (value) {
                      if (value != null) onChanged(value);
                    },
            ),
            const SizedBox(height: 8),
            Text(
              agentModelTypeLabel(current.type),
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontStyle: FontStyle.italic),
            ),
            Text(
              isLoaded ? '✓ Model loaded and ready' : '⚠ Press Initialize first',
              style: TextStyle(
                fontSize: 11,
                color: isLoaded ? Colors.green : Colors.orange,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
