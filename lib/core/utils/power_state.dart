/*
 * File: power_state.dart
 * Description: Platform battery-state access used by power-sensitive tasks.
 */

import 'package:battery_plus/battery_plus.dart';

/// Reads whether the device is connected to a charger.
class PowerState {
  PowerState._();

  static final Battery _battery = Battery();

  /// Returns true while charging or fully charged on external power.
  ///
  /// A platform failure is treated as not charging so a charging-only backup
  /// never runs without a confirmed power state.
  static Future<bool> isCharging() async {
    try {
      final state = await _battery.batteryState;
      return state == BatteryState.charging ||
          state == BatteryState.full ||
          state == BatteryState.connectedNotCharging;
    } catch (_) {
      return false;
    }
  }
}
