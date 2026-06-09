import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class LiveCameraFeed extends StatefulWidget {
  const LiveCameraFeed({super.key, required this.useFrontCamera});

  final bool useFrontCamera;

  @override
  State<LiveCameraFeed> createState() => _LiveCameraFeedState();
}

class _LiveCameraFeedState extends State<LiveCameraFeed> {
  CameraController? _controller;
  Timer? _timer;
  String? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(
            () => _error = 'No cameras found. Please check permissions.',
          );
        }
        return;
      }

      final direction = widget.useFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final preferred = cameras.firstWhere(
        (camera) => camera.lensDirection == direction,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        preferred,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;

      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_captureFrame()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Camera init error: $error');
      debugPrint('Camera init error: $error');
    }
  }

  Future<void> _restartCamera() async {
    _timer?.cancel();
    _timer = null;
    final oldController = _controller;
    _controller = null;
    _error = null;
    _capturing = false;
    if (mounted) setState(() {});
    await oldController?.dispose();
    if (mounted) await _initCamera();
  }

  Future<void> _captureFrame() async {
    if (!mounted || _capturing) return;
    final app = context.read<AdoetzAppState>();
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !app.isLiveActive) {
      return;
    }

    _capturing = true;
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      app.sendLiveVideoFrame(bytes, mimeType: file.mimeType ?? 'image/jpeg');
    } catch (error) {
      debugPrint('Camera capture error: $error');
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      return _CameraError(message: _error!);
    }
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final previewSize = controller.value.previewSize;
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize?.height ?? 1,
          height: previewSize?.width ?? 1,
          child: CameraPreview(controller),
        ),
      ),
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
