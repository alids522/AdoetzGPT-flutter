import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveForegroundService {
  static const _channel = MethodChannel('adoetzgpt/live_foreground');
  static void Function(String)? onAction;

  static void initialize() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAction') {
        final action = call.arguments as String?;
        if (action != null) onAction?.call(action);
      }
    });
  }

  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('stop');
  }
}
