import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides access to platform-specific functionality via MethodChannels.
class PlatformService {
  static const _channel = MethodChannel('app.alkyo.webreader/system');

  /// Opens the Android Text-to-Speech system settings screen.
  /// No-op on non-Android platforms.
  static Future<void> openTtsSettings() async {
    if (!defaultTargetPlatform.toString().contains('android') &&
        defaultTargetPlatform != TargetPlatform.android)
      return;
    try {
      await _channel.invokeMethod<void>('openTtsSettings');
    } on PlatformException {
      // Silently ignore if not available on this device.
    }
  }
}
