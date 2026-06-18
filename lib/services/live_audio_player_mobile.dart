import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:mp_audio_stream/mp_audio_stream.dart';
class LiveAudioPlayer {
  static const _channel = MethodChannel('adoetzgpt/live_audio');
  AudioStream? _audioStream;

  Future<void> start({int sampleRate = 24000}) async {
    try {
      if (Platform.isWindows || Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
        _audioStream = getAudioStream();
        _audioStream!.init(
            bufferMilliSec: 30000, // 30 second ring buffer for faster-than-realtime streams
            waitingBufferMilliSec: 100,
            channels: 1,
            sampleRate: sampleRate);
        _audioStream!.resume();
      } else {
        await _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});
      }
    } on MissingPluginException {
      // Non-Android targets can still receive transcripts without native audio.
    }
  }

  Future<void> playPcm16(Uint8List bytes, {int sampleRate = 24000}) async {
    try {
      if (Platform.isWindows || Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
        if (_audioStream != null) {
          final float32List = Float32List(bytes.length ~/ 2);
          final byteData = ByteData.sublistView(bytes);
          for (var i = 0; i < float32List.length; i++) {
            float32List[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
          }
          _audioStream!.push(float32List);
        }
      } else {
        await _channel.invokeMethod<void>('play', bytes);
      }
    } on MissingPluginException {
      // Keep Live usable for text transcripts where native playback is absent.
    }
  }

  Future<void> stop() async {
    try {
      if (Platform.isWindows || Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
        _audioStream?.uninit();
        _audioStream = null;
      } else {
        await _channel.invokeMethod<void>('stop');
      }
    } on MissingPluginException {
      // No platform audio player registered.
    }
  }
}
