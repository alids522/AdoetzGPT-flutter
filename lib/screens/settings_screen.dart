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
              const SizedBox(height: 28),
              _ProfileSection(copy: copy),
              const SizedBox(height: 22),
              const _MemorySection(),
              const SizedBox(height: 22),
              _SyncSection(
                guestUser: guestUser,
                guestPass: guestPass,
                savingGuest: savingGuest,
                onSavingGuest: (value) => setState(() => savingGuest = value),
              ),
              const SizedBox(height: 22),
              _ApiSection(copy: copy),
              const SizedBox(height: 22),
              _EndpointSection(copy: copy),
              const SizedBox(height: 22),
              _VoiceSection(copy: copy),
              const SizedBox(height: 22),
              const _WebSearchSection(),
              const SizedBox(height: 22),
              const _MediaSection(),
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
                          decoration: const InputDecoration(
                            labelText: 'Username',
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
                    _SettingField(
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
              values: ['', ...app.endpoints.map((item) => item.id)],
              labels: {
                for (final ep in app.endpoints) ep.id: ep.name,
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

class _SettingField extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _labelStyle(context)),
        const SizedBox(height: 7),
        TextFormField(
          key: ValueKey('$label-$initialValue'),
          initialValue: initialValue,
          obscureText: obscure,
          minLines: minLines,
          maxLines: obscure ? 1 : maxLines,
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
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
