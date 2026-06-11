import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;

import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;

import '../state/app_state.dart';

class LiveCameraFeed extends StatefulWidget {
  const LiveCameraFeed({super.key, required this.useFrontCamera});

  final bool useFrontCamera;

  @override
  State<LiveCameraFeed> createState() => _LiveCameraFeedState();
}

class _LiveCameraFeedState extends State<LiveCameraFeed> {
  late final String _viewType =
      'adoetz-live-camera-${DateTime.now().microsecondsSinceEpoch}';
  late final web.HTMLVideoElement _video;
  web.HTMLCanvasElement? _canvas;
  web.MediaStream? _stream;
  Timer? _timer;
  String? _error;
  bool _capturing = false;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..playsInline = true;
    _video.style
      ..setProperty('width', '100%')
      ..setProperty('height', '100%')
      ..setProperty('object-fit', 'cover')
      ..setProperty('pointer-events', 'none')
      ..setProperty('background', '#000');
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _video,
    );
    unawaited(_initCamera());
  }

  @override
  void didUpdateWidget(covariant LiveCameraFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.useFrontCamera != widget.useFrontCamera) {
      unawaited(_restartCamera());
    }
  }

  Future<void> _initCamera() async {
    try {
      final stream = await web.window.navigator.mediaDevices
          .getUserMedia(
            web.MediaStreamConstraints(
              video: _videoConstraints(),
              audio: false.toJS,
            ),
          )
          .toDart;
      if (!mounted) {
        _stopStream(stream);
        return;
      }

      _stream = stream;
      _video.srcObject = stream;
      try {
        await _video.play().toDart;
      } catch (_) {
        // Muted camera previews normally autoplay; the frame sampler can still
        // work after the browser starts the stream.
      }

      if (!mounted) return;
      setState(() => _ready = true);
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _captureFrame(),
      );
      _captureFrame();
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera init error: $error');
      debugPrint('Camera init error: $error');
    }
  }

  Future<void> _restartCamera() async {
    _timer?.cancel();
    _timer = null;
    final oldStream = _stream;
    _stream = null;
    _video.pause();
    _video.srcObject = null;
    _error = null;
    _capturing = false;
    _ready = false;
    if (mounted) setState(() {});
    if (oldStream != null) _stopStream(oldStream);
    if (mounted) await _initCamera();
  }

  JSAny _videoConstraints() {
    return {
      'facingMode': {'ideal': widget.useFrontCamera ? 'user' : 'environment'},
      'width': {'ideal': 1280},
      'height': {'ideal': 720},
      'frameRate': {'ideal': 15, 'max': 24},
    }.jsify()!;
  }

  void _captureFrame() {
    if (!mounted || _capturing || _disposed) return;
    final app = context.read<AdoetzAppState>();
    if (!app.isLiveActive ||
        _video.videoWidth <= 0 ||
        _video.videoHeight <= 0) {
      return;
    }

    _capturing = true;
    try {
      final width = _video.videoWidth;
      final height = _video.videoHeight;
      final largestSide = math.max(width, height);
      final scale = largestSide > 960 ? 960 / largestSide : 1.0;
      final targetWidth = math.max(1, (width * scale).round());
      final targetHeight = math.max(1, (height * scale).round());
      final canvas = _canvas ??= web.HTMLCanvasElement();
      canvas.width = targetWidth;
      canvas.height = targetHeight;

      final context2d =
          canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context2d == null) return;
      context2d.drawImage(_video, 0, 0, targetWidth, targetHeight);

      final dataUrl = canvas.toDataURL('image/jpeg', 0.78.toJS);
      final comma = dataUrl.indexOf(',');
      if (comma == -1) return;
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      app.sendLiveVideoFrame(bytes, mimeType: 'image/jpeg');
    } catch (error) {
      debugPrint('Camera frame error: $error');
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _video.pause();
    _video.srcObject = null;
    final stream = _stream;
    if (stream != null) _stopStream(stream);
    super.dispose();
  }

  void _stopStream(web.MediaStream stream) {
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _CameraError(message: _error!);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        HtmlElementView(viewType: _viewType),
        if (!_ready) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.black.withValues(alpha: 0.7),
        child: Text(
          message,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
