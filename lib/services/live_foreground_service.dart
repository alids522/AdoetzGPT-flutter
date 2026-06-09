import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveForegroundService {
  static const _channel = MethodChannel('adoetzgpt/live_foreground');

  static Future<void> start() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('start');
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('stop');
  }
}
