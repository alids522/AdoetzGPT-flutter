import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../services/ai_service.dart';
import '../state/app_state.dart';
import '../translations.dart';
import '../ui/app_theme.dart';
import '../widgets/live_camera_feed.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final input = TextEditingController();
  final scrollController = ScrollController();
  final attachments = <AttachmentData>[];
  String? editingId;
  final editController = TextEditingController();

  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    input.addListener(_rebuildForInput);
    scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final show =
        scrollController.offset <
        scrollController.position.maxScrollExtent - 150;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  @override
  void dispose() {
    input.removeListener(_rebuildForInput);
    input.dispose();
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    editController.dispose();
    super.dispose();
  }

  void _rebuildForInput() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    if (app.isLiveVideoEnabled) {
      return _LiveVideoStage(app: app);
    }

    final session = app.currentSession;
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: session.messages.isEmpty
              ? const _EmptyState()
              : _MessageList(
                  controller: scrollController,
                  editingId: editingId,
                  editController: editController,
                  onEditStart: _startEdit,
                  onEditCancel: _cancelEdit,
                  onEditSave: _saveEdit,
                ),
        ),

        if (_showScrollToBottom)
          Positioned(
            right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 168,
            child: FloatingActionButton.small(
              backgroundColor: p.surface,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: p.outline),
              ),
              onPressed: () {
                scrollController.animateTo(
                  scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              child: Icon(LucideIcons.arrowDown, color: p.onSurface, size: 20),
            ),
          ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                8,
                18,
                8,
                MediaQuery.of(context).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    p.background.withValues(alpha: 0),
                    p.background.withValues(alpha: 0.94),
                    p.background,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (attachments.isNotEmpty)
                    _AttachmentTray(
                      files: attachments,
                      onRemove: (index) =>
                          setState(() => attachments.removeAt(index)),
                    ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: SizedBox(
                      width: double.infinity,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 600),
                        reverseDuration: const Duration(milliseconds: 400),
                        switchInCurve: Curves
                            .easeOutBack, // Mimics spring stiffness 400 damping 15
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          final isIncoming =
                              child.key ==
                              (app.isLiveActive || app.isLiveConnecting
                                  ? const ValueKey('voice-overlay')
                                  : const ValueKey('input-pod'));

                          return AnimatedBuilder(
                            animation: animation,
                            builder: (context, childWidget) {
                              final offsetY = isIncoming
                                  ? Tween<double>(
                                      begin: 80.0,
                                      end: 0.0,
                                    ).evaluate(animation)
                                  : Tween<double>(
                                      begin: -80.0,
                                      end: 0.0,
                                    ).evaluate(animation);
                              return Transform.translate(
                                offset: Offset(0, offsetY),
                                child: Opacity(
                                  opacity: animation.value.clamp(0.0, 1.0),
                                  child: childWidget,
                                ),
                              );
                            },
                            child: child,
                          );
                        },
                        child: app.isLiveActive || app.isLiveConnecting
                            ? _VoiceOverlay(
                                key: const ValueKey('voice-overlay'),
                                recording: app.isLiveRecording,
                                connecting: app.isLiveConnecting,
                                status: app.liveStatus,
                                level: app.liveInputLevel,
                                outputLevel: app.liveOutputLevel,
                                onRecording: () =>
                                    unawaited(app.toggleLiveRecording()),
                                onClose: () =>
                                    unawaited(app.stopLiveConversation()),
                              )
                            : _InputPod(
                                key: const ValueKey('input-pod'),
                                input: input,
                                attachments: attachments,
                                onPick: _showAttachMenu,
                                onSend: _sendOrLive,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _sendOrLive() {
    final app = context.read<AdoetzAppState>();
    if (app.isGenerating) {
      app.stopGeneration();
      return;
    }
    if (input.text.trim().isEmpty && attachments.isEmpty) {
      FocusScope.of(context).unfocus();
      unawaited(app.startLiveConversation());
      return;
    }
    final text = input.text;
    final files = List<AttachmentData>.from(attachments);
    input.clear();
    setState(attachments.clear);
    app.sendMessage(text, files);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showAttachMenu() {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: p.isDark ? const Color(0xff111111) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Transform.scale(
            scale: 0.94 + value * 0.06,
            alignment: Alignment.bottomCenter,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AttachAction(
                  icon: LucideIcons.image,
                  label: 'Photo',
                  onTap: () => _pickFiles(FileType.image),
                ),
                _AttachAction(
                  icon: LucideIcons.video,
                  label: 'Video',
                  onTap: () => _pickFiles(FileType.video),
                ),
                _AttachAction(
                  icon: LucideIcons.fileText,
                  label: 'File',
                  onTap: () => _pickFiles(FileType.custom),
                ),
                _AttachAction(
                  icon: LucideIcons.camera,
                  label: 'Camera',
                  onTap: _captureImage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles(FileType type) async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowMultiple: true,
      withData: true,
      allowedExtensions: type == FileType.custom
          ? const ['pdf', 'doc', 'docx', 'txt', 'md', 'json', 'csv']
          : null,
    );
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null) continue;
      if (bytes.length > 5000000 &&
          !(lookupMimeType(
                file.name,
                headerBytes: bytes,
              )?.startsWith('image/') ??
              false)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File "${file.name}" is too large. Please upload files under 5MB.',
              ),
            ),
          );
        }
        continue;
      }
      final mime =
          lookupMimeType(file.name, headerBytes: bytes) ??
          'application/octet-stream';
      attachments.add(
        AttachmentData(name: file.name, type: mime, data: base64Encode(bytes)),
      );
    }
    setState(() {});
  }

  Future<void> _captureImage() async {
    Navigator.pop(context);
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 72,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    setState(
      () => attachments.add(
        AttachmentData(
          name: image.name,
          type: lookupMimeType(image.name, headerBytes: bytes) ?? 'image/jpeg',
          data: base64Encode(bytes),
        ),
      ),
    );
  }

  void _startEdit(Message message) {
    setState(() {
      editingId = message.id;
      editController.text = message.text;
    });
  }

  void _cancelEdit() {
    setState(() {
      editingId = null;
      editController.clear();
    });
  }

  void _saveEdit(Message message) {
    final text = editController.text.trim();
    if (text.isEmpty) return;
    context.read<AdoetzAppState>().editMessage(message.id, text);
    _cancelEdit();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final name = app.userName.trim().isEmpty ? 'there' : app.userName.trim();
    final greeting = app.language == AppLanguage.en
        ? 'Good to see you, $name.'
        : 'Senang bertemu lagi, $name.';
    final subtitle = app.language == AppLanguage.en
        ? 'I am ready when you are.'
        : 'Aku siap kapan pun kamu mau mulai.';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 220),
      children: [
        const SizedBox(height: 40),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  p.primary.withValues(alpha: 0.16),
                  p.primary.withValues(alpha: 0.02),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: p.primary.withValues(alpha: 0.08),
                  blurRadius: 60,
                ),
              ],
            ),
            child: const Center(child: SparkleMark(size: 54)),
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: Text(
            greeting,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 28,
              color: p.onSurface,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: p.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.controller,
    required this.editingId,
    required this.editController,
    required this.onEditStart,
    required this.onEditCancel,
    required this.onEditSave,
  });

  final ScrollController controller;
  final String? editingId;
  final TextEditingController editController;
  final ValueChanged<Message> onEditStart;
  final VoidCallback onEditCancel;
  final ValueChanged<Message> onEditSave;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final messages = app.currentSession.messages;
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 72, 14, 240),
      itemCount: messages.length + 1,
      itemBuilder: (context, index) {
        if (index == messages.length) return const SizedBox(height: 12);
        final message = messages[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SizedBox(
              width: double.infinity,
              child: _MessageBubble(
                message: message,
                isLast: index == messages.length - 1,
                editing: editingId == message.id,
                editController: editController,
                onEditStart: () => onEditStart(message),
                onEditCancel: onEditCancel,
                onEditSave: () => onEditSave(message),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isLast,
    required this.editing,
    required this.editController,
    required this.onEditStart,
    required this.onEditCancel,
    required this.onEditSave,
  });

  final Message message;
  final bool isLast;
  final bool editing;
  final TextEditingController editController;
  final VoidCallback onEditStart;
  final VoidCallback onEditCancel;
  final VoidCallback onEditSave;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final parsed = parseText(message.text);
    final align = message.isUser
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;
    final screenWidth = MediaQuery.of(context).size.width;
    final laneWidth = math.min(980.0, math.max(280.0, screenWidth - 28));
    final maxWidth = message.isUser
        ? math.min(620.0, laneWidth * 0.72)
        : laneWidth;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 460),
            curve: Curves.easeOutBack,
            builder: (context, value, child) {
              final radius = message.isUser
                  ? BorderRadius.only(
                      topLeft: Radius.circular(50 - 26 * value),
                      topRight: Radius.circular(50 - 26 * value),
                      bottomLeft: Radius.circular(50 - 26 * value),
                      bottomRight: Radius.circular(50 - 46 * value),
                    )
                  : null;
              return Transform.scale(
                scale: 0.2 + 0.8 * value,
                alignment: message.isUser
                    ? Alignment.bottomRight
                    : Alignment.bottomLeft,
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Container(
                      padding: message.isUser
                          ? const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            )
                          : const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                      decoration: message.isUser
                          ? BoxDecoration(
                              color: p.primary,
                              borderRadius: radius,
                            )
                          : null,
                      child: child,
                    ),
                  ),
                ),
              );
            },
            child: editing
                ? Column(
                    children: [
                      TextField(
                        controller: editController,
                        minLines: 2,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          hintText: 'Edit message',
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: onEditCancel,
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: onEditSave,
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: message.isUser
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (!message.isUser && parsed.thinkContent != null)
                        _ThoughtBlock(
                          content: parsed.thinkContent!,
                          active: parsed.isThinkingStill,
                        ),
                      if (message.attachments.isNotEmpty)
                        _MessageAttachments(files: message.attachments),
                      if (message.isUser)
                        Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.45,
                          ),
                        )
                      else if (parsed.mainContent.isEmpty && app.isGenerating)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: _PolygonProgressionLoading(),
                        )
                      else
                        _MarkdownMessage(data: parsed.mainContent, palette: p),
                    ],
                  ),
          ),
          if (!editing)
            Padding(
              padding: EdgeInsets.only(
                top: 4,
                left: message.isUser ? 0 : 16,
                right: message.isUser ? 12 : 0,
              ),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TinyAction(
                    icon: LucideIcons.copy,
                    label: 'Copy',
                    onTap: () => Clipboard.setData(
                      ClipboardData(
                        text: message.isUser
                            ? message.text
                            : parsed.mainContent,
                      ),
                    ),
                  ),
                  if (message.isUser)
                    _TinyAction(
                      icon: LucideIcons.edit2,
                      label: 'Edit',
                      onTap: onEditStart,
                    ),
                  _TinyAction(
                    icon: LucideIcons.trash2,
                    label: 'Delete',
                    onTap: () => app.deleteMessage(message.id),
                  ),
                  if (!message.isUser && isLast && !app.isGenerating)
                    _TinyAction(
                      icon: LucideIcons.rotateCw,
                      label: 'Regenerate',
                      onTap: app.regenerateLast,
                    ),
                  if (!message.isUser && message.tokenCount != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${message.tokenCount} tokens',
                        style: TextStyle(
                          color: p.onSurfaceVariant.withValues(alpha: 0.55),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  if (!message.isUser && message.model != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        message.model!,
                        style: TextStyle(
                          color: p.onSurfaceVariant.withValues(alpha: 0.55),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThoughtBlock extends StatefulWidget {
  const _ThoughtBlock({required this.content, required this.active});

  final String content;
  final bool active;

  @override
  State<_ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<_ThoughtBlock> {
  final _controller = ScrollController();
  bool _collapsed = false;

  @override
  void didUpdateWidget(covariant _ThoughtBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_collapsed &&
        widget.active &&
        widget.content.length != oldWidget.content.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceDim,
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(
            color: p.primary.withValues(alpha: widget.active ? 0.85 : 0.45),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.active ? 'Thinking...' : 'Thoughts',
                  style: TextStyle(
                    color: p.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              IconButton(
                tooltip: _collapsed ? 'Expand thoughts' : 'Minimize thoughts',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _collapsed = !_collapsed),
                icon: Icon(
                  _collapsed ? LucideIcons.chevronDown : LucideIcons.chevronUp,
                  size: 16,
                  color: p.onSurfaceVariant,
                ),
              ),
            ],
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: Scrollbar(
                  controller: _controller,
                  thumbVisibility: widget.content.length > 420,
                  child: SingleChildScrollView(
                    controller: _controller,
                    child: SelectableText(
                      widget.content,
                      style: TextStyle(
                        color: p.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            crossFadeState: _collapsed
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 160),
          ),
        ],
      ),
    );
  }
}

class _MarkdownMessage extends StatelessWidget {
  const _MarkdownMessage({required this.data, required this.palette});

  final String data;
  final AppPalette palette;

  String _enhanceMathAndVariables(String text) {
    // 1. Apply the standalone variable formatter.
    // We match existing backtick blocks (`...`) to ignore them.
    return text.replaceAllMapped(
      RegExp(
        r'(`[^`]*`)|(?<!`)\b(O\([^)]+\)|\([a-zA-Z0-9\^_{}+\-/*=]+\)|\b[a-zA-Z0-9]+\^[{]?[a-zA-Z0-9]+[}]?\b)(?!`)',
      ),
      (match) {
        if (match.group(1) != null) {
          return match.group(1)!; // Existing code block, leave it alone
        }
        return '`${match.group(2)}`'; // Match standalone variable, wrap it
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final parts = _splitMarkdown(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: parts.map((part) {
        if (part.isCode) {
          return _CopyableCodeBlock(
            code: part.content,
            language: part.language,
            palette: palette,
          );
        }
        if (part.content.trim().isEmpty) return const SizedBox.shrink();

        final processedContent = _enhanceMathAndVariables(part.content);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: MarkdownBody(
            data: processedContent,
            selectable: true,
            styleSheet: _markdownStyle(context, palette),
            builders: {
              'code': _InlineCodeBuilder(palette),
              'latex': LatexElementBuilder(
                textStyle: TextStyle(color: palette.onSurface),
              ),
            },
            extensionSet: md.ExtensionSet(
              [
                LatexBlockSyntax(),
                ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
              ],
              [
                LatexInlineSyntax(),
                ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  List<_MarkdownPart> _splitMarkdown(String value) {
    final parts = <_MarkdownPart>[];
    final fence = RegExp(r'```([^\n`]*)\n?([\s\S]*?)```');
    var cursor = 0;
    for (final match in fence.allMatches(value)) {
      if (match.start > cursor) {
        parts.add(_MarkdownPart.text(value.substring(cursor, match.start)));
      }
      parts.add(
        _MarkdownPart.code(
          match.group(2)?.trimRight() ?? '',
          language: match.group(1)?.trim() ?? '',
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      parts.add(_MarkdownPart.text(value.substring(cursor)));
    }
    return parts.isEmpty ? [_MarkdownPart.text(value)] : parts;
  }

  MarkdownStyleSheet _markdownStyle(BuildContext context, AppPalette p) {
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bodyColor = isDark ? const Color(0xFFD1D5DB) : p.onSurface;

    final body = TextStyle(
      color: bodyColor,
      height: 1.6,
      fontSize: 15,
      fontWeight: FontWeight.normal,
    );
    final heading = TextStyle(
      color: p.onSurface,
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final strong = TextStyle(color: p.onSurface, fontWeight: FontWeight.w700);

    return base.copyWith(
      p: body,
      h1: heading.copyWith(fontSize: 18),
      h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
      h2: heading.copyWith(fontSize: 17),
      h2Padding: const EdgeInsets.only(top: 14, bottom: 6),
      h3: heading.copyWith(fontSize: 16),
      h3Padding: const EdgeInsets.only(top: 12, bottom: 4),
      strong: strong,
      listBullet: body,
      listIndent: 20,
      blockSpacing: 16.0,
      blockquote: TextStyle(
        color: bodyColor.withValues(alpha: 0.86),
        height: 1.5,
        fontSize: 15,
      ),
      blockquoteDecoration: BoxDecoration(
        color: p.surfaceDim,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: p.primary, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: p.onSurfaceVariant.withValues(alpha: 0.34)),
        ),
      ),
    );
  }
}

class _InlineCodeBuilder extends MarkdownElementBuilder {
  _InlineCodeBuilder(this.palette);
  final AppPalette palette;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(4.0),
        border: Border.all(color: palette.outline.withValues(alpha: 0.2)),
      ),
      child: Text(
        element.textContent,
        style: const TextStyle(
          color: Color(0xFFE5E7EB),
          fontSize: 13.5,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _PolygonProgressionLoading extends StatefulWidget {
  const _PolygonProgressionLoading();

  @override
  State<_PolygonProgressionLoading> createState() =>
      _PolygonProgressionLoadingState();
}

class _PolygonProgressionLoadingState extends State<_PolygonProgressionLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const double _dotSize = 6.0;
  static const double _dist = 16.0;

  static const List<List<double>> _xs = [
    [0, -1, 0, -0.8, 0, 0, 0],
    [0, 1, 0.866, 0.8, 0.951, 0.866, 0],
    [0, 0, -0.866, 0.8, 0.588, 0.866, 0],
    [0, 0, 0, -0.8, -0.588, 0, 0],
    [0, 0, 0, 0, -0.951, -0.866, 0],
    [0, 0, 0, 0, 0, -0.866, 0],
  ];

  static const List<List<double>> _ys = [
    [0, 0, -1, -0.8, -1, -1, 0],
    [0, 0, 0.5, -0.8, -0.309, -0.5, 0],
    [0, 0, 0.5, 0.8, 0.809, 0.5, 0],
    [0, 0, 0, 0.8, 0.809, 1, 0],
    [0, 0, 0, 0, -0.309, -0.5, 0],
    [0, 0, 0, 0, 0, 0.5, 0],
  ];

  static const List<List<double>> _ss = [
    [1, 1, 1, 1, 1, 1, 1],
    [0, 1, 1, 1, 1, 1, 0],
    [0, 0, 1, 1, 1, 1, 0],
    [0, 0, 0, 1, 1, 1, 0],
    [0, 0, 0, 0, 1, 1, 0],
    [0, 0, 0, 0, 0, 1, 0],
  ];

  late final List<Animation<double>> _xAnims;
  late final List<Animation<double>> _yAnims;
  late final List<Animation<double>> _sAnims;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4670),
    )..repeat();

    _xAnims = List.generate(
      6,
      (i) => _createTween(
        _xs[i],
        true,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    );
    _yAnims = List.generate(
      6,
      (i) => _createTween(
        _ys[i],
        true,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    );
    _sAnims = List.generate(
      6,
      (i) => _createTween(
        _ss[i],
        false,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
    );
  }

  TweenSequence<double> _createTween(List<double> values, bool multiplyDist) {
    return TweenSequence<double>(
      List.generate(6, (j) {
        return TweenSequenceItem(
          tween: Tween<double>(
            begin: values[j] * (multiplyDist ? _dist : 1.0),
            end: values[j + 1] * (multiplyDist ? _dist : 1.0),
          ),
          weight: 1.0,
        );
      }),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: List.generate(6, (i) {
              return Transform.translate(
                offset: Offset(_xAnims[i].value, _yAnims[i].value),
                child: Transform.scale(
                  scale: _sAnims[i].value,
                  child: Opacity(
                    opacity: _sAnims[i].value,
                    child: Container(
                      width: _dotSize,
                      height: _dotSize,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _MarkdownPart {
  const _MarkdownPart.text(this.content) : isCode = false, language = '';
  const _MarkdownPart.code(this.content, {required this.language})
    : isCode = true;

  final String content;
  final String language;
  final bool isCode;
}

class _CopyableCodeBlock extends StatelessWidget {
  const _CopyableCodeBlock({
    required this.code,
    required this.language,
    required this.palette,
  });

  final String code;
  final String language;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: palette.surfaceDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
            decoration: BoxDecoration(
              color: palette.onSurface.withValues(alpha: 0.04),
              border: Border(bottom: BorderSide(color: palette.outline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language.isEmpty ? 'code' : language,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy code',
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(LucideIcons.copy, size: 15),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              code.isEmpty ? ' ' : code,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 13,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 12),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: p.onSurfaceVariant,
        textStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _MessageAttachments extends StatelessWidget {
  const _MessageAttachments({required this.files});

  final List<AttachmentData> files;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: files.map((file) {
          if (file.type.startsWith('image/') && file.data.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                base64Decode(file.data),
                width: 180,
                height: 180,
                fit: BoxFit.cover,
              ),
            );
          }
          return _FileChip(file: file);
        }).toList(),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.file});

  final AttachmentData file;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: p.surfaceDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            file.type.startsWith('video/')
                ? LucideIcons.film
                : LucideIcons.fileText,
            size: 18,
            color: p.primary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: p.onSurface, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentTray extends StatelessWidget {
  const _AttachmentTray({required this.files, required this.onRemove});

  final List<AttachmentData> files;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemBuilder: (context, index) {
          final file = files[index];
          Uint8List? bytes;
          if (file.type.startsWith('image/') && file.data.isNotEmpty) {
            bytes = base64Decode(file.data);
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: p.surfaceDim,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: p.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: bytes == null
                    ? Icon(
                        file.type.startsWith('video/')
                            ? LucideIcons.film
                            : LucideIcons.fileText,
                        color: p.onSurfaceVariant,
                      )
                    : Image.memory(bytes, fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => onRemove(index),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: p.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.outline),
                    ),
                    child: Icon(LucideIcons.x, size: 13, color: p.error),
                  ),
                ),
              ),
            ],
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemCount: files.length,
      ),
    );
  }
}

class _InputPod extends StatelessWidget {
  const _InputPod({
    super.key,
    required this.input,
    required this.attachments,
    required this.onPick,
    required this.onSend,
  });

  final TextEditingController input;
  final List<AttachmentData> attachments;
  final VoidCallback onPick;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final historyTokens = app.currentSession.messages.fold<int>(
      0,
      (sum, message) => sum + countTokens(message.text),
    );
    final contextMax = contextWindow(app.selectedModel);
    final liveTokens = historyTokens + countTokens(input.text);
    final compact = MediaQuery.of(context).size.width < 560;
    final contextRatio = (liveTokens / contextMax).clamp(0.0, 1.0).toDouble();
    final contextColor =
        Color.lerp(
          p.isDark ? Colors.white : const Color(0xff475569),
          p.error,
          math.pow(contextRatio, 1.35).toDouble(),
        ) ??
        p.error;
    final inner = Column(
      children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 5),
            child: Row(
              children: [
                RoundIconButton(
                  icon: LucideIcons.lightbulb,
                  size: 30,
                  iconSize: 17,
                  color: app.isThinkingMode
                      ? const Color(0xfffacc15)
                      : p.onSurfaceVariant,
                  onPressed: app.toggleThinkingMode,
                ),
                RoundIconButton(
                  icon: LucideIcons.globe,
                  size: 30,
                  iconSize: 17,
                  color: app.genSettings.webSearchMode != 'off'
                      ? p.primary
                      : p.onSurfaceVariant,
                  onPressed: () => app.updateGenerationSettings(
                    app.genSettings.copyWith(
                      webSearchMode: app.genSettings.webSearchMode == 'off'
                          ? 'on'
                          : 'off',
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: LucideIcons.sparkles,
                  size: 30,
                  iconSize: 17,
                  color: app.isArtifactMode
                      ? const Color(0xffc084fc)
                      : p.onSurfaceVariant,
                  onPressed: app.toggleArtifactMode,
                ),
                const SizedBox(width: 12),
                if (app.currentSession.temporary && !compact) ...[
                  _TemporaryComposerPill(palette: p),
                  const SizedBox(width: 10),
                ],
                SizedBox(
                  width: compact ? 74 : 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: contextRatio,
                        backgroundColor: p.onSurface.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation<Color>(contextColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 64, maxWidth: 88),
                  child: Text(
                    '${formatTokenCount(liveTokens)} / ${formatTokenCount(contextMax)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: p.onSurfaceVariant.withValues(alpha: 0.68),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.outline),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RoundIconButton(
                  icon: LucideIcons.plus,
                  onPressed: onPick,
                  color: p.onSurfaceVariant,
                ),
                Expanded(
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: 40,
                      maxHeight: compact ? 68 : 96,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: compact ? 2 : 4,
                      style: TextStyle(
                        color: p.onSurface,
                        fontSize: 15,
                        height: 1.32,
                      ),
                      decoration: InputDecoration(
                        hintText: copy.t('chat', 'placeholder'),
                        hintStyle: TextStyle(
                          color: p.onSurfaceVariant.withValues(alpha: 0.55),
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 7),
                      ),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                ),
                RoundIconButton(
                  icon: LucideIcons.mic,
                  onPressed: onSend,
                  color: p.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: FilledButton(
                    onPressed: onSend,
                    style: FilledButton.styleFrom(
                      backgroundColor: p.primary,
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    child: Icon(
                      app.isGenerating
                          ? LucideIcons.square
                          : (input.text.trim().isNotEmpty ||
                                    attachments.isNotEmpty
                                ? LucideIcons.arrowUp
                                : LucideIcons.audioLines),
                      size: app.isGenerating ? 15 : 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

    if (p.isClassic) {
      return Container(
        decoration: BoxDecoration(
          color: p.isDark
              ? const Color(0xf2111111)
              : Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.isDark ? 0.45 : 0.10),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: inner,
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: p.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
          if (p.isAurora)
            BoxShadow(
              color: p.glow.withValues(alpha: 0.12),
              blurRadius: 28,
              spreadRadius: -8,
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: p.glassBlur > 0 ? p.glassBlur : 24,
            sigmaY: p.glassBlur > 0 ? p.glassBlur : 24,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: p.outline.withValues(alpha: p.isAurora ? 0.3 : 0.8),
              ),
              gradient: p.isLiquidGlass ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: p.isDark ? 0.15 : 0.8),
                  p.surface,
                  p.surface.withValues(alpha: p.isDark ? 0.05 : 0.4),
                ],
                stops: const [0.0, 0.4, 1.0],
              ) : null,
            ),
            child: inner,
          ),
        ),
      ),
    );
  }
}

class _TemporaryComposerPill extends StatelessWidget {
  const _TemporaryComposerPill({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: const Color(0xffa78bfa).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xffa78bfa).withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.shieldOff, size: 13, color: Color(0xffa78bfa)),
          const SizedBox(width: 5),
          Text(
            'Temporary',
            style: TextStyle(
              color: palette.onSurface.withValues(alpha: 0.78),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceOverlay extends StatelessWidget {
  const _VoiceOverlay({
    super.key,
    required this.recording,
    required this.connecting,
    required this.status,
    required this.level,
    required this.outputLevel,
    required this.onRecording,
    required this.onClose,
  });

  final bool recording;
  final bool connecting;
  final String status;
  final double level;
  final double outputLevel;
  final VoidCallback onRecording;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: p.isDark ? Colors.black : p.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: p.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;
          final buttonSize = compact ? 42.0 : 48.0;
          final capsuleBaseWidth = compact ? 144.0 : 176.0;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RoundIconButton(
                icon: LucideIcons.video,
                size: buttonSize,
                background: p.surfaceDim,
                color: context.read<AdoetzAppState>().isLiveVideoEnabled
                    ? p.primary
                    : p.onSurface,
                onPressed: () {
                  context.read<AdoetzAppState>().toggleLiveVideo();
                },
              ),
              SizedBox(width: compact ? 6 : 8),
              if (!compact) ...[
                RoundIconButton(
                  icon: LucideIcons.monitorUp,
                  size: buttonSize,
                  background: p.surfaceDim,
                  color: p.onSurface,
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(width: compact ? 8 : 16),
              _LiveStatusCapsule(
                width: capsuleBaseWidth,
                height: 52,
                recording: recording,
                connecting: connecting,
                level: level,
                outputLevel: outputLevel,
                status: status,
              ),
              const SizedBox(width: 16),
              RoundIconButton(
                icon: LucideIcons.mic,
                size: buttonSize,
                background: recording ? p.error : p.surfaceDim,
                color: recording ? Colors.white : p.onSurface,
                onPressed: onRecording,
              ),
              const SizedBox(width: 8),
              RoundIconButton(
                icon: LucideIcons.x,
                size: buttonSize,
                background: p.surfaceDim,
                color: p.onSurface,
                onPressed: onClose,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LiveVideoStage extends StatelessWidget {
  const _LiveVideoStage({required this.app});

  final AdoetzAppState app;

  @override
  Widget build(BuildContext context) {
    final caption = _latestLiveCaption(app);
    return Stack(
      children: [
        Positioned.fill(
          child: LiveCameraFeed(useFrontCamera: app.isLiveFrontCamera),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.36),
                    Colors.black.withValues(alpha: 0.04),
                    Colors.black.withValues(alpha: 0.74),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(top: 14, right: 16, child: _LiveVideoTopControls(app: app)),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (caption.isNotEmpty)
                    Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Text(
                            caption,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              height: 1.38,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 980),
                    child: SizedBox(
                      width: double.infinity,
                      child: _VoiceOverlay(
                        key: const ValueKey('video-voice-overlay'),
                        recording: app.isLiveRecording,
                        connecting: app.isLiveConnecting,
                        status: app.liveStatus,
                        level: app.liveInputLevel,
                        outputLevel: app.liveOutputLevel,
                        onRecording: () => unawaited(app.toggleLiveRecording()),
                        onClose: () => unawaited(app.stopLiveConversation()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _latestLiveCaption(AdoetzAppState app) {
    for (final message in app.currentSession.messages.reversed) {
      final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!message.isUser && text.isNotEmpty) return text;
    }
    final status = app.liveStatus.trim();
    if (status.isNotEmpty) return status;
    return app.isLiveRecording ? 'Listening...' : 'Paused';
  }
}

class _LiveVideoTopControls extends StatelessWidget {
  const _LiveVideoTopControls({required this.app});

  final AdoetzAppState app;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LiveCircleButton(
          icon: LucideIcons.switchCamera,
          tooltip: app.isLiveFrontCamera
              ? 'Use rear camera'
              : 'Use front camera',
          onPressed: app.toggleLiveCameraFacing,
        ),
        const SizedBox(width: 12),
        Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(29),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LiveCircleButton(
                icon: LucideIcons.captions,
                size: 42,
                iconSize: 22,
                background: Colors.transparent,
                onPressed: () {},
              ),
              _LiveCircleButton(
                icon: LucideIcons.moreHorizontal,
                size: 42,
                iconSize: 24,
                background: Colors.transparent,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveStatusCapsule extends StatelessWidget {
  const _LiveStatusCapsule({
    required this.width,
    required this.height,
    required this.recording,
    required this.connecting,
    required this.level,
    required this.outputLevel,
    required this.status,
  });

  final double width;
  final double height;
  final bool recording;
  final bool connecting;
  final double level;
  final double outputLevel;
  final String status;

  @override
  Widget build(BuildContext context) {
    final activeLevel = math.max(level, outputLevel).clamp(0.0, 1.0).toDouble();
    final isOutput = outputLevel > math.max(level, 0.04);
    final idleLevel = connecting ? 0.18 : 0.0;
    final amplitude = math
        .max(activeLevel, idleLevel)
        .clamp(0.0, 1.0)
        .toDouble();
    final label = connecting
        ? 'Connecting...'
        : (isOutput
              ? 'Speaking...'
              : (status.trim().isEmpty
                    ? (recording ? 'Listening...' : 'Paused')
                    : status.trim()));

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: amplitude),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        final scaleY = 1.0 + value * 1.6;
        final fogScale = 1.2 + value * 0.9;
        final radius = height > 84 ? 60.0 : height / 2;
        final coreHeight = height * 0.39;
        final fogHeight = height * 0.28;
        final fogInset = width * 0.15;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutBack,
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xff171717)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: const Color(
                  0xff2563eb,
                ).withValues(alpha: 0.12 + value * 0.28),
                blurRadius: 18 + value * 24,
                spreadRadius: value * 3,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: coreHeight,
                child: Transform.scale(
                  alignment: Alignment.bottomCenter,
                  scaleY: scaleY,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: height * 0.12,
                      sigmaY: height * 0.12,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(radius),
                        ),
                        gradient: const RadialGradient(
                          center: Alignment.bottomCenter,
                          radius: 1.5,
                          colors: [
                            Color(0xff2563eb),
                            Color(0x440744d5),
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: math.max(2, height * 0.03),
                left: fogInset,
                right: fogInset,
                height: fogHeight,
                child: Transform.scale(
                  alignment: Alignment.bottomCenter,
                  scale: fogScale,
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(
                      sigmaX: height * 0.08,
                      sigmaY: height * 0.08,
                    ),
                    child: Opacity(
                      opacity: 0.22 + value * 0.16,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xff0744d5),
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LiveCircleButton extends StatelessWidget {
  const _LiveCircleButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 58,
    this.iconSize = 26,
    this.background,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background ?? Colors.black.withValues(alpha: 0.70),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          padding: EdgeInsets.zero,
        ),
        icon: Icon(icon, size: iconSize),
      ),
    );
  }
}

class _AttachAction extends StatelessWidget {
  const _AttachAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: Text(label), onTap: onTap);
  }
}
