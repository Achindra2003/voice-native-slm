// Single source of truth for the function-calling tool schema and the adaptive
// system prompts. Shared by the interactive agent (AgentService) and the
// benchmark runner so the app behaves exactly as it is measured.

/// One function-calling tool in the OpenAI-style schema the Cactus v2.0 engine
/// expects as its `toolsJson`:
/// `{"type":"function","function":{"name":..,"description":..,"parameters":{..}}}`
Map<String, dynamic> _tool(
  String name,
  String description,
  Map<String, Map<String, String>> properties,
) {
  return {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': properties,
        'required': properties.keys.toList(),
      },
    },
  };
}

/// The six device-control functions the model may call, as JSON-ready maps.
List<Map<String, dynamic>> buildAgentTools() {
  return [
    _tool('setDoNotDisturb', 'Enables Do Not Disturb mode for a specified duration.', {
      'durationMinutes': {'type': 'integer', 'description': 'Duration in minutes.'},
    }),
    _tool('toggleFlashlight', 'Controls the device flashlight.', {
      'enable': {'type': 'boolean', 'description': 'True to turn on, false to turn off.'},
    }),
    _tool('setVolume', 'Adjusts device volume.', {
      'volumePercent': {'type': 'integer', 'description': 'Volume from 0-100.'},
    }),
    _tool('setScreenBrightness', 'Adjusts screen brightness.', {
      'brightnessPercent': {'type': 'integer', 'description': 'Brightness from 0-100.'},
    }),
    _tool('toggleWifi', 'Enables or disables Wi-Fi.', {
      'enable': {'type': 'boolean', 'description': 'True to enable, false to disable.'},
    }),
    _tool('createRule', 'Creates a contextual automation rule.', {
      'trigger': {'type': 'string', 'description': 'Context trigger, e.g. "in class", "sleeping".'},
      'action': {'type': 'string', 'description': 'Action to perform, e.g. "mute", "enable dnd".'},
    }),
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

    case 'audio':
      return 'Listen to the audio and call the matching device-control function. '
          'Always call exactly one function with correct parameters. '
          'Examples: heard "turn on flashlight"→toggleFlashlight(true), '
          '"set volume 60"→setVolume(60).';

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
