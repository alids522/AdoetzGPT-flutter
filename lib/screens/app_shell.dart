import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../translations.dart';
import '../ui/app_theme.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';
import 'token_usage_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final showHeader =
        !(app.currentView == AppView.chat && app.isLiveVideoEnabled);
    return PopScope(
      canPop: kIsWeb,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
          Navigator.of(context).pop();
          return;
        }
        if (context.read<AdoetzAppState>().handleSystemBack()) return;
        SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: const _AppDrawer(),
        drawerScrimColor: Colors.black.withValues(alpha: 0.60),
        backgroundColor: p.background,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Positioned.fill(
                child: switch (app.currentView) {
                  AppView.chat => const ChatScreen(),
                  AppView.settings => const SettingsScreen(),
                  AppView.tokenUsage => const TokenUsageScreen(),
                },
              ),
              if (showHeader)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          p.background.withValues(alpha: 0.85),
                          p.background.withValues(alpha: 0.40),
                          p.background.withValues(alpha: 0.0),
                        ],
                        stops: const [0.2, 0.65, 1.0],
                      ),
                    ),
                    child: const _Header(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header();

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final LayerLink _modelButtonLink = LayerLink();
  final GlobalKey _modelButtonKey = GlobalKey();
  OverlayEntry? _modelOverlay;

  @override
  void dispose() {
    _modelOverlay?.remove();
    _modelOverlay = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Row(
        children: [
          if (app.currentView == AppView.chat) ...[
            Builder(
              builder: (context) => RoundIconButton(
                icon: LucideIcons.menu,
                color: p.onSurface,
                tooltip: 'Open sidebar',
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Align(
                alignment: Alignment.centerLeft,
                child: CompositedTransformTarget(
                  link: _modelButtonLink,
                  child: InkWell(
                    key: _modelButtonKey,
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _toggleModelPicker(context),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 260),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: p.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: p.outline),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _formatModelName(app.selectedModel),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: p.onSurface.withValues(alpha: 0.92),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            LucideIcons.chevronDown,
                            size: 14,
                            color: p.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            TextButton.icon(
              onPressed: () => app.setView(AppView.chat),
              icon: const Icon(LucideIcons.arrowLeft, size: 20),
              label: Text(
                app.language == AppLanguage.en ? 'Back to chat' : 'Kembali',
              ),
              style: TextButton.styleFrom(
                foregroundColor: p.onSurface.withValues(alpha: 0.88),
              ),
            ),
            const Spacer(),
          ],
          const SizedBox(width: 8),
          if (app.syncSettings.enabled && app.syncStatus.isNotEmpty)
            Flexible(
              child: Text(
                app.syncStatus,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: p.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          RoundIconButton(
            icon: app.currentSession.messages.isEmpty
                ? LucideIcons.sparkles
                : LucideIcons.edit2,
            color: app.currentSession.messages.isEmpty
                ? const Color(0xffa78bfa)
                : p.onSurface,
            tooltip: app.currentSession.messages.isEmpty
                ? 'Temporary chat'
                : 'New chat',
            onPressed: app.headerChatShortcut,
          ),
        ],
      ),
    );
  }

  void _toggleModelPicker(BuildContext context) {
    if (_modelOverlay != null) {
      _hideModelPicker();
      return;
    }
    final app = context.read<AdoetzAppState>();
    final renderBox =
        _modelButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final buttonSize = renderBox?.size ?? const Size(260, 40);
    final buttonOffset =
        renderBox?.localToGlobal(Offset.zero) ?? const Offset(12, 56);
    final media = MediaQuery.of(context).size;
    final screenWidth = media.width;
    final compact = screenWidth < 560;
    final dropdownWidth = compact
        ? math.min(330.0, math.max(280.0, screenWidth - 56))
        : math.min(390.0, math.max(300.0, screenWidth - 32));
    final overflowRight = buttonOffset.dx + dropdownWidth - (screenWidth - 12);
    final horizontalOffset = overflowRight > 0 ? -overflowRight : 0.0;
    final maxHeight = math.max(
      260.0,
      math.min(
        compact ? 390.0 : 470.0,
        media.height - buttonOffset.dy - buttonSize.height - 24,
      ),
    );
    _modelOverlay = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideModelPicker,
              child: const SizedBox.expand(),
            ),
          ),
          CompositedTransformFollower(
            link: _modelButtonLink,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: Offset(horizontalOffset, 8),
            child: ChangeNotifierProvider.value(
              value: app,
              child: SizedBox(
                width: dropdownWidth,
                child: _ModelDropdown(
                  minWidth: buttonSize.width,
                  maxHeight: maxHeight,
                  compact: compact,
                  onClose: _hideModelPicker,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_modelOverlay!);
  }

  void _hideModelPicker() {
    _modelOverlay?.remove();
    _modelOverlay = null;
  }

  String _formatModelName(String name) {
    if (name.toLowerCase() == 'gemini-2.5-flash') return 'Gemini 2.5 Flash';
    return name
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          if (part.toLowerCase() == 'gpt') return 'GPT';
          return part.substring(0, 1).toUpperCase() + part.substring(1);
        })
        .join(' ');
  }
}

class _ModelDropdown extends StatefulWidget {
  const _ModelDropdown({
    required this.minWidth,
    required this.maxHeight,
    required this.compact,
    required this.onClose,
  });

  @override
  State<_ModelDropdown> createState() => _ModelDropdownState();

  final double minWidth;
  final double maxHeight;
  final bool compact;
  final VoidCallback onClose;
}

class _ModelDropdownState extends State<_ModelDropdown> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final models = app.models
        .where((model) => model.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: math.min(widget.minWidth, 330),
          maxHeight: widget.maxHeight,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xff111111) : Colors.white,
            borderRadius: BorderRadius.circular(widget.compact ? 18 : 22),
            border: Border.all(color: p.outline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? 0.38 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  widget.compact ? 10 : 12,
                  8,
                  widget.compact ? 6 : 10,
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.bot, size: 16, color: p.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Model Selection',
                        style: TextStyle(
                          color: p.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fetch models',
                      onPressed: app.isFetchingModels
                          ? null
                          : () => unawaited(app.fetchModels()),
                      icon: app.isFetchingModels
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(LucideIcons.refreshCw, size: 16),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: widget.onClose,
                      icon: const Icon(LucideIcons.x, size: 16),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  widget.compact ? 8 : 12,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(LucideIcons.search, size: 16),
                    hintText: app.language == AppLanguage.en
                        ? 'Search models...'
                        : 'Cari model...',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              if (app.modelFetchStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      app.modelFetchStatus,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            app.modelFetchStatus.toLowerCase().contains(
                              'failed',
                            )
                            ? p.error
                            : p.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Flexible(
                child: models.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: Text(
                          app.isFetchingModels
                              ? 'Fetching models...'
                              : 'No models match your search.',
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        itemCount: models.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: p.outline),
                        itemBuilder: (context, index) {
                          final model = models[index];
                          final selected = model == app.selectedModel;
                          final endpointLabel = _endpointLabel(app, model);
                          return ListTile(
                            dense: true,
                            minVerticalPadding: widget.compact ? 7 : 10,
                            visualDensity: widget.compact
                                ? VisualDensity.compact
                                : VisualDensity.standard,
                            title: Text(
                              model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? p.onSurface
                                    : p.onSurface.withValues(alpha: 0.78),
                                fontWeight: selected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              endpointLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.onSurfaceVariant,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            trailing: selected
                                ? Icon(
                                    LucideIcons.check,
                                    color: p.primary,
                                    size: 18,
                                  )
                                : null,
                            onTap: () {
                              app.setSelectedModel(model);
                              widget.onClose();
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _endpointLabel(AdoetzAppState app, String model) {
    EndpointModel? endpointModel;
    for (final item in app.endpointModels) {
      if (item.name == model) {
        endpointModel = item;
        break;
      }
    }
    if (endpointModel == null) return 'Gemini';
    for (final endpoint in app.endpoints) {
      if (endpoint.id == endpointModel.endpointId) {
        return endpoint.name.trim().isEmpty ? 'Endpoint' : endpoint.name;
      }
    }
    return 'Endpoint';
  }
}

class _AppDrawer extends StatefulWidget {
  const _AppDrawer();

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  bool memoryOpen = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final activeSessions = app.activeSessions
        .where((session) => !session.temporary)
        .toList();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Drawer(
      width: 320,
      backgroundColor: p.isDark ? Colors.black : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 12, 10),
              child: Row(
                children: [
                  Text(
                    'AdoetzGPT',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: p.onSurface,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const Spacer(),
                  RoundIconButton(
                    icon: LucideIcons.menu,
                    onPressed: () => Navigator.pop(context),
                    color: p.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            _NavTile(
              icon: LucideIcons.edit2,
              label: copy.t('sidebar', 'newSession'),
              active: false,
              onTap: () => _closeAfter(context, app.createSession),
            ),
            _NavTile(
              icon: LucideIcons.search,
              label: 'Search',
              active: false,
              onTap: () {},
            ),
            _NavTile(
              icon: LucideIcons.brain,
              label: copy.t('sidebar', 'memory'),
              active: memoryOpen,
              onTap: () => setState(() => memoryOpen = !memoryOpen),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _MemoryPanel(copy: copy),
              crossFadeState: memoryOpen
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 180),
            ),
            _NavTile(
              icon: LucideIcons.trendingUp,
              label: 'Token Usage',
              active: app.currentView == AppView.tokenUsage,
              onTap: () =>
                  _closeAfter(context, () => app.setView(AppView.tokenUsage)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              child: Divider(color: p.outline),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount:
                    1 +
                    activeSessions.length +
                    (activeSessions.isNotEmpty ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                      child: Text(
                        copy.t('sidebar', 'recentSessions').toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          color: p.onSurfaceVariant.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    );
                  }
                  final sessionIndex = index - 1;
                  if (sessionIndex < activeSessions.length) {
                    return _SessionTile(session: activeSessions[sessionIndex]);
                  }
                  return _NavTile(
                    icon: LucideIcons.trash2,
                    label: copy.t('sidebar', 'clearAll'),
                    active: false,
                    danger: true,
                    onTap: () => _confirmClear(context, app),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () =>
                    _closeAfter(context, () => app.setView(AppView.settings)),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: p.outline),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: p.primary,
                        backgroundImage: const AssetImage(
                          'assets/app_logo.png',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.userName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: p.onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              copy.t('sidebar', 'verifiedUser').toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xff60a5fa),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.settings,
                        size: 18,
                        color: p.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeAfter(BuildContext context, VoidCallback action) {
    action();
    Navigator.pop(context);
  }

  Future<void> _confirmClear(BuildContext context, AdoetzAppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Clear Everything'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (ok == true && mounted) {
      app.clearAllSessions();
      Navigator.pop(context);
    }
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final color = danger
        ? p.error
        : active
        ? p.onSurface
        : p.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: ListTile(
        dense: true,
        minLeadingWidth: 24,
        horizontalTitleGap: 12,
        leading: Icon(icon, size: 20, color: color),
        title: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        tileColor: active ? p.onSurface.withValues(alpha: 0.06) : null,
        onTap: onTap,
      ),
    );
  }
}

class _MemoryPanel extends StatefulWidget {
  const _MemoryPanel({required this.copy});

  final UiCopy copy;

  @override
  State<_MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<_MemoryPanel> {
  String? editingId;
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: app.memories.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Center(
                  child: Text(
                    widget.copy.t('sidebar', 'noMemories'),
                    style: TextStyle(
                      color: p.onSurfaceVariant,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: app.memories.length,
                itemBuilder: (context, index) {
                  final memory = app.memories[index];
                  final editing = editingId == memory.id;
                  if (editing) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(
                        children: [
                          TextField(
                            controller: controller,
                            minLines: 2,
                            maxLines: 4,
                            style: const TextStyle(fontSize: 12),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () {
                                    app.updateMemory(
                                      memory.id,
                                      controller.text,
                                    );
                                    setState(() => editingId = null);
                                  },
                                  child: Text(widget.copy.t('sidebar', 'save')),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      setState(() => editingId = null),
                                  child: Text(
                                    widget.copy.t('sidebar', 'cancel'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: p.onSurface.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          memory.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: p.onSurface.withValues(alpha: 0.78),
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              DateFormat.yMd().format(
                                DateTime.fromMillisecondsSinceEpoch(
                                  memory.timestamp,
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 10,
                                color: p.onSurfaceVariant.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                            const Spacer(),
                            RoundIconButton(
                              icon: LucideIcons.edit2,
                              size: 26,
                              iconSize: 12,
                              onPressed: () {
                                controller.text = memory.content;
                                setState(() => editingId = memory.id);
                              },
                            ),
                            RoundIconButton(
                              icon: LucideIcons.trash2,
                              size: 26,
                              iconSize: 12,
                              color: p.error,
                              onPressed: () => app.deleteMemory(memory.id),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final active =
        app.currentView == AppView.chat && app.currentSessionId == session.id;
    return ListTile(
      dense: true,
      minLeadingWidth: 22,
      horizontalTitleGap: 12,
      leading: Icon(
        LucideIcons.messageSquare,
        size: 16,
        color: active ? p.onSurface : p.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      title: Text(
        session.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? p.onSurface : p.onSurfaceVariant,
          fontSize: 15,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.pinned)
            const Icon(LucideIcons.pin, size: 12, color: Color(0xff60a5fa)),
          PopupMenuButton<String>(
            icon: Icon(
              LucideIcons.moreHorizontal,
              size: 16,
              color: p.onSurfaceVariant,
            ),
            onSelected: (value) => _handleMenu(context, app, value),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'pin', child: Text('Pin')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: active ? p.onSurface.withValues(alpha: 0.06) : null,
      onTap: () {
        app.selectSession(session.id);
        Navigator.pop(context);
      },
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    AdoetzAppState app,
    String value,
  ) async {
    if (value == 'pin') {
      app.pinSession(session.id);
    } else if (value == 'delete') {
      app.deleteSession(session.id);
    } else if (value == 'rename') {
      final controller = TextEditingController(text: session.title);
      final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Rename'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (title != null) app.renameSession(session.id, title);
    }
  }
}
