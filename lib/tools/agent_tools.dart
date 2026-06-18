// Single source of truth for the function-calling tool schema and the adaptive
// system prompts. Shared by the interactive agent (AgentService) and the
// benchmark runner so the app behaves exactly as it is measured.

import 'package:cactus/cactus.dart';

/// The six device-control functions the model may call.
List<CactusTool> buildAgentTools() {
  return [
    CactusTool(
      name: 'setDoNotDisturb',
      description: 'Enables Do Not Disturb mode for a specified duration.',
      parameters: ToolParametersSchema(
        properties: {
          'durationMinutes': ToolParameter(
            type: 'integer',
            description: 'Duration in minutes.',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'toggleFlashlight',
      description: 'Controls the device flashlight.',
      parameters: ToolParametersSchema(
        properties: {
          'enable': ToolParameter(
            type: 'boolean',
            description: 'True to turn on, false to turn off.',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'setVolume',
      description: 'Adjusts device volume.',
      parameters: ToolParametersSchema(
        properties: {
          'volumePercent': ToolParameter(
            type: 'integer',
            description: 'Volume from 0-100.',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'setScreenBrightness',
      description: 'Adjusts screen brightness.',
      parameters: ToolParametersSchema(
        properties: {
          'brightnessPercent': ToolParameter(
            type: 'integer',
            description: 'Brightness from 0-100.',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'toggleWifi',
      description: 'Enables or disables Wi-Fi.',
      parameters: ToolParametersSchema(
        properties: {
          'enable': ToolParameter(
            type: 'boolean',
            description: 'True to enable, false to disable.',
            required: true,
          ),
        },
      ),
    ),
    CactusTool(
      name: 'createRule',
      description: 'Creates a contextual automation rule.',
      parameters: ToolParametersSchema(
        properties: {
          'trigger': ToolParameter(
            type: 'string',
            description: 'Context trigger, e.g. "in class", "sleeping".',
            required: true,
          ),
          'action': ToolParameter(
            type: 'string',
            description: 'Action to perform, e.g. "mute", "enable dnd".',
            required: true,
          ),
        },
      ),
    ),
  ];
}

/// Adaptive system prompt keyed by model type (see `AgentModel.type`).
String systemPromptFor(String modelType) {
  switch (modelType) {
    case 'specialist':
      return 'Function calling assistant. Parse the command and call the matching '
          'function with parameters. '
          'Examples: "silence 2h"→setDoNotDisturb(120), "torch on"→toggleFlashlight(true). '
          'Always call exactly one function.';

    case 'liquid':
      return 'Temporal reasoning assistant with function calling.\n'
          'Extract: action + parameters + temporal context.\n'
          'Examples:\n'
          '- "silence next hour" → setDoNotDisturb(60)\n'
          '- "brightness for reading" → setScreenBrightness(70)\n'
          '- "mute when in class" → createRule(trigger="in class", action="mute")\n'
          'Always call a function. Handle time expressions.';

    case 'generalist':
    default:
      return 'You are an intelligent device control assistant with function '
          'calling capabilities.\n\n'
          '## Reasoning Process:\n'
          '1. Parse user intent: what action?\n'
          '2. Identify synonyms: silence=mute=quiet=dnd, torch=flashlight\n'
          '3. Extract parameters: numbers, time durations\n'
          '4. Handle temporal: "next hour"=60min, "2 hours"=120min\n'
          '5. Map context: "sleeping"→low volume/brightness\n'
          '6. Choose function and validate parameters\n\n'
          '## Examples:\n'
          '- "Turn on flashlight" → toggleFlashlight(enable=true)\n'
          '- "Quiet for 2 hours" → setDoNotDisturb(durationMinutes=120)\n'
          '- "Volume 75 percent" → setVolume(volumePercent=75)\n'
          '- "Brightness for reading" → setScreenBrightness(brightnessPercent=70)\n'
          '- "Enable wifi" → toggleWifi(enable=true)\n'
          '- "Mute in class" → createRule(trigger="in class", action="mute")\n\n'
          '## Rules:\n'
          '- ALWAYS call a function\n'
          '- Extract exact numeric values\n'
          '- Use reasonable defaults\n'
          '- Handle ASR errors gracefully';
  }
}
