import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DeviceControls {
  static const MethodChannel _channel = MethodChannel(
    'com.myagent.tools/system',
  );

  static Future<bool> setDoNotDisturb({required int durationMinutes}) async {
    try {
      final bool result = await _channel.invokeMethod('enableDnd', {
        'duration': durationMinutes,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to enable DND: ${e.message}');
      return false;
    }
  }

  static Future<void> requestDndPermission() async {
    try {
      await _channel.invokeMethod('requestDndPermission');
    } on PlatformException catch (e) {
      debugPrint('Failed to request DND permission: ${e.message}');
    }
  }

  static Future<bool> toggleFlashlight({required bool enable}) async {
    try {
      final bool result = await _channel.invokeMethod('toggleFlashlight', {
        'enable': enable,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to toggle flashlight: ${e.message}');
      return false;
    }
  }

  static Future<bool> setVolume({required int volumePercent}) async {
    try {
      final bool result = await _channel.invokeMethod('setVolume', {
        'volumePercent': volumePercent,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to set volume: ${e.message}');
      return false;
    }
  }

  static Future<bool> setScreenBrightness({
    required int brightnessPercent,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('setScreenBrightness', {
        'brightnessPercent': brightnessPercent,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to set brightness: ${e.message}');
      return false;
    }
  }

  static Future<bool> toggleWifi({required bool enable}) async {
    try {
      final bool result = await _channel.invokeMethod('toggleWifi', {
        'enable': enable,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to toggle wifi: ${e.message}');
      return false;
    }
  }

  /// Set a timer/alarm for specified minutes from now
  static Future<bool> setTimer({required int minutes}) async {
    try {
      final bool result = await _channel.invokeMethod('setTimer', {
        'minutes': minutes,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to set timer: ${e.message}');
      return false;
    }
  }

  /// Toggle Bluetooth on/off
  static Future<bool> toggleBluetooth({required bool enable}) async {
    try {
      final bool result = await _channel.invokeMethod('toggleBluetooth', {
        'enable': enable,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to toggle bluetooth: ${e.message}');
      return false;
    }
  }

  /// Toggle Airplane mode on/off
  static Future<bool> toggleAirplaneMode({required bool enable}) async {
    try {
      final bool result = await _channel.invokeMethod('toggleAirplaneMode', {
        'enable': enable,
      });
      return result;
    } on PlatformException catch (e) {
      debugPrint('Failed to toggle airplane mode: ${e.message}');
      return false;
    }
  }
}
