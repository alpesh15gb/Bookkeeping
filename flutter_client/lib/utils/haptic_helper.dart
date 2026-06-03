import 'package:flutter/services.dart';

class HapticHelper {
  static Future<void> light() async {
    await HapticFeedback.lightImpact();
  }

  static Future<void> medium() async {
    await HapticFeedback.mediumImpact();
  }

  static Future<void> heavy() async {
    await HapticFeedback.heavyImpact();
  }

  static Future<void> success() async {
    // Light tick for success
    await HapticFeedback.lightImpact();
  }

  static Future<void> error() async {
    // Strong tick/vibration for error
    await HapticFeedback.heavyImpact();
  }

  static Future<void> delete() async {
    // Strong tick/vibration for deletion
    await HapticFeedback.heavyImpact();
  }
}
