// Executes the function calls produced by the model against the real device
// controls, and manages the in-memory automation rules.

import '../models/automation_rule.dart';
import '../tools/device_controls.dart';

/// Outcome of executing one tool call — a human-readable message plus a short
/// status label for the UI.
class ExecResult {
  final String message;
  final String status;
  final bool success;

  const ExecResult(this.message, this.status, {this.success = true});
}

class DeviceExecutor {
  final List<AutomationRule> rules = [];

  Future<ExecResult> execute(
    String function,
    Map<String, dynamic> args,
  ) async {
    switch (function) {
      case 'createRule':
        return _createRule(args);
      case 'listRules':
        return _listRules();
      case 'clearRules':
        return _clearRules();
      case 'setDoNotDisturb':
        final minutes = _asInt(args['durationMinutes'], 30);
        final ok = await DeviceControls.setDoNotDisturb(durationMinutes: minutes);
        return ExecResult(
          'DND ${ok ? 'enabled' : 'failed'} for $minutes minutes',
          ok ? 'Success' : 'Failed',
          success: ok,
        );
      case 'toggleFlashlight':
        final enable = _asBool(args['enable']);
        final ok = await DeviceControls.toggleFlashlight(enable: enable);
        return ExecResult(
          'Flashlight ${ok ? (enable ? 'turned on' : 'turned off') : 'failed'}',
          ok ? 'Success' : 'Failed',
          success: ok,
        );
      case 'setVolume':
        final percent = _asInt(args['volumePercent'], 50);
        final ok = await DeviceControls.setVolume(volumePercent: percent);
        return ExecResult(
          'Volume ${ok ? 'set to $percent%' : 'failed'}',
          ok ? 'Success' : 'Failed',
          success: ok,
        );
      case 'setScreenBrightness':
        final percent = _asInt(args['brightnessPercent'], 50);
        final ok =
            await DeviceControls.setScreenBrightness(brightnessPercent: percent);
        return ExecResult(
          'Brightness ${ok ? 'set to $percent%' : 'failed'}',
          ok ? 'Success' : 'Failed',
          success: ok,
        );
      case 'toggleWifi':
        final enable = _asBool(args['enable']);
        final ok = await DeviceControls.toggleWifi(enable: enable);
        return ExecResult(
          'Wi-Fi ${ok ? (enable ? 'enabled' : 'disabled') : 'failed'}',
          ok ? 'Success' : 'Failed',
          success: ok,
        );
      default:
        return ExecResult(
          'Unknown function: $function',
          'Unsupported',
          success: false,
        );
    }
  }

  ExecResult _createRule(Map<String, dynamic> args) {
    final trigger = args['trigger']?.toString() ?? '';
    final action = (args['action']?.toString() ?? '').toLowerCase();

    String mappedAction;
    final params = <String, dynamic>{};
    if (action.contains('mute') ||
        action.contains('silence') ||
        action.contains('dnd') ||
        action.contains('do not disturb')) {
      mappedAction = 'setDoNotDisturb';
      params['durationMinutes'] = 60;
    } else if (action.contains('flashlight') || action.contains('torch')) {
      mappedAction = 'toggleFlashlight';
      params['enable'] = action.contains('on') || action.contains('enable');
    } else if (action.contains('volume')) {
      mappedAction = 'setVolume';
      params['volumePercent'] = 0;
    } else {
      return ExecResult(
        'Could not understand action: "$action"',
        'Rule creation failed',
        success: false,
      );
    }

    rules.add(AutomationRule(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      trigger: trigger,
      action: mappedAction,
      parameters: params,
      created: DateTime.now(),
    ));

    return ExecResult(
      'Rule created: When "$trigger" → $mappedAction\nTotal rules: ${rules.length}',
      'Rule created',
    );
  }

  ExecResult _listRules() {
    if (rules.isEmpty) {
      return const ExecResult(
        'No rules yet. Try: "Mute notifications when I\'m in class"',
        'No rules',
      );
    }
    final list = rules
        .asMap()
        .entries
        .map((e) =>
            '${e.key + 1}. ${e.value.enabled ? "✓" : "✗"} When "${e.value.trigger}" → ${e.value.action}')
        .join('\n');
    return ExecResult('Active Rules (${rules.length}):\n\n$list', 'Rules listed');
  }

  ExecResult _clearRules() {
    final count = rules.length;
    rules.clear();
    return ExecResult('Deleted $count rule${count == 1 ? "" : "s"}', 'Rules cleared');
  }

  static int _asInt(dynamic value, int fallback) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _asBool(dynamic value) {
    return value == true || value?.toString().toLowerCase() == 'true';
  }
}
