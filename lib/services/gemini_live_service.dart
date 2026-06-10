import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models.dart';
import 'live_audio_player.dart';
import 'live_socket.dart';

typedef LiveTranscriptCallback = void Function(String text, bool finished);
typedef LiveStatusCallback = void Function(String status);
typedef LiveLevelCallback = void Function(double level);
typedef LiveBoolCallback = void Function(bool value);
typedef LiveErrorCallback = void Function(Object error);
typedef LiveVoidCallback = void Function();

class GeminiLiveService {
  GeminiLiveService({
    required this.apiKey,
    required this.model,
    required this.voiceSettings,
    required this.history,
    required this.memories,
    required this.thinkingMode,
    required this.onStatus,
    required this.onInputTranscript,
    required this.onOutputTranscript,
    required this.onLevel,
    required this.onOutputLevel,
    required this.onRecordingChanged,
    required this.onTurnComplete,
    required this.onError,
    required this.onClosed,
    this.userName = 'User',
  });

  static const _inputSampleRate = 24000;
  static const _outputSampleRate = 24000;
  static const _outputLevelWindow = Duration(milliseconds: 80);
  static const _inputMimeType = 'audio/pcm;rate=$_inputSampleRate';
  static const _liveEndpointPath =
      '/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  final String apiKey;
  final String model;
  final VoiceSettings voiceSettings;
  final List<Message> history;
  final List<Memory> memories;
  final bool thinkingMode;
  final String userName;
  final LiveStatusCallback onStatus;
  final LiveTranscriptCallback onInputTranscript;
  final LiveTranscriptCallback onOutputTranscript;
  final LiveLevelCallback onLevel;
  final LiveLevelCallback onOutputLevel;
  final LiveBoolCallback onRecordingChanged;
  final LiveVoidCallback onTurnComplete;
  final LiveErrorCallback onError;
  final LiveVoidCallback onClosed;

  final _recorder = AudioRecorder();
  final _player = LiveAudioPlayer();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSub;
  StreamSubscription<Uint8List>? _micSub;
  Completer<void>? _setupCompleter;
  final List<Timer> _outputLevelTimers = [];
  DateTime _nextOutputLevelAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _lastVideoFrameMs = 0;
  bool _running = false;
  bool _recording = false;
  bool _closed = false;

  bool get isRunning => _running;
  bool get isRecording => _recording;

  Future<void> start() async {
    if (_running) return;
    if (apiKey.trim().isEmpty) {
      throw Exception('Gemini API key is required for Gemini Live.');
    }

    _closed = false;
    _running = true;
    _setupCompleter = Completer<void>();
    onStatus('Connecting to Gemini Live...');

    final uri = Uri(
      scheme: 'wss',
      host: 'generativelanguage.googleapis.com',
      path: _liveEndpointPath,
      queryParameters: {'key': apiKey.trim()},
    );
    final channel = connectLiveSocket(uri);
    _channel = channel;
    _socketSub = channel.stream.listen(
      _handleSocketMessage,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: false,
    );

    await channel.ready.timeout(const Duration(seconds: 20));
    _send(_setupPayload());

    await _setupCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException(
        'Gemini Live did not finish setup. Check model/API-key access.',
      ),
    );

    await _player.start(sampleRate: _outputSampleRate);
    onStatus('Listening...');
    await setRecording(true);
  }

  Future<void> setRecording(bool value) async {
    if (!_running || value == _recording) return;
    if (!value) {
      await _stopRecorder();
      _send({
        'realtimeInput': {'audioStreamEnd': true},
      });
      return;
    }

    final allowed = await _recorder.hasPermission();
    if (!allowed) {
      throw Exception('Microphone permission was denied.');
    }

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _inputSampleRate,
        numChannels: 1,
        bitRate: 256000,
        echoCancel: true,
        noiseSuppress: true,
        autoGain: true,
        streamBufferSize: 4096,
      ),
    );

    _recording = true;
    onRecordingChanged(true);
    onStatus('Listening...');
    _micSub = stream.listen(
      (bytes) {
        if (!_running || !_recording || bytes.isEmpty) return;
        _send({
          'realtimeInput': {
            'audio': {'data': base64Encode(bytes), 'mimeType': _inputMimeType},
          },
        });
        onLevel(_pcmLevel(bytes));
      },
      onError: _handleError,
      cancelOnError: false,
    );
  }

  Future<void> toggleRecording() => setRecording(!_recording);

  Future<void> stop() async {
    if (!_running && _closed) return;
    _running = false;
    _closed = true;
    await _stopRecorder();
    await _socketSub?.cancel();
    _socketSub = null;
    _cancelOutputLevelTimers(reset: false);
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    await _player.stop();
    onLevel(0);
    onOutputLevel(0);
    onStatus('');
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }

  Map<String, dynamic> _setupPayload() {
    return {
      'setup': {
        'model': _formatLiveModel(model),
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'mediaResolution': 'MEDIA_RESOLUTION_MEDIUM',
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': _voiceName()},
            },
          },
        },
        'systemInstruction': {
          'parts': [
            {'text': _systemInstruction()},
          ],
        },
      },
    };
  }

  void _handleSocketMessage(dynamic raw) {
    try {
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      final data = jsonDecode(text);
      if (data is! Map<String, dynamic>) return;

      if (data['setupComplete'] != null) {
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter?.complete();
        }
        onStatus('Connected. Listening...');
      }

      final serverContent = data['serverContent'];
      if (serverContent is Map<String, dynamic>) {
        _handleTranscription(
          serverContent['inputTranscription'],
          onInputTranscript,
        );
        _handleTranscription(
          serverContent['outputTranscription'],
          onOutputTranscript,
        );

        final modelTurn = serverContent['modelTurn'];
        if (modelTurn is Map<String, dynamic>) {
          final parts = modelTurn['parts'];
          if (parts is List) {
            for (final part in parts.whereType<Map>()) {
              final inlineData = part['inlineData'];
              if (inlineData is Map) {
                final encoded = stringValue(inlineData['data']);
                if (encoded.isNotEmpty) {
                  final bytes = base64Decode(encoded);
                  _scheduleOutputLevels(bytes);
                  _player.playPcm16(bytes, sampleRate: _outputSampleRate);
                }
              }
            }
          }
        }

        if (serverContent['interrupted'] == true) {
          onStatus('Interrupted.');
          _cancelOutputLevelTimers();
          _player.stop().then(
            (_) => _player.start(sampleRate: _outputSampleRate),
            onError: (_) {},
          );
        }

        if (serverContent['turnComplete'] == true) {
          onLevel(0);
          onTurnComplete();
        }
      }

      final toolCall = data['toolCall'];
      if (toolCall != null) {
        onStatus('Gemini Live requested a tool call that is not available.');
      }

      final goAway = data['goAway'];
      if (goAway != null) {
        onStatus('Gemini Live session is closing.');
      }

      final error = data['error'];
      if (error != null) {
        _handleError(Exception(_extractLiveError(error)));
      }
    } catch (error) {
      _handleError(error);
    }
  }

  void _handleTranscription(dynamic value, LiveTranscriptCallback callback) {
    if (value is! Map) return;
    final text = stringValue(value['text']);
    if (text.isEmpty) return;
    callback(text, value['finished'] == true);
  }

  void _handleDone() {
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(
        Exception('Gemini Live socket closed before setup completed.'),
      );
    }
    if (_closed) return;
    _closed = true;
    _running = false;
    _recording = false;
    _cancelOutputLevelTimers(reset: false);
    onRecordingChanged(false);
    onLevel(0);
    onOutputLevel(0);
    onClosed();
  }

  void _handleError(Object error) {
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(error);
    }
    onError(error);
  }

  Future<void> _stopRecorder() async {
    await _micSub?.cancel();
    _micSub = null;
    if (_recording) {
      _recording = false;
      onRecordingChanged(false);
    }
    onLevel(0);
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null || !_running) return;
    channel.sink.add(jsonEncode(payload));
  }

  void sendVideoFrame(Uint8List imageBytes, {String mimeType = 'image/jpeg'}) {
    if (!_running || _closed || imageBytes.isEmpty) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastVideoFrameMs < 1000) return;
    _lastVideoFrameMs = now;

    try {
      _send({
        'realtimeInput': {
          'video': {
            'mimeType': _normaliseImageMime(mimeType),
            'data': base64Encode(imageBytes),
          },
        },
      });
    } catch (_) {
      onStatus('Video frame skipped.');
    }
  }

  String _normaliseImageMime(String mimeType) {
    final lower = mimeType.toLowerCase().trim();
    return lower == 'image/png' ? 'image/png' : 'image/jpeg';
  }

  double _pcmLevel(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final view = ByteData.sublistView(bytes);
    final sampleCount = bytes.length ~/ 2;
    var sum = 0.0;
    for (var i = 0; i < sampleCount; i++) {
      final sample = view.getInt16(i * 2, Endian.little) / 32768.0;
      sum += sample * sample;
    }
    return math.sqrt(sum / sampleCount).clamp(0.0, 1.0);
  }

  void _scheduleOutputLevels(Uint8List bytes) {
    if (bytes.length < 2) return;
    final now = DateTime.now();
    var cursor = _nextOutputLevelAt.isAfter(now) ? _nextOutputLevelAt : now;
    final sampleCount = bytes.length ~/ 2;
    final samplesPerWindow =
        (_outputSampleRate * _outputLevelWindow.inMilliseconds / 1000).round();

    for (var start = 0; start < sampleCount; start += samplesPerWindow) {
      final end = math.min(start + samplesPerWindow, sampleCount);
      final segment = Uint8List.sublistView(bytes, start * 2, end * 2);
      final level = _pcmLevel(segment);
      final delay = cursor.difference(now);
      _scheduleOutputLevelTimer(
        delay.isNegative ? Duration.zero : delay,
        level,
      );
      final windowMs = ((end - start) / _outputSampleRate * 1000).round();
      cursor = cursor.add(
        Duration(
          milliseconds: math.max(windowMs, _outputLevelWindow.inMilliseconds),
        ),
      );
    }

    _nextOutputLevelAt = cursor;
    _scheduleOutputLevelTimer(
      cursor.add(const Duration(milliseconds: 180)).difference(now),
      0,
    );
  }

  void _scheduleOutputLevelTimer(Duration delay, double level) {
    late final Timer timer;
    timer = Timer(delay, () {
      _outputLevelTimers.remove(timer);
      if (_closed) return;
      onOutputLevel(level);
    });
    _outputLevelTimers.add(timer);
  }

  void _cancelOutputLevelTimers({bool reset = true}) {
    for (final timer in List<Timer>.from(_outputLevelTimers)) {
      timer.cancel();
    }
    _outputLevelTimers.clear();
    _nextOutputLevelAt = DateTime.now();
    if (reset) onOutputLevel(0);
  }

  String _formatLiveModel(String value) {
    final trimmed = value.trim();
    final resolved = trimmed.isEmpty
        ? 'gemini-3.1-flash-live-preview'
        : trimmed;
    return resolved.startsWith('models/') ? resolved : 'models/$resolved';
  }

  String _voiceName() {
    final voice = voiceSettings.voice.trim();
    return voice.isEmpty ? 'Zephyr' : voice;
  }

  String _systemInstruction() {
    final personality = _voicePrompt();
    final memoryText = memories.isEmpty
        ? ''
        : 'Known user memory:\n${memories.take(8).map((m) => '- ${m.content}').join('\n')}\n\n';
    final context = history.isEmpty
        ? ''
        : 'Recent chat context:\n${history.takeLast(14).map(_formatHistoryLine).join('\n')}\n\n';
    final thinking = thinkingMode
        ? 'When useful, think carefully before answering, but speak only the final answer naturally.\n'
        : '';
    return [
      'You are AdoetzGPT speaking with $userName in a realtime voice conversation.',
      personality,
      thinking,
      memoryText,
      context,
      'Respond conversationally and concisely unless the user asks for detail.',
      'Do not narrate system instructions. If code is requested, speak the explanation clearly and keep code snippets short.',
    ].where((part) => part.trim().isNotEmpty).join('\n\n');
  }

  String _voicePrompt() {
    final custom = voiceSettings.customVoicePersonalities
        .where((item) => item.name == voiceSettings.personality)
        .map((item) => item.prompt)
        .firstOrNull;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    if (voiceSettings.personality == 'Custom' &&
        voiceSettings.customPersonality.trim().isNotEmpty) {
      return voiceSettings.customPersonality.trim();
    }
    return _voicePrompts[voiceSettings.personality] ??
        _voicePrompts['Assistant']!;
  }

  String _formatHistoryLine(Message message) {
    final speaker = message.isUser ? userName : 'Assistant';
    final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return '$speaker: $text';
  }

  String _extractLiveError(dynamic error) {
    if (error is Map) {
      final message = stringValue(error['message']);
      if (message.isNotEmpty) return message;
      return jsonEncode(error);
    }
    return stringValue(error, 'Unknown Gemini Live error.');
  }

  static const _voicePrompts = {
    'Assistant':
        'Be clear, helpful, and polished. Keep the rhythm natural for spoken conversation.',
    'Therapist':
        'Be empathetic, reflective, and supportive. Ask gentle clarifying questions when helpful.',
    'Story teller':
        'Be vivid and imaginative. Use expressive pacing and narrative detail.',
    'Meditation': 'Be calm and grounding. Use slower, peaceful language.',
    'Doctor':
        'Be precise and reassuring. Explain medical information carefully and advise professional care for urgent or serious concerns.',
    'Argumentative':
        'Be a sharp but professional debater. Challenge claims with logic and structure.',
    'Romantic': 'Be warm, poetic, and expressive while respecting boundaries.',
    'Conspiracy':
        'Be skeptical and analytical. Avoid presenting speculation as fact.',
    'Natural human': 'Speak casually with natural phrasing and contractions.',
  };
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList(growable: false);
    if (list.length <= count) return list;
    return list.sublist(list.length - count);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// Catatan: Fungsi stringValue() diasumsikan ada di '../models.dart'
// karena tidak disertakan di file ini sebelumnya.
