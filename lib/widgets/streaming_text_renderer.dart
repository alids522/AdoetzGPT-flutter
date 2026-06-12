import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StreamingTextRenderer extends StatefulWidget {
  const StreamingTextRenderer({
    super.key,
    required this.receivedText,
    required this.isStreaming,
    required this.textStyle,
    this.accentColor = const Color(0xff10b981),
    this.enableHaptics = false,
    this.onVisibleTextChanged,
    this.onFinishedVisualReveal,
    this.revealMode = StreamingRevealMode.smooth,
  });

  final String receivedText;
  final bool isStreaming;
  final TextStyle textStyle;
  final Color accentColor;
  final bool enableHaptics;
  final ValueChanged<String>? onVisibleTextChanged;
  final VoidCallback? onFinishedVisualReveal;
  final StreamingRevealMode revealMode;

  @override
  State<StreamingTextRenderer> createState() => _StreamingTextRendererState();
}

enum StreamingRevealMode { smooth, fast, instant }

class _StreamingTextRendererState extends State<StreamingTextRenderer>
    with SingleTickerProviderStateMixin {
  // Visual pacing constants. These only affect reveal speed, never API/network
  // chunk receiving. The renderer keeps old text stable and only animates the
  // active tail to avoid expensive per-character widgets on long responses.
  static const _tickInterval = Duration(milliseconds: 34);
  static const _fadeDuration = Duration(milliseconds: 180);
  static const _hapticInterval = Duration(milliseconds: 82);
  static const _finishedCatchUpWords = 46;
  static const _smallBacklogWords = 3;
  static const _mediumBacklogWords = 10;
  static const _largeBacklogWords = 30;
  static const _activeTailChars = 240;
  static const _streamingHeadChars = 4200;
  static const _streamingTailChars = 4200;
  static const _longStreamingLimit = 10000;

  late final AnimationController _fadeController;
  Timer? _ticker;
  DateTime? _lastHapticAt;
  String _visibleText = '';
  int _visibleEnd = 0;
  bool _finishedNotified = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: _fadeDuration)
      ..value = 1;
    if (widget.revealMode == StreamingRevealMode.instant) {
      _snapToReceived(notify: false);
    } else {
      _scheduleTicker();
    }
  }

  @override
  void didUpdateWidget(covariant StreamingTextRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.receivedText.length < _visibleEnd ||
        !widget.receivedText.startsWith(_visibleText)) {
      _visibleText = '';
      _visibleEnd = 0;
      _finishedNotified = false;
    }
    if (widget.receivedText != oldWidget.receivedText ||
        widget.isStreaming != oldWidget.isStreaming ||
        widget.revealMode != oldWidget.revealMode) {
      if (widget.revealMode == StreamingRevealMode.instant) {
        _snapToReceived();
      } else {
        _finishedNotified = false;
        _scheduleTicker();
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    _lastHapticAt = null;
    _fadeController.dispose();
    super.dispose();
  }

  void _scheduleTicker() {
    if (_ticker != null) return;
    _ticker = Timer(_tickInterval, _tick);
  }

  void _tick() {
    _ticker = null;
    if (!mounted) return;

    final received = widget.receivedText;
    if (_visibleEnd >= received.length) {
      _notifyFinishedIfNeeded();
      return;
    }

    final oldVisible = _visibleText;
    final nextEnd = _nextRevealIndex(received);
    _visibleEnd = nextEnd.clamp(0, received.length);
    _visibleText = received.substring(0, _visibleEnd);
    _fadeController.forward(from: 0);
    widget.onVisibleTextChanged?.call(_visibleText);
    _maybeHaptic(_visibleText.length - oldVisible.length);

    setState(() {});
    if (_visibleEnd < received.length || widget.isStreaming) {
      _scheduleTicker();
    } else {
      _notifyFinishedIfNeeded();
    }
  }

  int _nextRevealIndex(String received) {
    final backlog = received.length - _visibleEnd;
    if (backlog <= 0) return received.length;

    final words = widget.isStreaming
        ? _wordsPerTick(backlog)
        : math.max(_finishedCatchUpWords, _wordsPerTick(backlog));
    return _advanceByWords(received, _visibleEnd, words);
  }

  int _wordsPerTick(int backlogChars) {
    if (widget.revealMode == StreamingRevealMode.fast) {
      if (backlogChars > 4500) return 38;
      if (backlogChars > 1200) return 18;
      return 6;
    }
    if (backlogChars > 7000) return _largeBacklogWords;
    if (backlogChars > 1800) return _mediumBacklogWords;
    return _smallBacklogWords;
  }

  int _advanceByWords(String text, int start, int wordCount) {
    var end = start;
    var seen = 0;
    for (final match in RegExp(r'\S+\s*').allMatches(text, start)) {
      end = match.end;
      seen += 1;
      if (seen >= wordCount) return end;
    }
    if (end > start) return end;
    return math.min(text.length, start + math.max(16, wordCount * 8));
  }

  void _snapToReceived({bool notify = true}) {
    _ticker?.cancel();
    _ticker = null;
    _visibleText = widget.receivedText;
    _visibleEnd = widget.receivedText.length;
    _fadeController.value = 1;
    if (notify) {
      widget.onVisibleTextChanged?.call(_visibleText);
      if (mounted) setState(() {});
    }
    _notifyFinishedIfNeeded();
  }

  void _notifyFinishedIfNeeded() {
    if (_finishedNotified || widget.isStreaming) return;
    if (_visibleEnd < widget.receivedText.length) return;
    _finishedNotified = true;
    _lastHapticAt = null;
    widget.onFinishedVisualReveal?.call();
  }

  void _maybeHaptic(int deltaChars) {
    if (!widget.enableHaptics ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        deltaChars < 8) {
      return;
    }
    final now = DateTime.now();
    final last = _lastHapticAt;
    if (last != null && now.difference(last) < _hapticInterval) return;
    _lastHapticAt = now;
    if (deltaChars > 220) {
      unawaited(HapticFeedback.mediumImpact());
    } else {
      unawaited(HapticFeedback.lightImpact());
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayText(_visibleText);
    final split = math.max(0, display.length - _activeTailChars);
    final stable = display.substring(0, split);
    final active = display.substring(split);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _fadeController,
        builder: (context, _) {
          final opacity = Curves.easeOutCubic.transform(_fadeController.value);
          final baseStyle = widget.textStyle;
          final activeColor = Color.lerp(
            baseStyle.color ?? Colors.white,
            widget.accentColor,
            0.12,
          );
          return Text.rich(
            TextSpan(
              children: [
                if (stable.isNotEmpty) TextSpan(text: stable, style: baseStyle),
                if (active.isNotEmpty)
                  TextSpan(
                    text: active,
                    style: baseStyle.copyWith(
                      color: activeColor?.withValues(
                        alpha: 0.76 + 0.24 * opacity,
                      ),
                      shadows: [
                        Shadow(
                          color: widget.accentColor.withValues(
                            alpha: 0.04 + 0.05 * opacity,
                          ),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            softWrap: true,
            textAlign: TextAlign.start,
          );
        },
      ),
    );
  }

  String _displayText(String value) {
    if (value.length <= _longStreamingLimit) return value;
    final head = value.substring(0, _streamingHeadChars).trimRight();
    final tail = value.substring(value.length - _streamingTailChars).trimLeft();
    return '$head\n\n...\n\n$tail';
  }
}
