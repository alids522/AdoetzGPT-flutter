import 'package:flutter/services.dart';

class LiveAudioPlayer {
  static const _channel = MethodChannel('adoetzgpt/live_audio');

  Future<void> start({int sampleRate = 24000}) async {
    try {
      await _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});
    } on MissingPluginException {
      // Non-Android targets can still receive transcripts without native audio.
    }
  }

  Future<void> playPcm16(Uint8List bytes, {int sampleRate = 24000}) async {
    try {
      await _channel.invokeMethod<void>('play', bytes);
    } on MissingPluginException {
      // Keep Live usable for text transcripts where native playback is absent.
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No platform audio player registered.
    }
  }
}
