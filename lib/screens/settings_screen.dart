import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../translations.dart';
import '../ui/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final guestUser = TextEditingController();
  final guestPass = TextEditingController();
  bool savingGuest = false;
  String _selectedCategory = 'General';

  final _categories = const [
    'General',
    'AI & Generation',
    'Voice & Live',
    'Integrations',
    'Sync & Data',
  ];

  @override
  void dispose() {
    guestUser.dispose();
    guestPass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final copy = UiCopy(app.language);
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CONFIGURATION',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.cyan.shade400,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${copy.t('settings', 'title')}.',
                style: TextStyle(
                  fontSize: 42,
                  color: p.primary,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Customize your AI workspace environment, custom models, and database synchronization.',
                style: TextStyle(
                  fontSize: 12,
                  color: p.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((category) {
                    final selected = category == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: selected,
                        onSelected: (value) {
                          if (value) setState(() => _selectedCategory = category);
                        },
                        selectedColor: p.primary.withValues(alpha: 0.2),
                        labelStyle: TextStyle(
                          color: selected ? p.primary : p.onSurfaceVariant,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        backgroundColor: p.surface,
                        side: BorderSide(
                          color: selected ? p.primary : p.outline,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 28),
              if (_selectedCategory == 'General') ...[
                _ProfileSection(copy: copy),
                const SizedBox(height: 22),
                const _ExperienceSection(),
              ],
              if (_selectedCategory == 'AI & Generation') ...[
                const _MemorySection(),
                const SizedBox(height: 22),
                const _TitleGenerationSection(),
                const SizedBox(height: 22),
                _EndpointSection(copy: copy),
                const SizedBox(height: 22),
                const _ModelCostsSection(),
              ],
              if (_selectedCategory == 'Integrations') ...[
                _ApiSection(copy: copy),
                const SizedBox(height: 22),
                const _ConnectorSection(),
                const SizedBox(height: 22),
                const _WebSearchSection(),
              ],
              if (_selectedCategory == 'Voice & Live') ...[
                _VoiceSection(copy: copy),
                const SizedBox(height: 22),
                const _MediaSection(),
              ],
              if (_selectedCategory == 'Sync & Data') ...[
                _SyncSection(
                  guestUser: guestUser,
                  guestPass: guestPass,
                  savingGuest: savingGuest,
                  onSavingGuest: (value) => setState(() => savingGuest = value),
                ),
              ],
              const SizedBox(height: 30),
              _ActionBar(copy: copy),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.copy});

  final UiCopy copy;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: LucideIcons.user,
            title: copy.t('settings', 'profile'),
            accent: const Color(0xfff43f5e),
          ),
          const SizedBox(height: 18),
          _SettingField(
            label: copy.t('settings', 'displayName'),
            initialValue: app.userName,
            onChanged: (value) => app.updateProfile(name: value),
          ),
          const SizedBox(height: 16),
          Text(
            copy.t('settings', 'language').toUpperCase(),
            style: _labelStyle(context),
          ),
          const SizedBox(height: 8),
          SegmentedPills<AppLanguage>(
            value: app.language,
            items: const [
              SegmentItem(value: AppLanguage.id, label: 'Indonesia'),
              SegmentItem(value: AppLanguage.en, label: 'English'),
            ],
            onChanged: (value) => app.updateProfile(nextLanguage: value),
          ),
        ],
      ),
    );
  }
}

class _ExperienceSection extends StatelessWidget {
  const _ExperienceSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.slidersHorizontal,
            title: 'Experience',
            accent: Color(0xff38bdf8),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: app.isDark,
            onChanged: (_) => app.toggleTheme(),
            title: const Text('Dark mode'),
            subtitle: Text(
              app.isDark
                  ? 'Dark interface is active.'
                  : 'Light interface is active.',
              style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
            ),
          ),
          const SizedBox(height: 14),
          const _ThemeSelector(),
          const SizedBox(height: 14),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: app.genSettings.hapticStreamingEnabled,
            onChanged: (value) => app.updateGenerationSettings(
              app.genSettings.copyWith(hapticStreamingEnabled: value),
            ),
            title: const Text('Streaming haptics'),
            subtitle: Text(
              'Vibrate lightly while Android streams model responses.',
              style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
            ),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: app.soundEffectsEnabled,
            onChanged: (value) => app.setSoundEffectsEnabled(value),
            title: const Text('Sound effects'),
            subtitle: Text(
              'Play audio cues for messaging and voice mode.',
              style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorySection extends StatelessWidget {
  const _MemorySection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.brain,
            title: 'Memory',
            accent: Color(0xffa78bfa),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: app.genSettings.memoryEnabled,
            onChanged: app.updateMemoryEnabled,
            title: const Text('Enable memory'),
            subtitle: Text(
              app.genSettings.memoryEnabled
                  ? '${app.memories.length} saved memories can be used in chat context.'
                  : 'Saved memories are kept, but new messages will not save or inject memory.',
              style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
            ),
          ),
          if (app.memories.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: app.memories.take(6).map((memory) {
                return Chip(
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      memory.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  onDeleted: () => app.deleteMemory(memory.id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('THEME STYLE', style: _labelStyle(context)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth > 560;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: appVisualThemeOptions.map((option) {
                final selected = app.visualTheme == option.key;
                final width = twoColumns
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
                return SizedBox(
                  width: width,
                  child: _ThemeOptionTile(
                    option: option,
                    selected: selected,
                    palette: p,
                    onTap: () => app.setVisualTheme(option.key),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _ThemeOptionTile extends StatefulWidget {
  const _ThemeOptionTile({
    required this.option,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final AppVisualThemeOption option;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  State<_ThemeOptionTile> createState() => _ThemeOptionTileState();
}

class _ThemeOptionTileState extends State<_ThemeOptionTile> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final reducedMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = widget.selected || hovered;
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedScale(
        scale: reducedMotion ? 1 : (hovered ? 1.015 : 1),
        duration: Duration(milliseconds: reducedMotion ? 1 : 140),
        curve: Curves.easeOutCubic,
        child: InkWell(
          borderRadius: BorderRadius.circular(p.cardRadius),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: reducedMotion ? 1 : 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: widget.selected
                  ? p.primary.withValues(alpha: p.isAurora ? 0.18 : 0.12)
                  : p.surfaceDim,
              borderRadius: BorderRadius.circular(p.cardRadius),
              border: Border.all(
                color: widget.selected ? p.primary : p.outline,
                width: widget.selected ? 1.2 : 1,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: (widget.selected ? p.primary : p.glow)
                            .withValues(alpha: p.isAurora ? 0.26 : 0.14),
                        blurRadius: p.isMinimal ? 14 : 22,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: widget.selected ? p.primary : p.outline,
                    ),
                  ),
                  child: Icon(widget.option.icon, size: 18, color: p.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.option.label,
                        style: TextStyle(
                          color: p.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.option.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: p.onSurfaceVariant,
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: widget.selected ? 1 : 0,
                  duration: Duration(milliseconds: reducedMotion ? 1 : 120),
                  child: Icon(LucideIcons.check, size: 18, color: p.primary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleGenerationSection extends StatelessWidget {
  const _TitleGenerationSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final settings = app.genSettings;
    final fallbackModel = app.models.contains(app.selectedModel)
        ? app.selectedModel
        : (app.models.isNotEmpty ? app.models.first : app.selectedModel);
    final selectedTitleModel = settings.titleModel.trim().isNotEmpty
        ? settings.titleModel.trim()
        : fallbackModel;
    final modelValues = {
      if (selectedTitleModel.trim().isNotEmpty) selectedTitleModel,
      if (app.selectedModel.trim().isNotEmpty) app.selectedModel,
      ...app.models.where((model) => model.trim().isNotEmpty),
    }.toList();

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.panelTop,
            title: 'Title Generation',
            accent: Color(0xff22c55e),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: settings.titleModelEnabled,
            onChanged: (value) {
              app.updateGenerationSettings(
                settings.copyWith(
                  titleModelEnabled: value,
                  titleModel: settings.titleModel.trim().isNotEmpty
                      ? settings.titleModel
                      : selectedTitleModel,
                ),
              );
            },
            title: const Text('Use dedicated title model'),
            subtitle: Text(
              settings.titleModelEnabled
                  ? 'Session titles use ${app.formatTargetName(selectedTitleModel)}.'
                  : 'Session titles use the same model as the active chat.',
              style: TextStyle(color: p.onSurfaceVariant, fontSize: 12),
            ),
          ),
          if (settings.titleModelEnabled) ...[
            const SizedBox(height: 12),
            _DropdownSetting(
              label: 'Title Model',
              value: selectedTitleModel,
              values: modelValues,
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(titleModel: value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncSection extends StatelessWidget {
  const _SyncSection({
    required this.guestUser,
    required this.guestPass,
    required this.savingGuest,
    required this.onSavingGuest,
  });

  final TextEditingController guestUser;
  final TextEditingController guestPass;
  final bool savingGuest;
  final ValueChanged<bool> onSavingGuest;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final db = app.syncSettings.database;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.database,
            title: 'Postgres Sync',
            accent: Colors.cyan,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: p.surfaceDim,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.currentUser?.label ?? 'User',
                          style: TextStyle(
                            color: p.primary,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          app.currentUser?.isGuest == true
                              ? 'Guest mode'
                              : (app.currentUser?.username ?? ''),
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                          ),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (app.lastSyncAt != null)
                          Chip(
                            label: Text(
                              'Last Sync ${DateFormat.yMd().add_jm().format(DateTime.fromMillisecondsSinceEpoch(app.lastSyncAt!))}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        FilterChip(
                          selected: app.syncSettings.enabled,
                          label: Text(
                            app.syncSettings.enabled ? 'Sync On' : 'Sync Off',
                          ),
                          onSelected: (value) => app.updateSyncSettings(
                            app.syncSettings.copyWith(enabled: value),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (app.currentUser?.isGuest == true) ...[
                  const SizedBox(height: 18),
                  GlassPanel(
                    radius: 18,
                    padding: const EdgeInsets.all(16),
                    backgroundColor: p.surface,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              LucideIcons.sparkles,
                              color: p.primary,
                              size: 14,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'SAVE GUEST SESSION',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: guestUser,
                          decoration: InputDecoration(
                            labelText: app.syncSettings.useSupabase ? 'Email' : 'Username',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: guestPass,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: savingGuest
                                ? null
                                : () async {
                                    onSavingGuest(true);
                                    try {
                                      await app.saveGuestSession(
                                        guestUser.text,
                                        guestPass.text,
                                      );
                                      guestPass.clear();
                                    } finally {
                                      onSavingGuest(false);
                                    }
                                  },
                            child: Text(
                              savingGuest ? 'Saving...' : 'Save Guest Session',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use Supabase as Primary Engine'),
                  subtitle: const Text('Connect directly to Supabase using native SDK.'),
                  value: app.syncSettings.useSupabase,
                  onChanged: (value) => app.updateSyncSettings(
                    app.syncSettings.copyWith(useSupabase: value),
                  ),
                ),
                if (app.syncSettings.useSupabase) ...[
                  const SizedBox(height: 12),
                  _SettingField(
                    label: 'Supabase URL',
                    initialValue: app.syncSettings.supabaseUrl,
                    onChanged: (value) => app.updateSyncSettings(
                      app.syncSettings.copyWith(supabaseUrl: value),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingField(
                    label: 'Supabase Anon Key',
                    initialValue: app.syncSettings.supabaseAnonKey,
                    obscure: true,
                    onChanged: (value) => app.updateSyncSettings(
                      app.syncSettings.copyWith(supabaseAnonKey: value),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  _SettingField(
                    label: 'Sync API URL',
                  initialValue: app.syncSettings.apiBaseUrl,
                  hint: kIsWeb
                      ? 'Chrome uses HTTP sync API, usually http://127.0.0.1:3000'
                      : 'Blank = direct Postgres on Android',
                  onChanged: (value) => app.updateSyncSettings(
                    app.syncSettings.copyWith(apiBaseUrl: value),
                  ),
                ),
                const SizedBox(height: 12),
                _SettingField(
                  label: 'Database URL',
                  initialValue: db.databaseUrl,
                  onChanged: (value) =>
                      _updateDb(context, db.copyWith(databaseUrl: value)),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SettingField(
                        label: 'Database',
                        initialValue: db.database,
                        onChanged: (value) =>
                            _updateDb(context, db.copyWith(database: value)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SettingField(
                        label: 'Database Schema',
                        initialValue: db.schemaName,
                        onChanged: (value) => _updateDb(
                          context,
                          db.copyWith(
                            schemaName: value.isEmpty ? 'adoetzgpt' : value,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SettingField(
                        label: 'User',
                        initialValue: db.user,
                        onChanged: (value) =>
                            _updateDb(context, db.copyWith(user: value)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SettingField(
                        label: 'Password',
                        initialValue: db.password,
                        obscure: true,
                        onChanged: (value) =>
                            _updateDb(context, db.copyWith(password: value)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingField(
                  label: 'Custom Database Port',
                  initialValue: db.port,
                  hint: 'Blank = 5432',
                  onChanged: (value) =>
                      _updateDb(context, db.copyWith(port: value)),
                ),
                ],
                const SizedBox(height: 20),
                _BackupDatabases(),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: app.syncNow,
                      icon: const Icon(LucideIcons.rotateCw, size: 16),
                      label: const Text('Sync Now'),
                    ),
                    if (app.syncStatus.isNotEmpty)
                      Chip(
                        label: Text(
                          app.syncStatus,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _updateDb(BuildContext context, DatabaseSettings next) {
    final app = context.read<AdoetzAppState>();
    app.updateSyncSettings(app.syncSettings.copyWith(database: next));
  }
}

class _BackupDatabases extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Backup Databases',
                style: TextStyle(color: p.primary, fontWeight: FontWeight.w800),
              ),
            ),
            TextButton.icon(
              onPressed: () => app.updateSyncSettings(
                app.syncSettings.copyWith(
                  backupDatabases: [
                    ...app.syncSettings.backupDatabases,
                    const DatabaseSettings(),
                  ],
                ),
              ),
              icon: const Icon(LucideIcons.plus, size: 14),
              label: const Text('Add Backup'),
            ),
          ],
        ),
        if (app.syncSettings.backupDatabases.isNotEmpty)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto Sync Backups'),
            value: app.syncSettings.autoSyncBackups,
            onChanged: (value) => app.updateSyncSettings(
              app.syncSettings.copyWith(autoSyncBackups: value),
            ),
          ),
        ...app.syncSettings.backupDatabases.asMap().entries.map((entry) {
          final index = entry.key;
          final db = entry.value;
          void update(DatabaseSettings next) {
            final list = [...app.syncSettings.backupDatabases];
            list[index] = next;
            app.updateSyncSettings(
              app.syncSettings.copyWith(backupDatabases: list),
            );
          }

          return GlassPanel(
            radius: 18,
            padding: const EdgeInsets.all(14),
            backgroundColor: p.surface,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Backup ${index + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        final list = [...app.syncSettings.backupDatabases];
                        final oldPrimary = app.syncSettings.database;
                        final newPrimary = list[index];
                        list[index] = oldPrimary;
                        app.updateSyncSettings(
                          app.syncSettings.copyWith(
                            database: newPrimary,
                            backupDatabases: list,
                          ),
                        );
                      },
                      child: const Text('Make Primary'),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 16),
                      onPressed: () {
                        final list = [...app.syncSettings.backupDatabases]
                          ..removeAt(index);
                        app.updateSyncSettings(
                          app.syncSettings.copyWith(backupDatabases: list),
                        );
                      },
                    ),
                  ],
                ),
                _SettingField(
                  label: 'Database URL',
                  initialValue: db.databaseUrl,
                  onChanged: (value) => update(db.copyWith(databaseUrl: value)),
                ),
                const SizedBox(height: 8),
                _SettingField(
                  label: 'Database',
                  initialValue: db.database,
                  onChanged: (value) => update(db.copyWith(database: value)),
                ),
                const SizedBox(height: 8),
                _SettingField(
                  label: 'Schema',
                  initialValue: db.schemaName,
                  onChanged: (value) => update(db.copyWith(schemaName: value)),
                ),
                const SizedBox(height: 8),
                _SettingField(
                  label: 'User',
                  initialValue: db.user,
                  onChanged: (value) => update(db.copyWith(user: value)),
                ),
                const SizedBox(height: 8),
                _SettingField(
                  label: 'Password',
                  initialValue: db.password,
                  obscure: true,
                  onChanged: (value) => update(db.copyWith(password: value)),
                ),
                const SizedBox(height: 8),
                _SettingField(
                  label: 'Port',
                  initialValue: db.port,
                  onChanged: (value) => update(db.copyWith(port: value)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _ApiSection extends StatelessWidget {
  const _ApiSection({required this.copy});

  final UiCopy copy;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: LucideIcons.key,
            title: copy.t('settings', 'apiKey'),
            accent: Colors.amber,
          ),
          const SizedBox(height: 18),
          _SettingField(
            label: copy.t('settings', 'apiKey'),
            initialValue: app.geminiApiKey,
            hint: copy.t('settings', 'apiPlaceholder'),
            obscure: true,
            onChanged: app.updateGeminiKey,
          ),
        ],
      ),
    );
  }
}

class _EndpointSection extends StatelessWidget {
  const _EndpointSection({required this.copy});

  final UiCopy copy;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: LucideIcons.server,
            title: copy.t('settings', 'endpoints'),
            accent: Colors.blue,
          ),
          const SizedBox(height: 16),
          ...app.endpoints.map((endpoint) {
            void update(EndpointConfig next) {
              app.updateEndpoints(
                app.endpoints
                    .map((item) => item.id == endpoint.id ? next : item)
                    .toList(),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassPanel(
                radius: 20,
                padding: const EdgeInsets.all(16),
                backgroundColor: p.surfaceDim,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _SettingField(
                            label: 'Name',
                            initialValue: endpoint.name,
                            onChanged: (value) =>
                                update(endpoint.copyWith(name: value)),
                          ),
                        ),
                        Switch(
                          value: endpoint.enabled,
                          onChanged: (value) =>
                              update(endpoint.copyWith(enabled: value)),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          onPressed: app.endpoints.length == 1
                              ? null
                              : () => app.updateEndpoints(
                                  app.endpoints
                                      .where((item) => item.id != endpoint.id)
                                      .toList(),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _SettingField(
                      label: 'Base URL',
                      initialValue: endpoint.url,
                      onChanged: (value) =>
                          update(endpoint.copyWith(url: value)),
                    ),
                    const SizedBox(height: 10),
                    _SettingField(
                      label: 'API Key',
                      initialValue: endpoint.key,
                      obscure: true,
                      onChanged: (value) =>
                          update(endpoint.copyWith(key: value)),
                    ),
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Skip model fetch'),
                      value: endpoint.skipModelFetch,
                      onChanged: (value) =>
                          update(endpoint.copyWith(skipModelFetch: value)),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _SettingField(
                            label: 'Predefined Models',
                            initialValue: endpoint.models.join('\n'),
                            minLines: 2,
                            maxLines: 5,
                            hint: 'One model per line',
                            onChanged: (value) => update(
                              endpoint.copyWith(
                                models: value
                                    .split(RegExp(r'[\n,]'))
                                    .map((item) => item.trim())
                                    .where((item) => item.isNotEmpty)
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: FilledButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => _ModelSelectionDialog(
                                endpoint: endpoint,
                                onSave: (models) {
                                  update(
                                    endpoint.copyWith(
                                      models: models,
                                      skipModelFetch: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                            icon: const Icon(
                              LucideIcons.cloudDownload,
                              size: 16,
                            ),
                            label: const Text('Fetch'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () => app.updateEndpoints([
                  ...app.endpoints,
                  EndpointConfig(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    name: 'New Endpoint',
                    url: '',
                    key: '',
                  ),
                ]),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Endpoint'),
              ),
              FilledButton.icon(
                onPressed: app.isFetchingModels ? null : app.fetchModels,
                icon: app.isFetchingModels
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.refreshCw, size: 16),
                label: Text(
                  app.isFetchingModels ? 'Fetching...' : 'Fetch Models',
                ),
              ),
            ],
          ),
          if (app.modelFetchStatus.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              app.modelFetchStatus,
              style: TextStyle(
                color: app.modelFetchStatus.toLowerCase().contains('failed')
                    ? p.error
                    : p.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelCostsSection extends StatefulWidget {
  const _ModelCostsSection();

  @override
  State<_ModelCostsSection> createState() => _ModelCostsSectionState();
}

class _ModelCostsSectionState extends State<_ModelCostsSection> {
  String _newModelName = '';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );

    final configuredModels = <String>{
      ...app.modelInputCosts.keys,
      ...app.modelOutputCosts.keys,
      ...app.modelCacheHitCosts.keys,
    }.toList()..sort();

    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: Icons.attach_money,
            title: 'Model Cost Pricing',
            accent: Colors.green,
          ),
          const SizedBox(height: 16),
          ...configuredModels.map((model) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: GlassPanel(
                radius: 20,
                padding: const EdgeInsets.all(16),
                backgroundColor: p.surfaceDim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            model,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.trash2, size: 18),
                          onPressed:
                              () => app.updateModelCost(model, null, null, null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _SettingField(
                            label: 'Input / 1M (\$)',
                            initialValue:
                                app.modelInputCosts[model]?.toString() ?? '',
                            hint: '0.15',
                            onChanged:
                                (v) => app.updateModelCost(
                                  model,
                                  double.tryParse(v) ?? 0.0,
                                  app.modelOutputCosts[model],
                                  app.modelCacheHitCosts[model],
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SettingField(
                            label: 'Output / 1M (\$)',
                            initialValue:
                                app.modelOutputCosts[model]?.toString() ?? '',
                            hint: '0.60',
                            onChanged:
                                (v) => app.updateModelCost(
                                  model,
                                  app.modelInputCosts[model],
                                  double.tryParse(v) ?? 0.0,
                                  app.modelCacheHitCosts[model],
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _SettingField(
                            label: 'Cache Hit / 1M (\$)',
                            initialValue:
                                app.modelCacheHitCosts[model]?.toString() ?? '',
                            hint: '0.04',
                            onChanged:
                                (v) => app.updateModelCost(
                                  model,
                                  app.modelInputCosts[model],
                                  app.modelOutputCosts[model],
                                  double.tryParse(v) ?? 0.0,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ADD MODEL', style: _labelStyle(context)),
                    const SizedBox(height: 7),
                    InkWell(
                      onTap: () async {
                        final models = app.models
                            .where((m) => !configuredModels.contains(m))
                            .toList();
                        final result = await showDialog<String>(
                          context: context,
                          builder: (context) => _SettingsModelPicker(models: models),
                        );
                        if (result != null) {
                          setState(() => _newModelName = result);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: p.outline),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _newModelName.isEmpty ? 'Select model...' : _newModelName,
                                style: TextStyle(
                                  color: _newModelName.isEmpty
                                      ? p.onSurfaceVariant
                                      : p.onSurface,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(LucideIcons.chevronDown, size: 16, color: p.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 26),
                child: OutlinedButton.icon(
                  onPressed:
                      _newModelName.trim().isEmpty
                          ? null
                          : () {
                            app.updateModelCost(_newModelName.trim(), 0, 0, 0);
                            setState(() => _newModelName = '');
                          },
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsModelPicker extends StatefulWidget {
  const _SettingsModelPicker({required this.models});
  final List<String> models;

  @override
  State<_SettingsModelPicker> createState() => _SettingsModelPickerState();
}

class _SettingsModelPickerState extends State<_SettingsModelPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final normalized = query.toLowerCase();
    final filtered = widget.models
        .where((m) => m.toLowerCase().contains(normalized))
        .toList();

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 330,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: p.isDark ? const Color(0xff111111) : Colors.white,
            borderRadius: BorderRadius.circular(22),
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
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                child: Row(
                  children: [
                    Icon(LucideIcons.bot, size: 16, color: p.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select Model',
                        style: TextStyle(
                          color: p.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.x, size: 16),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(LucideIcons.search, size: 16),
                    hintText: 'Search models...',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: Text(
                          'No models match your search.',
                          style: TextStyle(
                            color: p.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final m = filtered[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              m,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.pop(context, m),
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
}

class _ConnectorSection extends StatelessWidget {
  const _ConnectorSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.serverCog,
            title: 'Agent Servers',
            accent: Color(0xff22c55e),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure OpenClaw, Hermes, and OpenAI-compatible agent connectors. Use a backend proxy with encrypted secret storage for production credentials.',
            style: TextStyle(
              color: p.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          if (app.agentConnectors.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: p.surfaceDim,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: p.outline),
              ),
              child: Text(
                'No Agent Servers configured yet.',
                style: TextStyle(color: p.onSurfaceVariant),
              ),
            )
          else
            ...app.agentConnectors.map(
              (connector) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ConnectorEditor(connector: connector),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    app.upsertAgentConnector(AgentConnector.empty()),
                icon: const Icon(LucideIcons.plus, size: 16),
                label: const Text('Add Connector'),
              ),
              OutlinedButton.icon(
                onPressed: app.agentConnectors.isEmpty
                    ? null
                    : () {
                        for (final connector in app.agentConnectors) {
                          unawaited(app.testAgentConnector(connector.id));
                        }
                      },
                icon: const Icon(LucideIcons.activity, size: 16),
                label: const Text('Test All'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectorEditor extends StatelessWidget {
  const _ConnectorEditor({required this.connector});

  final AgentConnector connector;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );

    void update(AgentConnector next) => app.upsertAgentConnector(next);

    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(16),
      backgroundColor: p.surfaceDim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ConnectorStatusDot(status: connector.status),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  connector.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (connector.isDefault)
                Chip(
                  label: const Text('Default'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: p.primary.withValues(alpha: 0.5)),
                ),
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(LucideIcons.trash2, size: 18),
                onPressed: () => app.deleteAgentConnector(connector.id),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingField(
            label: 'Name',
            initialValue: connector.name,
            onChanged: (value) => update(connector.copyWith(name: value)),
          ),
          const SizedBox(height: 10),
          _DropdownSetting(
            label: 'Connector Type',
            value: connectorTypeCode(connector.type),
            values: const [
              'openclaw_gateway',
              'hermes_agent',
              'generic_openai_compatible',
            ],
            labels: const {
              'openclaw_gateway': 'OpenClaw Gateway',
              'hermes_agent': 'Hermes Agent',
              'generic_openai_compatible': 'Generic OpenAI Compatible',
            },
            onChanged: (value) =>
                update(connector.copyWith(type: connectorTypeFromJson(value))),
          ),
          const SizedBox(height: 10),
          _SettingField(
            label: 'Backend Proxy / Base URL',
            initialValue: connector.baseUrl,
            hint: 'https://your-backend.example.com/openclaw/home',
            onChanged: (value) => update(connector.copyWith(baseUrl: value)),
          ),
          const SizedBox(height: 10),
          _SettingField(
            label: 'Encrypted API Key / Secret Ref',
            initialValue: connector.encryptedApiKey,
            obscure: true,
            hint: 'Prefer a backend-held secret reference',
            onChanged: (value) =>
                update(connector.copyWith(encryptedApiKey: value)),
          ),
          const SizedBox(height: 10),
          _DropdownSetting(
            label: 'Permission Mode',
            value: toolPermissionModeCode(connector.permissionMode),
            values: const [
              'tools_disabled',
              'safe_auto',
              'ask_before_write',
              'ask_before_every_tool',
            ],
            labels: const {
              'tools_disabled': 'Tools disabled',
              'safe_auto': 'Safe auto',
              'ask_before_write': 'Ask before write',
              'ask_before_every_tool': 'Ask before every tool',
            },
            onChanged: (value) => update(
              connector.copyWith(
                permissionMode: toolPermissionModeFromJson(value),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                selected: connector.enabled,
                label: Text(connector.enabled ? 'Enabled' : 'Disabled'),
                onSelected: (value) =>
                    app.setConnectorEnabled(connector.id, value),
              ),
              FilterChip(
                selected: connector.isDefault,
                label: const Text('Default'),
                onSelected: (_) => app.setDefaultConnector(connector.id),
              ),
              FilterChip(
                selected: connector.capabilities.supportsStreaming,
                label: const Text('Streaming'),
                onSelected: (value) => update(
                  connector.copyWith(
                    capabilities: connector.capabilities.copyWith(
                      supportsStreaming: value,
                    ),
                  ),
                ),
              ),
              FilterChip(
                selected: connector.capabilities.supportsTools,
                label: const Text('Tools'),
                onSelected: (value) => update(
                  connector.copyWith(
                    capabilities: connector.capabilities.copyWith(
                      supportsTools: value,
                    ),
                  ),
                ),
              ),
              FilterChip(
                selected: connector.capabilities.supportsModelsEndpoint,
                label: const Text('Models Endpoint'),
                onSelected: (value) => update(
                  connector.copyWith(
                    capabilities: connector.capabilities.copyWith(
                      supportsModelsEndpoint: value,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    unawaited(app.testAgentConnector(connector.id)),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Test Connection'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    unawaited(app.syncAgentConnectorTargets(connector.id)),
                icon: const Icon(LucideIcons.cloudDownload, size: 16),
                label: const Text('Sync Targets'),
              ),
              OutlinedButton.icon(
                onPressed: () => _showLogs(context, connector),
                icon: const Icon(LucideIcons.fileText, size: 16),
                label: const Text('View Logs'),
              ),
              if (connector.latencyMs != null)
                Chip(label: Text('${connector.latencyMs}ms')),
              Chip(label: Text(connectorStatusLabel(connector.status))),
            ],
          ),
          if (connector.lastError.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              connector.lastError,
              style: TextStyle(
                color: connector.lastError.toLowerCase().contains('testing')
                    ? p.onSurfaceVariant
                    : p.error,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (connector.targets.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('TARGETS', style: _labelStyle(context)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: connector.targets
                  .take(12)
                  .map((target) => Chip(label: Text(target.displayName)))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _showLogs(BuildContext context, AgentConnector connector) {
    final logs = connector.logs.isEmpty
        ? ['No connector logs yet.']
        : connector.logs;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${connector.name} Logs'),
        content: SizedBox(
          width: 480,
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
}

class _ConnectorStatusDot extends StatelessWidget {
  const _ConnectorStatusDot({required this.status});

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
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
        ],
      ),
    );
  }
}

class _VoiceSection extends StatelessWidget {
  const _VoiceSection({required this.copy});

  final UiCopy copy;

  static const voices = ['Puck', 'Charon', 'Kore', 'Fenrir', 'Zephyr'];
  static const personalities = [
    'Assistant',
    'Therapist',
    'Story teller',
    'Meditation',
    'Doctor',
    'Argumentative',
    'Romantic',
    'Conspiracy',
    'Natural human',
    'Custom',
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            icon: LucideIcons.mic,
            title: copy.t('settings', 'geminiLive'),
            accent: Colors.teal,
          ),
          const SizedBox(height: 18),
          _SettingField(
            label: 'Live Model (Override)',
            initialValue: app.voiceSettings.liveModel,
            hint: 'e.g. gemini-3.1-flash-live-preview',
            onChanged: (value) => app.updateVoiceSettings(
              app.voiceSettings.copyWith(liveModel: value),
            ),
          ),
          const SizedBox(height: 12),
          _DropdownSetting(
            label: 'Voice',
            value: app.voiceSettings.voice,
            values: voices,
            onChanged: (value) => app.updateVoiceSettings(
              app.voiceSettings.copyWith(voice: value),
            ),
          ),
          const SizedBox(height: 12),
          _DropdownSetting(
            label: copy.t('settings', 'personality'),
            value: app.voiceSettings.personality,
            values: personalities,
            onChanged: (value) => app.updateVoiceSettings(
              app.voiceSettings.copyWith(personality: value),
            ),
          ),
          if (app.voiceSettings.personality == 'Custom') ...[
            const SizedBox(height: 12),
            _SettingField(
              label: 'Custom Voice Personality',
              initialValue: app.voiceSettings.customPersonality,
              minLines: 3,
              maxLines: 6,
              onChanged: (value) => app.updateVoiceSettings(
                app.voiceSettings.copyWith(customPersonality: value),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _DropdownSetting(
            label: copy.t('settings', 'textPersonality'),
            value: app.voiceSettings.textPersonality,
            values: personalities,
            onChanged: (value) => app.updateVoiceSettings(
              app.voiceSettings.copyWith(textPersonality: value),
            ),
          ),
          if (app.voiceSettings.textPersonality == 'Custom') ...[
            const SizedBox(height: 12),
            _SettingField(
              label: 'Custom Text Personality',
              initialValue: app.voiceSettings.customTextPersonality,
              minLines: 3,
              maxLines: 6,
              onChanged: (value) => app.updateVoiceSettings(
                app.voiceSettings.copyWith(customTextPersonality: value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebSearchSection extends StatelessWidget {
  const _WebSearchSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final settings = app.genSettings;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.activity,
            title: 'Web Search',
            accent: Colors.lightBlue,
          ),
          const SizedBox(height: 18),
          Text('SEARCH MODE', style: _labelStyle(context)),
          const SizedBox(height: 8),
          SegmentedPills<String>(
            value: settings.webSearchMode,
            items: const [
              SegmentItem(value: 'off', label: 'Off'),
              SegmentItem(value: 'auto', label: 'Auto'),
              SegmentItem(value: 'on', label: 'On'),
            ],
            onChanged: (value) => app.updateGenerationSettings(
              settings.copyWith(webSearchMode: value),
            ),
          ),
          const SizedBox(height: 18),
          Text('SEARCH ENGINE', style: _labelStyle(context)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                [
                  'gemini',
                  'google-custom',
                  'duckduckgo',
                  'endpoint',
                  'tavily',
                ].map((engine) {
                  final selected = settings.webSearchEngine == engine;
                  return ChoiceChip(
                    selected: selected,
                    label: Text(_engineLabel(engine)),
                    onSelected: (_) => app.updateGenerationSettings(
                      settings.copyWith(
                        webSearchEngine: engine,
                        webSearchProvider: engine == 'endpoint'
                            ? 'endpoint'
                            : 'gemini',
                      ),
                    ),
                  );
                }).toList(),
          ),
          const SizedBox(height: 14),
          if (settings.webSearchEngine == 'google-custom') ...[
            _SettingField(
              label: 'Google API Key',
              initialValue: settings.googleSearchApiKey,
              obscure: true,
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(googleSearchApiKey: value),
              ),
            ),
            const SizedBox(height: 10),
            _SettingField(
              label: 'Search Engine ID (cx)',
              initialValue: settings.googleSearchCx,
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(googleSearchCx: value),
              ),
            ),
          ] else if (settings.webSearchEngine == 'tavily') ...[
            _SettingField(
              label: 'Tavily API Key',
              initialValue: settings.tavilyApiKey,
              obscure: true,
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(tavilyApiKey: value),
              ),
            ),
          ] else if (settings.webSearchEngine == 'endpoint') ...[
            _DropdownSetting(
              label: 'Endpoint',
              value: settings.webSearchEndpointId,
              values: ['', ...app.endpoints.where((e) => e.enabled).map((item) => item.id)],
              labels: {
                for (final ep in app.endpoints.where((e) => e.enabled)) ep.id: ep.name,
                '': 'Select endpoint',
              },
              onChanged: (value) {
                final firstModel = app.endpointModels
                    .where((item) => item.endpointId == value)
                    .firstOrNull;
                app.updateGenerationSettings(
                  settings.copyWith(
                    webSearchEndpointId: value,
                    webSearchModel: firstModel?.name ?? '',
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _DropdownSetting(
              label: 'Model',
              value: settings.webSearchModel,
              values: [
                '',
                ...app.endpointModels
                    .where(
                      (item) =>
                          settings.webSearchEndpointId.isEmpty ||
                          item.endpointId == settings.webSearchEndpointId,
                    )
                    .map((item) => item.name),
              ],
              labels: const {'': 'Select model'},
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(webSearchModel: value),
              ),
            ),
          ] else if (settings.webSearchEngine == 'gemini') ...[
            _DropdownSetting(
              label: 'Gemini Search Model',
              value: settings.webSearchModel,
              values: {
                'gemini-flash-lite-latest',
                'gemini-2.5-flash',
                ...app.geminiModels,
              }.toList(),
              onChanged: (value) => app.updateGenerationSettings(
                settings.copyWith(webSearchModel: value),
              ),
            ),
          ] else
            const Text('No API key required.'),
        ],
      ),
    );
  }

  String _engineLabel(String value) {
    return switch (value) {
      'google-custom' => 'Google Custom',
      'duckduckgo' => 'DuckDuckGo',
      'endpoint' => 'Endpoint',
      'tavily' => 'Tavily AI',
      _ => 'Gemini Grounding',
    };
  }
}

class _MediaSection extends StatelessWidget {
  const _MediaSection();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            icon: LucideIcons.sparkles,
            title: 'Media Generation',
            accent: Colors.purpleAccent,
          ),
          const SizedBox(height: 18),
          Text('IMAGE MODEL', style: _labelStyle(context)),
          const SizedBox(height: 8),
          SegmentedPills<String>(
            value: app.genSettings.imageModel,
            items: const [
              SegmentItem(value: 'gemini', label: 'Gemini'),
              SegmentItem(value: 'openai', label: 'OpenAI'),
            ],
            onChanged: (value) => app.updateGenerationSettings(
              app.genSettings.copyWith(imageModel: value),
            ),
          ),
          const SizedBox(height: 18),
          Text('VIDEO MODEL', style: _labelStyle(context)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: null,
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text('Google Veo (Latest)    Active'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.copy});

  final UiCopy copy;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(copy.t('sidebar', 'signOutConfirm')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(copy.t('sidebar', 'cancel')),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(copy.t('settings', 'signOut')),
                    ),
                  ],
                ),
              );
              if (ok == true) app.signOut();
            },
            icon: Icon(LucideIcons.logOut, size: 16, color: p.error),
            label: Text(copy.t('settings', 'signOut')),
            style: OutlinedButton.styleFrom(foregroundColor: p.error),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: app.saveSettings,
            icon: const Icon(LucideIcons.save, size: 16),
            label: Text(copy.t('settings', 'save')),
          ),
        ),
      ],
    );
  }
}

class _SettingField extends StatefulWidget {
  const _SettingField({
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.hint,
    this.obscure = false,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final String initialValue;
  final String? hint;
  final bool obscure;
  final int minLines;
  final int maxLines;
  final ValueChanged<String> onChanged;

  @override
  State<_SettingField> createState() => _SettingFieldState();
}

class _SettingFieldState extends State<_SettingField> {
  late final TextEditingController _controller;
  Timer? _debounce;
  late String _lastSentValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _lastSentValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant _SettingField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      if (widget.initialValue != _lastSentValue) {
        final currentSelection = _controller.selection;
        _controller.text = widget.initialValue;
        _lastSentValue = widget.initialValue;
        if (currentSelection.isValid &&
            currentSelection.baseOffset <= widget.initialValue.length) {
          _controller.selection = currentSelection;
        }
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label.toUpperCase(), style: _labelStyle(context)),
        const SizedBox(height: 7),
        TextFormField(
          controller: _controller,
          obscureText: widget.obscure,
          minLines: widget.minLines,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          decoration: InputDecoration(hintText: widget.hint),
          onChanged: (value) {
            if (_debounce?.isActive ?? false) _debounce!.cancel();
            _debounce = Timer(const Duration(milliseconds: 500), () {
              _lastSentValue = value;
              widget.onChanged(value);
            });
          },
        ),
      ],
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  const _DropdownSetting({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
    this.labels = const {},
  });

  final String label;
  final String value;
  final List<String> values;
  final Map<String, String> labels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = values.toSet().toList();
    final effectiveValue = items.contains(value)
        ? value
        : (items.isNotEmpty ? items.first : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _labelStyle(context)),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: effectiveValue,
          items: items
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(labels[item] ?? item),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    );
  }
}

TextStyle _labelStyle(BuildContext context) {
  final p = AppPalette.fromBrightness(
    Theme.of(context).brightness == Brightness.dark,
  );
  return TextStyle(
    fontSize: 10,
    color: p.onSurfaceVariant,
    fontWeight: FontWeight.w900,
    letterSpacing: 1.4,
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ModelSelectionDialog extends StatefulWidget {
  const _ModelSelectionDialog({required this.endpoint, required this.onSave});

  final EndpointConfig endpoint;
  final ValueChanged<List<String>> onSave;

  @override
  State<_ModelSelectionDialog> createState() => _ModelSelectionDialogState();
}

class _ModelSelectionDialogState extends State<_ModelSelectionDialog> {
  List<String>? _availableModels;
  String _error = '';
  String _searchQuery = '';
  final Set<String> _selectedModels = {};

  @override
  void initState() {
    super.initState();
    _selectedModels.addAll(widget.endpoint.models);
    _fetchModels();
  }

  Future<void> _fetchModels() async {
    try {
      final app = context.read<AdoetzAppState>();
      final models = await app.fetchEndpointModels(widget.endpoint);
      if (mounted) {
        setState(() {
          _availableModels = models;
          // Add previously selected ones that might not be in the list
          for (final selected in _selectedModels) {
            if (!models.contains(selected)) {
              _availableModels!.add(selected);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );

    final filteredModels =
        _availableModels
            ?.where((m) => m.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList() ??
        [];

    return AlertDialog(
      title: Text('Models for ${widget.endpoint.name}'),
      backgroundColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search models',
                  prefixIcon: Icon(LucideIcons.search),
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
            const SizedBox(height: 12),
            if (_availableModels == null && _error.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error, style: TextStyle(color: p.error)),
              )
            else
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedModels.addAll(filteredModels);
                              });
                            },
                            child: const Text('Select All'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedModels.removeAll(filteredModels);
                              });
                            },
                            child: const Text('Deselect All'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredModels.length,
                        itemBuilder: (context, index) {
                          final model = filteredModels[index];
                          return CheckboxListTile(
                            title: Text(
                              model,
                              style: const TextStyle(fontSize: 14),
                            ),
                            value: _selectedModels.contains(model),
                            onChanged: (selected) {
                              setState(() {
                                if (selected == true) {
                                  _selectedModels.add(model);
                                } else {
                                  _selectedModels.remove(model);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.onSave(_selectedModels.toList());
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
