import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ArtifactPreview extends StatefulWidget {
  const ArtifactPreview({super.key, required this.files, this.isFullscreen = false});

  final Map<String, String> files;
  final bool isFullscreen;

  @override
  State<ArtifactPreview> createState() => _ArtifactPreviewState();
}
class _ArtifactPreviewState extends State<ArtifactPreview> {
  late final WebViewController? _controller;
  String? _currentFile;
  final List<String> _history = [];
  bool get _isSupported => kIsWeb || Platform.isAndroid || Platform.isIOS;
  String? _fallbackContent;

  @override
  void initState() {
    super.initState();
    
    // Pick the initial file. Prefer index.html, then any .html file, then the first file.
    if (widget.files.containsKey('index.html')) {
      _currentFile = 'index.html';
    } else {
      _currentFile = widget.files.keys.firstWhere(
        (k) => k.endsWith('.html'),
        orElse: () => widget.files.keys.first,
      );
    }
    
    if (_isSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'ArtifactChannel',
          onMessageReceived: (message) {
            final href = message.message;
            _navigateTo(href);
          },
        )
        ..setBackgroundColor(Colors.white);
    } else {
      _controller = null;
    }

    _loadCurrentFile();
  }

  @override
  void didUpdateWidget(covariant ArtifactPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If files changed (e.g. AI is streaming new content), reload current file
    if (_currentFile != null && widget.files.containsKey(_currentFile)) {
      _loadCurrentFile();
    }
  }

  void _navigateTo(String filename) {
    // Strip hash or query params if any
    final cleanName = filename.split('#').first.split('?').first;
    if (widget.files.containsKey(cleanName)) {
      setState(() {
        if (_currentFile != null) {
          _history.add(_currentFile!);
        }
        _currentFile = cleanName;
      });
      _loadCurrentFile();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File not found: $cleanName')),
      );
    }
  }

  void _goBack() {
    if (_history.isNotEmpty) {
      setState(() {
        _currentFile = _history.removeLast();
      });
      _loadCurrentFile();
    }
  }

  void _loadCurrentFile() {
    if (_currentFile == null || !widget.files.containsKey(_currentFile)) return;

    String content = widget.files[_currentFile!]!;

    // If it's an HTML file, inject CSS, JS, and our interceptor
    if (_currentFile!.endsWith('.html')) {
      // Inject CSS
      final cssFiles = widget.files.entries.where((e) => e.key.endsWith('.css'));
      for (final css in cssFiles) {
        final styleTag = '<style>\n${css.value}\n</style>';
        if (content.contains('</head>')) {
          content = content.replaceFirst('</head>', '$styleTag\n</head>');
        } else {
          content = '$styleTag\n$content';
        }
      }

      // Inject JS
      final jsFiles = widget.files.entries.where((e) => e.key.endsWith('.js'));
      for (final js in jsFiles) {
        final scriptTag = '<script>\n${js.value}\n</script>';
        if (content.contains('</body>')) {
          content = content.replaceFirst('</body>', '$scriptTag\n</body>');
        } else {
          content = '$content\n$scriptTag';
        }
      }

      // Inject Interceptor
      const interceptor = """
      <script>
        document.addEventListener('click', function(e) {
          var target = e.target.closest('a');
          if (target && target.getAttribute('href')) {
            var href = target.getAttribute('href');
            if (!href.startsWith('http')) {
              e.preventDefault();
              ArtifactChannel.postMessage(href);
            }
          }
        });
      </script>
      """;
      
      if (content.contains('</body>')) {
        content = content.replaceFirst('</body>', '$interceptor\n</body>');
      } else {
        content = '$content\n$interceptor';
      }
    }

    if (_isSupported) {
      _controller!.loadHtmlString(content);
    } else {
      setState(() {
        _fallbackContent = content;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Mini Browser Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.arrowLeft, size: 18),
                onPressed: _history.isNotEmpty ? _goBack : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.lock, size: 12, color: Colors.green),
                      const SizedBox(width: 6),
                      Text(
                        'localhost:$_currentFile',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                onPressed: _loadCurrentFile,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(
                  widget.isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  size: 20,
                ),
                onPressed: () {
                  if (widget.isFullscreen) {
                    Navigator.of(context).pop();
                  } else {
                    showDialog(
                      context: context,
                      useSafeArea: true,
                      builder: (context) => Dialog.fullscreen(
                        child: ArtifactPreview(
                          files: widget.files,
                          isFullscreen: true,
                        ),
                      ),
                    );
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        // WebView or Fallback Content
        Expanded(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
            child: _isSupported
                ? WebViewWidget(
                    controller: _controller!,
                    gestureRecognizers: {
                      Factory<VerticalDragGestureRecognizer>(
                        () => VerticalDragGestureRecognizer(),
                      ),
                      Factory<HorizontalDragGestureRecognizer>(
                        () => HorizontalDragGestureRecognizer(),
                      ),
                    },
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceBright,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.monitorX, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text(
                            'Preview not supported natively on this platform.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () async {
                              if (_fallbackContent == null) return;
                              try {
                                final dir = await getTemporaryDirectory();
                                final file = File('${dir.path}/adoetzgpt_preview.html');
                                await file.writeAsString(_fallbackContent!);
                                await launchUrl(Uri.file(file.path));
                              } catch (e) {
                                debugPrint('Could not launch browser: $e');
                              }
                            },
                            icon: const Icon(LucideIcons.externalLink, size: 16),
                            label: const Text('Open in Browser'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
