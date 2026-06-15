import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

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
  DateTime? _lastBackPressTime;

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

        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Press back again to exit app',
                style: TextStyle(color: Colors.white),
              ),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              backgroundColor: p.isDark
                  ? const Color(0xff333333)
                  : const Color(0xff555555),
            ),
          );
          return;
        }
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
              const Positioned.fill(child: ThemedBackdrop()),
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: Duration(
                    milliseconds:
                        (MediaQuery.maybeOf(context)?.disableAnimations ??
                            false)
                        ? 1
                        : 220,
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: KeyedSubtree(
                    key: ValueKey(app.currentView),
                    child: switch (app.currentView) {
                      AppView.chat => const ChatScreen(),
                      AppView.settings => const SettingsScreen(),
                      AppView.tokenUsage => const TokenUsageScreen(),
                    },
                  ),
                ),
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
    final activeTarget = app.activeChatTarget;
    final showStatusShortcut =
        (app.syncSettings.enabled && app.syncStatus.isNotEmpty) ||
        app.agentConnectors.isNotEmpty;
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
                    onTap: activeTarget.isAgentServer ? null : () => _toggleModelPicker(context),
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                app.formatTargetName(activeTarget.displayName),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: p.onSurface.withValues(alpha: 0.92),
                                ),
                              ),
                            ),
                          ),
                          if (activeTarget.isAgentServer) ...[
                            const SizedBox(width: 7),
                            _ConnectorDot(status: activeTarget.status),
                          ] else ...[
                            const SizedBox(width: 5),
                            Icon(
                              LucideIcons.chevronDown,
                              size: 14,
                              color: p.onSurfaceVariant,
                            ),
                          ],
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
          if (app.currentView == AppView.chat) ...[const Spacer()],
          if (showStatusShortcut) ...[
            Tooltip(
              message: app.syncStatus.isEmpty
                  ? 'Connector status'
                  : app.syncStatus,
              child: _SyncStatusIcon(
                status: app.syncStatus.isEmpty
                    ? 'Connector status'
                    : app.syncStatus,
                color: p.onSurfaceVariant.withValues(alpha: 0.72),
                onTap: () => _showConnectorStatus(context),
              ),
            ),
            const SizedBox(width: 8),
          ],
          RoundIconButton(
            icon: LucideIcons.edit2,
            color: p.onSurface,
            tooltip: 'New chat',
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
                child: _ChatTargetDropdown(
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

  void _showConnectorStatus(BuildContext context) {
    final app = context.read<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: p.isDark ? const Color(0xff111111) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ChangeNotifierProvider.value(
          value: app,
          child: Consumer<AdoetzAppState>(
            builder: (context, app, _) => Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.server, size: 18, color: p.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Connected Servers',
                          style: TextStyle(
                            color: p.onSurface,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sync database',
                        onPressed: app.syncNow,
                        icon: const Icon(LucideIcons.databaseZap, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (app.agentConnectors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        'No Agent Servers configured yet.',
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    ...app.agentConnectors.map(
                      (connector) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: _ConnectorDot(status: connector.status),
                        title: Text(connector.name),
                        subtitle: Text(
                          connector.latencyMs == null
                              ? connectorStatusLabel(connector.status)
                              : '${connectorStatusLabel(connector.status)} - ${connector.latencyMs}ms',
                        ),
                        trailing: IconButton(
                          tooltip: 'Test connection',
                          onPressed: () =>
                              unawaited(app.testAgentConnector(connector.id)),
                          icon: const Icon(LucideIcons.refreshCw, size: 16),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      app.setView(AppView.settings);
                    },
                    icon: const Icon(LucideIcons.settings, size: 16),
                    label: const Text('Manage Connectors'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatTargetDropdown extends StatefulWidget {
  const _ChatTargetDropdown({
    required this.minWidth,
    required this.maxHeight,
    required this.compact,
    required this.onClose,
  });

  @override
  State<_ChatTargetDropdown> createState() => _ChatTargetDropdownState();

  final double minWidth;
  final double maxHeight;
  final bool compact;
  final VoidCallback onClose;
}

class _ChatTargetDropdownState extends State<_ChatTargetDropdown> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final normalized = query.toLowerCase();
    final modelTargets = app.modelTargets
        .where(
          (target) =>
              target.displayName.toLowerCase().contains(normalized) ||
              target.provider.toLowerCase().contains(normalized),
        )
        .toList();
    final agentTargets = app.agentServerTargets
        .where(
          (target) =>
              target.displayName.toLowerCase().contains(normalized) ||
              target.provider.toLowerCase().contains(normalized),
        )
        .toList();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: 0.96 + value * 0.04,
        alignment: Alignment.topLeft,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Material(
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
                          'Choose Chat Target',
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
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
                          ? 'Search targets...'
                          : 'Cari target...',
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
                  child: modelTargets.isEmpty && agentTargets.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                          child: Text(
                            app.isFetchingModels
                                ? 'Fetching models...'
                                : 'No targets match your search.',
                            style: TextStyle(
                              color: p.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                          children: [
                            if (modelTargets.isNotEmpty)
                              _TargetSectionLabel(label: 'Models', palette: p),
                            ...modelTargets.map(
                              (target) => _TargetTile(
                                target: target,
                                selected: target.id == app.activeChatTarget.id,
                                compact: widget.compact,
                                palette: p,
                                onTap: () => _selectTarget(context, target),
                              ),
                            ),
                            if (agentTargets.isNotEmpty) ...[
                              Divider(height: 1, color: p.outline),
                              _TargetSectionLabel(
                                label: 'Agent Servers',
                                palette: p,
                              ),
                              ...agentTargets.map(
                                (target) => _TargetTile(
                                  target: target,
                                  selected:
                                      target.id == app.activeChatTarget.id,
                                  compact: widget.compact,
                                  palette: p,
                                  onTap: () => _selectTarget(context, target),
                                ),
                              ),
                            ],
                            Divider(height: 1, color: p.outline),
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                LucideIcons.settings,
                                size: 16,
                              ),
                              title: const Text('Manage Connectors'),
                              onTap: () {
                                widget.onClose();
                                app.setView(AppView.settings);
                              },
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectTarget(BuildContext context, ChatTarget target) async {
    final app = context.read<AdoetzAppState>();
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    widget.onClose();
    if (!app.requiresTargetSwitchConfirmation(target)) {
      app.applyChatTarget(target, insertDivider: false);
      return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!rootContext.mounted) return;
    final action = await _showTargetSwitchSheet(rootContext, app, target);
    if (action == 'continue') {
      app.applyChatTarget(target);
    } else if (action == 'fork') {
      app.applyChatTarget(target, fork: true);
    }
  }

  Future<String?> _showTargetSwitchSheet(
    BuildContext context,
    AdoetzAppState app,
    ChatTarget target,
  ) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final current = app.activeChatTarget;
    final text = current.isAgentServer && target.isAgentServer
        ? 'Device-specific tools, memory, files, and permissions may differ between Agent Servers.'
        : 'Tools and device state may not be available after switching between a normal model and an Agent Server.';
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.isDark ? const Color(0xff111111) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Switch Chat Target',
                style: TextStyle(
                  color: p.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Switch from ${app.formatTargetName(current.displayName)} to ${app.formatTargetName(target.displayName)}. $text',
                style: TextStyle(
                  color: p.onSurfaceVariant,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(context, 'continue'),
                child: const Text('Continue this chat'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'fork'),
                child: const Text('Fork from here'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'cancel'),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetSectionLabel extends StatelessWidget {
  const _TargetSectionLabel({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: palette.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.3,
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.target,
    required this.selected,
    required this.compact,
    required this.palette,
    required this.onTap,
  });

  final ChatTarget target;
  final bool selected;
  final bool compact;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AdoetzAppState>();
    return ListTile(
      dense: true,
      minVerticalPadding: compact ? 7 : 10,
      visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
      leading: target.isAgentServer
          ? _ConnectorDot(status: target.status)
          : Icon(LucideIcons.bot, size: 16, color: palette.primary),
      title: Text(
        app.formatTargetName(target.displayName),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: selected
              ? palette.onSurface
              : palette.onSurface.withValues(alpha: 0.78),
          fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
        ),
      ),
      subtitle: Text(
        target.isAgentServer
            ? '${target.provider} - ${connectorStatusLabel(target.status)}'
            : target.provider,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: palette.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: selected
          ? Icon(LucideIcons.check, color: palette.primary, size: 18)
          : null,
      onTap: onTap,
    );
  }
}

class _ConnectorDot extends StatelessWidget {
  const _ConnectorDot({required this.status});

  final ConnectorStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ConnectorStatus.online => const Color(0xff22c55e),
      ConnectorStatus.authFailed ||
      ConnectorStatus.timeout => const Color(0xfff59e0b),
      ConnectorStatus.offline ||
      ConnectorStatus.streamingFailed ||
      ConnectorStatus.syncFailed => const Color(0xffef4444),
      ConnectorStatus.unknown => const Color(0xff64748b),
    };
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 8),
        ],
      ),
    );
  }
}

class _AppDrawer extends StatefulWidget {
  const _AppDrawer();

  @override
  State<_AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<_AppDrawer> {
  bool memoryOpen = false;
  bool searchOpen = false;
  final searchController = TextEditingController();

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final activeSessions = app.activeSessions.toList();
    final searchQuery = searchController.text.trim();
    final genericSessions = activeSessions
        .where((s) => !s.currentTargetId.startsWith('agent:'))
        .toList();
    final visibleSessions = searchQuery.isEmpty
        ? genericSessions
        : activeSessions
              .where((session) => _sessionMatches(session, searchQuery))
              .toList();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Drawer(
      width: 320,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(p.sidebarRadius),
        ),
      ),
      backgroundColor: p.isClassic
          ? (p.isDark ? Colors.black : Colors.white)
          : Colors.transparent,
      elevation: p.isClassic ? 16 : 0,
      child: Builder(
        builder: (context) {
          final inner = SafeArea(
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
                  active: searchOpen,
                  onTap: () {
                    setState(() {
                      searchOpen = !searchOpen;
                      if (!searchOpen) searchController.clear();
                    });
                  },
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _DrawerSearchField(
                    controller: searchController,
                    onChanged: (_) => setState(() {}),
                    onClear: () => setState(searchController.clear),
                  ),
                  crossFadeState: searchOpen
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
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
                  onTap: () => _closeAfter(
                    context,
                    () => app.setView(AppView.tokenUsage),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      const _AgentServersSection(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 10,
                        ),
                        child: Divider(color: p.outline),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                        child: Text(
                          (searchQuery.isEmpty
                                  ? copy.t('sidebar', 'recentSessions')
                                  : 'Search results')
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            color: p.onSurfaceVariant.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ),
                      if (searchQuery.isNotEmpty && visibleSessions.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                          child: Text(
                            'No chats contain "$searchQuery".',
                            style: TextStyle(
                              color: p.onSurfaceVariant,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        ...visibleSessions.map(
                          (session) => _SessionTile(
                            session: session,
                            query: searchQuery,
                          ),
                        ),
                      if (searchQuery.isEmpty && genericSessions.isNotEmpty)
                        _NavTile(
                          icon: LucideIcons.trash2,
                          label: copy.t('sidebar', 'clearAll'),
                          active: false,
                          danger: true,
                          onTap: () => _confirmClear(context, app),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _closeAfter(
                      context,
                      () => app.setView(AppView.settings),
                    ),
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
                                  copy
                                      .t('sidebar', 'verifiedUser')
                                      .toUpperCase(),
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
          );

          if (p.isClassic || p.glassBlur <= 0) {
            return Container(
              color: p.isClassic ? null : p.surface,
              child: Material(color: Colors.transparent, child: inner),
            );
          }

          return BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: p.glassBlur,
              sigmaY: p.glassBlur,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                border: Border(
                  right: BorderSide(color: p.outline.withValues(alpha: 0.5)),
                ),
                gradient: p.isLiquidGlass
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: p.isDark ? 0.12 : 0.6),
                          p.surface,
                          p.surface.withValues(alpha: p.isDark ? 0.02 : 0.2),
                        ],
                      )
                    : null,
              ),
              child: Material(color: Colors.transparent, child: inner),
            ),
          );
        },
      ),
    );
  }

  void _closeAfter(BuildContext context, VoidCallback action) {
    action();
    Navigator.pop(context);
  }

  bool _sessionMatches(Session session, String query) {
    final normalized = query.toLowerCase();
    if (session.title.toLowerCase().contains(normalized)) return true;
    return session.messages.any(
      (message) => message.text.toLowerCase().contains(normalized),
    );
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

class _AgentServersSection extends StatefulWidget {
  const _AgentServersSection();

  @override
  State<_AgentServersSection> createState() => _AgentServersSectionState();
}

class _AgentServersSectionState extends State<_AgentServersSection> {
  bool open = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    return Column(
      children: [
        _NavTile(
          icon: LucideIcons.server,
          label: 'Agent Servers',
          active: open,
          onTap: () => setState(() => open = !open),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 8, 8),
            child: app.agentConnectors.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        app.setView(AppView.settings);
                      },
                      icon: const Icon(LucideIcons.plus, size: 14),
                      label: const Text('Add connector'),
                    ),
                  )
                : Column(
                    children: app.agentConnectors.map((connector) {
                      return _ConnectorAccordionTile(
                        connector: connector,
                        onCloseSidebar: () => Navigator.pop(context),
                      );
                    }).toList(),
                  ),
          ),
          crossFadeState: open
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
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

class _DrawerSearchField extends StatelessWidget {
  const _DrawerSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 10),
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        style: TextStyle(color: p.onSurface, fontSize: 14),
        decoration: InputDecoration(
          prefixIcon: const Icon(LucideIcons.search, size: 16),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(LucideIcons.x, size: 16),
                ),
          hintText: 'Search chat content...',
          isDense: true,
        ),
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
  const _SessionTile({required this.session, this.query = ''});

  final Session session;
  final String query;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final active =
        app.currentView == AppView.chat && app.currentSessionId == session.id;
    final preview = _matchPreview(session, query);
    final targetLabel = app.targetLabelForSession(session);
    return ListTile(
      dense: true,
      minLeadingWidth: 22,
      horizontalTitleGap: 12,
      leading: Icon(
        LucideIcons.messageSquare,
        size: 16,
        color: active ? p.onSurface : p.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? p.onSurface : p.onSurfaceVariant,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            targetLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? p.primary.withValues(alpha: 0.9)
                  : p.onSurfaceVariant.withValues(alpha: 0.62),
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      subtitle: preview == null
          ? null
          : Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: p.onSurfaceVariant.withValues(alpha: 0.74),
                fontSize: 11,
                height: 1.25,
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

  String? _matchPreview(Session session, String query) {
    final clean = query.trim().toLowerCase();
    if (clean.isEmpty) return null;
    for (final message in session.messages) {
      final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final lower = text.toLowerCase();
      final matchIndex = lower.indexOf(clean);
      if (matchIndex < 0) continue;
      final start = math.max(0, matchIndex - 34);
      final end = math.min(text.length, matchIndex + clean.length + 74);
      final prefix = start > 0 ? '...' : '';
      final suffix = end < text.length ? '...' : '';
      return '$prefix${text.substring(start, end)}$suffix';
    }
    return session.title.toLowerCase().contains(clean) ? session.title : null;
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

class _SyncStatusIcon extends StatefulWidget {
  final String status;
  final Color color;
  final VoidCallback onTap;

  const _SyncStatusIcon({
    required this.status,
    required this.color,
    required this.onTap,
  });

  @override
  State<_SyncStatusIcon> createState() => _SyncStatusIconState();
}

class _SyncStatusIconState extends State<_SyncStatusIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _opacity = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _updateAnimation();
  }

  @override
  void didUpdateWidget(_SyncStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    final lower = widget.status.toLowerCase();
    final isSyncing =
        lower.contains('syncing') ||
        lower.contains('connecting') ||
        lower.contains('pulling');
    if (isSyncing) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lower = widget.status.toLowerCase();
    Color iconColor = widget.color;
    final isSyncing =
        lower.contains('syncing') ||
        lower.contains('connecting') ||
        lower.contains('pulling');

    if (isSyncing) {
      iconColor = Colors.blue;
    } else if (lower.contains('success') ||
        lower.contains('loaded') ||
        lower.contains('saved')) {
      iconColor = Colors.green;
    } else if (lower.contains('fail') ||
        lower.contains('error') ||
        lower.contains('disconnect')) {
      iconColor = Colors.red;
    }

    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: AnimatedBuilder(
          animation: _opacity,
          builder: (context, child) {
            return Opacity(
              opacity: isSyncing ? _opacity.value : 1.0,
              child: child,
            );
          },
          child: Icon(LucideIcons.database, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

class _ConnectorAccordionTile extends StatefulWidget {
  const _ConnectorAccordionTile({
    required this.connector,
    required this.onCloseSidebar,
  });

  final AgentConnector connector;
  final VoidCallback onCloseSidebar;

  @override
  State<_ConnectorAccordionTile> createState() => _ConnectorAccordionTileState();
}

class _ConnectorAccordionTileState extends State<_ConnectorAccordionTile> {
  bool expanded = false;

  void _confirmClearAgent(BuildContext context, AdoetzAppState app) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${widget.connector.name} Sessions'),
        content: Text('Are you sure you want to delete all chats with ${widget.connector.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              app.clearAgentSessions(widget.connector.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _handleConnectorMenu(
    BuildContext context,
    AdoetzAppState app,
    AgentConnector connector,
    String value,
  ) {
    switch (value) {
      case 'test':
        unawaited(app.testAgentConnector(connector.id));
        break;
      case 'default':
        app.setDefaultConnector(connector.id);
        break;
      case 'logs':
        _showConnectorLogs(context, connector);
        break;
      case 'edit':
        widget.onCloseSidebar();
        app.setView(AppView.settings);
        break;
      case 'toggle':
        app.setConnectorEnabled(connector.id, !connector.enabled);
        break;
      case 'delete':
        app.deleteAgentConnector(connector.id);
        break;
    }
  }

  void _showConnectorLogs(BuildContext context, AgentConnector connector) {
    final logs = connector.logs.isEmpty
        ? ['No connector logs yet.']
        : connector.logs;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${connector.name} Logs'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: SelectableText(logs.join('\n'))),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final active = app.activeChatTarget.connectorId == widget.connector.id;
    final agentSessions = app.activeSessions
        .where((s) => s.currentTargetId == 'agent:${widget.connector.id}')
        .toList();

    return Column(
      children: [
        ListTile(
          dense: true,
          minLeadingWidth: 18,
          contentPadding: const EdgeInsets.only(left: 6),
          leading: _ConnectorDot(status: widget.connector.status),
          title: Text(
            widget.connector.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? p.onSurface : p.onSurfaceVariant,
              fontWeight: active ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          subtitle: Text(
            widget.connector.providerLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: p.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                icon: Icon(
                  LucideIcons.moreHorizontal,
                  size: 16,
                  color: p.onSurfaceVariant,
                ),
                onSelected: (value) => _handleConnectorMenu(
                  context,
                  app,
                  widget.connector,
                  value,
                ),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'test',
                    child: Text('Test Connection'),
                  ),
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Set as Default'),
                  ),
                  const PopupMenuItem(
                    value: 'logs',
                    child: Text('View Logs'),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit'),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                      widget.connector.enabled ? 'Disable' : 'Enable',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
                ],
              ),
              Icon(
                expanded ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 16,
                color: p.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
            ],
          ),
          onTap: () {
            setState(() {
              expanded = !expanded;
            });
          },
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: [
                _NavTile(
                  icon: LucideIcons.plus,
                  label: 'New Chat',
                  active: false,
                  onTap: () {
                    app.startChatWithConnector(widget.connector.id);
                    widget.onCloseSidebar();
                  },
                ),
                if (agentSessions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'No chats yet.',
                        style: TextStyle(
                          color: p.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else ...[
                  ...agentSessions.map(
                    (session) => _SessionTile(
                      session: session,
                      query: '',
                    ),
                  ),
                  _NavTile(
                    icon: LucideIcons.trash2,
                    label: 'Clear All',
                    active: false,
                    danger: true,
                    onTap: () => _confirmClearAgent(context, app),
                  ),
                ],
              ],
            ),
          ),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 180),
        ),
      ],
    );
  }
}
