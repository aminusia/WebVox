import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Provides access to platform-specific functionality via MethodChannels.
class PlatformService {
  static const _channel = MethodChannel('app.alkyo.webreader/system');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Opens the Android Text-to-Speech system settings screen.
  /// No-op on non-Android platforms.
  static Future<void> openTtsSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openTtsSettings');
    } on PlatformException {
      // Silently ignore if not available on this device.
    }
  }

  /// Renders a URL in an Android WebView and returns the hydrated document HTML.
  /// Returns null on non-Android platforms or when rendering is unavailable.
  static Future<String?> renderUrlToHtml(
    String url, {
    String? refererUrl,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (!_isAndroid) return null;

    try {
      return await _channel.invokeMethod<String>('renderUrlToHtml', {
        'url': url,
        if (refererUrl != null && refererUrl.trim().isNotEmpty)
          'refererUrl': refererUrl.trim(),
        'timeoutMillis': timeout.inMilliseconds,
      });
    } on PlatformException {
      return null;
    }
  }
}
