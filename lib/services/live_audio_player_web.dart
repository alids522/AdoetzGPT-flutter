import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class LiveAudioPlayer {
  web.AudioContext? _context;
  double _nextPlayTime = 0;

  Future<void> start({int sampleRate = 24000}) async {
    final existing = _context;
    if (existing != null) {
      try {
        await existing.resume().toDart;
      } catch (_) {}
      _nextPlayTime = math.max(_nextPlayTime, existing.currentTime + 0.03);
      return;
    }
    final context = web.AudioContext(
      web.AudioContextOptions(sampleRate: sampleRate),
    );
    _context = context;
    _nextPlayTime = context.currentTime + 0.04;
    try {
      await context.resume().toDart;
    } catch (_) {}
  }

  Future<void> playPcm16(Uint8List bytes, {int sampleRate = 24000}) async {
    if (bytes.isEmpty) return;
    if (_context == null) {
      await start(sampleRate: sampleRate);
    }
    final context = _context;
    if (context == null) return;

    final samples = _pcm16ToFloat32(bytes);
    if (samples.isEmpty) return;

    final buffer = context.createBuffer(1, samples.length, sampleRate);
    buffer.copyToChannel(samples.toJS, 0);

    final source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);

    final startAt = math.max(_nextPlayTime, context.currentTime + 0.02);
    source.start(startAt);
    _nextPlayTime = startAt + samples.length / sampleRate;
  }

  Future<void> stop() async {
    final context = _context;
    _context = null;
    _nextPlayTime = 0;
    if (context == null) return;
    try {
      await context.close().toDart;
    } catch (_) {}
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final view = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      final value = view.getInt16(i * 2, Endian.little);
      samples[i] = (value / 32768).clamp(-1.0, 1.0);
    }
    return samples;
  }
}
