import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models.dart';
import '../services/ai_service.dart';
import '../services/gemini_live_service.dart';
import '../services/live_foreground_service.dart';
import '../services/memory_agent.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';

class AdoetzAppState extends ChangeNotifier {
  AdoetzAppState({StorageService? storage, SyncService? sync, AiService? ai})
    : _storage = storage ?? StorageService(),
      _sync = sync ?? SyncService(),
      _ai = ai ?? AiService();

  final StorageService _storage;
  final SyncService _sync;
  final AiService _ai;
  GeminiLiveService? _liveService;
  Timer? _remoteSyncTimer;
  Timer? _liveInputReleaseTimer;
  Timer? _liveOutputPulseTimer;
  Timer? _streamFlushTimer;
  String? _activeGenerationId;
  String? _activeStreamSessionId;
  String? _activeStreamBotId;
  String _pendingStreamText = '';
  String _lastDisplayedStreamText = '';
  bool _generationStopRequested = false;
  int _stateSavedAt = 0;

  final _audioPlayer = AudioPlayer();

  bool initialized = false;
  bool isGenerating = false;
  bool isLiveActive = false;
  bool isLiveConnecting = false;
  bool isLiveRecording = false;
  bool isLiveVideoEnabled = false;
  bool isLiveFrontCamera = false;
  bool isFetchingModels = false;
  String syncStatus = '';
  String liveStatus = '';
  String modelFetchStatus = '';
  double liveInputLevel = 0;
  double liveOutputLevel = 0;
  int? lastSyncAt;
  String lastPushedHash = '';
  String? _liveUserMessageId;
  String? _liveBotMessageId;

  AppView currentView = AppView.chat;
  AppLanguage language = AppLanguage.id;
  String theme = 'dark';
  String visualTheme = 'default';
  String selectedModel = 'gemini-2.5-flash';
  String selectedTargetId = 'model:gemini-2.5-flash';
  bool isThinkingMode = false;
  bool isArtifactMode = false;
  bool soundEffectsEnabled = true;

  UserAccount? currentUser;
  String authToken = '';
  SyncSettings syncSettings = const SyncSettings();
  String userName = 'User';
  String geminiApiKey = '';
  List<EndpointConfig> endpoints = const [
    EndpointConfig(
      id: '1',
      name: 'OpenAI',
      url: 'https://api.openai.com/v1',
      key: '',
    ),
  ];
  List<AgentConnector> agentConnectors = const [];
  GenerationSettings genSettings = const GenerationSettings();
  VoiceSettings voiceSettings = const VoiceSettings();
  List<Session> sessions = [Session.empty('1', 'model:gemini-2.5-flash')];
  String currentSessionId = '1';
  List<Memory> memories = const [];
  List<TokenUsageRecord> tokenUsageData = const [];
  List<CustomCounter> customCounters = const [];
  Map<String, int> modelContextOverrides = const {};
  List<String> geminiModels = const [];
  List<EndpointModel> endpointModels = const [];
  List<String> models = const ['gemini-2.5-flash'];

  Future<void> _playSound(String name) async {
    if (!soundEffectsEnabled) return;
    try {
      await _audioPlayer.play(AssetSource('audio/$name'));
    } catch (_) {}
  }

  List<Session> get activeSessions {
    final list = sessions.where((session) => !session.deleted).toList();
    list.sort((a, b) {
      if (a.pinned && !b.pinned) return -1;
      if (!a.pinned && b.pinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  Session get currentSession {
    return activeSessions
            .where((session) => session.id == currentSessionId)
            .firstOrNull ??
        (activeSessions.isNotEmpty
            ? activeSessions.first
            : Session.empty('default', selectedTargetId));
  }

  bool get isDark => theme == 'dark';

  List<ChatTarget> get modelTargets {
    final targetModels = models.isEmpty ? [selectedModel] : models;
    return targetModels
        .where((model) => model.trim().isNotEmpty)
        .map(
          (model) =>
              ChatTarget.model(model, provider: _modelProviderLabel(model)),
        )
        .toList();
  }

  List<ChatTarget> get agentServerTargets {
    return agentConnectors
        .where((connector) => connector.enabled)
        .map((connector) => ChatTarget.agent(connector: connector))
        .toList();
  }

  List<ChatTarget> get chatTargets => [...modelTargets, ...agentServerTargets];

  ChatTarget get activeChatTarget {
    final currentTarget = currentSession.currentTargetId.trim();
    final candidates = chatTargets;
    for (final id in [selectedTargetId, currentTarget]) {
      if (id.isEmpty) continue;
      final match = candidates.where((target) => target.id == id).firstOrNull;
      if (match != null) return match;
    }
    return ChatTarget.model(
      selectedModel,
      provider: _modelProviderLabel(selectedModel),
    );
  }

  String targetLabelForSession(Session session) {
    final id = session.lastTargetId.isNotEmpty
        ? session.lastTargetId
        : session.currentTargetId;
    final target = chatTargets.where((item) => item.id == id).firstOrNull;
    if (target != null) return formatTargetName(target.displayName);
    if (id.startsWith('model:')) return formatTargetName(id.substring(6));
    if (id.startsWith('agent:')) {
      final connectorId = id.substring(6);
      final connector = agentConnectors
          .where((item) => item.id == connectorId)
          .firstOrNull;
      return connector?.name ?? 'Agent Server';
    }
    return formatTargetName(selectedModel);
  }

  Future<void> initialize() async {
    final saved = await _storage.load();
    _applyState(saved ?? PersistedAppState.defaults(), notify: false);
    if (kIsWeb && syncSettings.apiBaseUrl.trim().isEmpty) {
      syncSettings = syncSettings.copyWith(
        apiBaseUrl: SyncService.defaultWebApiBaseUrl,
      );
    }

    if (activeSessions.isEmpty) {
      final session = Session.empty(null, selectedTargetId);
      sessions = [...sessions, session];
      currentSessionId = session.id;
    } else if (!activeSessions.any(
      (session) => session.id == currentSessionId,
    )) {
      currentSessionId = activeSessions.first.id;
    }

    initialized = true;
    notifyListeners();

    LiveForegroundService.initialize();
    LiveForegroundService.onAction = (action) {
      if (action == 'end_live') {
        stopLiveConversation();
      } else if (action == 'toggle_mic') {
        toggleLiveRecording();
      }
    };

    unawaited(fetchModels());
    unawaited(_persist(touchSavedAt: false));
    unawaited(_pullRemoteStateAfterStartup());
  }

  Future<void> _pullRemoteStateAfterStartup() async {
    if (currentUser != null &&
        currentUser!.isGuest == false &&
        authToken.isNotEmpty &&
        syncSettings.enabled) {
      try {
        final remote = await _sync
            .pullRemoteState(authToken, syncSettings)
            .timeout(const Duration(seconds: 8));
        if (remote != null) {
          _applyState(_mergeRemote(buildState(), remote), notify: false);
          lastSyncAt = DateTime.now().millisecondsSinceEpoch;
          syncStatus = 'Database sync loaded.';
          notifyListeners();
          unawaited(_persist(touchSavedAt: false));
        }
      } catch (error) {
        syncStatus = 'Auto-pull failed; using local state.';
        notifyListeners();
      }
    }
  }

  PersistedAppState buildState() {
    final savedAt = _stateSavedAt > 0
        ? _stateSavedAt
        : DateTime.now().millisecondsSinceEpoch;
    final persistedSessions = sessions.toList();
    final persistedCurrentId =
        persistedSessions.any((session) => session.id == currentSessionId)
        ? currentSessionId
        : (persistedSessions.isNotEmpty
              ? persistedSessions.first.id
              : currentSessionId);
    return PersistedAppState(
      currentUser: currentUser,
      authToken: authToken,
      syncSettings: syncSettings,
      language: language,
      theme: theme,
      visualTheme: visualTheme,
      selectedModel: selectedModel,
      selectedTargetId: selectedTargetId,
      isThinkingMode: isThinkingMode,
      isArtifactMode: isArtifactMode,
      soundEffectsEnabled: soundEffectsEnabled,
      isLiveVideoEnabled: false,
      isLiveFrontCamera: isLiveFrontCamera,
      userName: userName,
      geminiApiKey: geminiApiKey,
      endpoints: endpoints,
      agentConnectors: agentConnectors,
      modelContextOverrides: modelContextOverrides,
      genSettings: genSettings,
      voiceSettings: voiceSettings,
      sessions: persistedSessions,
      currentSessionId: persistedCurrentId,
      memories: memories,
      tokenUsageData: tokenUsageData,
      customCounters: customCounters,
      savedAt: savedAt,
    );
  }

  void _applyState(PersistedAppState state, {bool notify = true}) {
    currentUser = state.currentUser;
    _stateSavedAt = state.savedAt ?? DateTime.now().millisecondsSinceEpoch;
    authToken = state.authToken;
    syncSettings = state.syncSettings;
    language = state.language;
    theme = state.theme;
    visualTheme = state.visualTheme;
    selectedModel = state.selectedModel;
    selectedTargetId = state.selectedTargetId.isEmpty
        ? 'model:$selectedModel'
        : state.selectedTargetId;
    isThinkingMode = state.isThinkingMode;
    isArtifactMode = state.isArtifactMode;
    soundEffectsEnabled = state.soundEffectsEnabled;
    isLiveVideoEnabled = false;
    isLiveFrontCamera = state.isLiveFrontCamera;
    userName = state.userName;
    geminiApiKey = state.geminiApiKey;
    endpoints = state.endpoints.isEmpty ? endpoints : state.endpoints;
    agentConnectors = state.agentConnectors;
    genSettings = state.genSettings;
    voiceSettings = state.voiceSettings;
    sessions = state.sessions.isEmpty
        ? [Session.empty('1', selectedTargetId)]
        : state.sessions;
    currentSessionId = state.currentSessionId;
    memories = state.memories;
    tokenUsageData = state.tokenUsageData;
    customCounters = state.customCounters;
    modelContextOverrides = state.modelContextOverrides;
    if (notify) notifyListeners();
  }

  PersistedAppState _mergeRemote(
    PersistedAppState local,
    PersistedAppState remote,
  ) {
    final sessionMap = <String, Session>{
      for (final session in local.sessions) session.id: session,
    };
    for (final session in remote.sessions) {
      final existing = sessionMap[session.id];
      if (existing == null || session.updatedAt > existing.updatedAt) {
        sessionMap[session.id] = session;
      }
    }
    final mergedSessions = sessionMap.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final memoryMap = <String, Memory>{
      for (final memory in local.memories) memory.id: memory,
    };
    for (final memory in remote.memories) {
      memoryMap[memory.id] = memory;
    }
    final mergedMemories = memoryMap.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final usageSeen = <String>{};
    final mergedUsage = <TokenUsageRecord>[];
    for (final record in [...local.tokenUsageData, ...remote.tokenUsageData]) {
      final key = '${record.timestamp}-${record.model}-${record.endpoint}';
      if (usageSeen.add(key)) mergedUsage.add(record);
    }
    mergedUsage.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final counterMap = <String, CustomCounter>{
      for (final counter in local.customCounters) counter.id: counter,
    };
    for (final counter in remote.customCounters) {
      counterMap.putIfAbsent(counter.id, () => counter);
    }

    final remoteIsNewer = (remote.savedAt ?? 0) >= (local.savedAt ?? 0);

    return PersistedAppState(
      currentUser: local.currentUser,
      authToken: local.authToken,
      syncSettings: local.syncSettings,
      language: remoteIsNewer ? remote.language : local.language,
      theme: remoteIsNewer ? remote.theme : local.theme,
      visualTheme: remoteIsNewer ? remote.visualTheme : local.visualTheme,
      selectedModel: remoteIsNewer && remote.selectedModel.isNotEmpty
          ? remote.selectedModel
          : local.selectedModel,
      selectedTargetId: remoteIsNewer && remote.selectedTargetId.isNotEmpty
          ? remote.selectedTargetId
          : local.selectedTargetId,
      isThinkingMode: remoteIsNewer
          ? remote.isThinkingMode
          : local.isThinkingMode,
      isArtifactMode: remoteIsNewer
          ? remote.isArtifactMode
          : local.isArtifactMode,
      userName: remoteIsNewer && remote.userName.isNotEmpty
          ? remote.userName
          : local.userName,
      geminiApiKey: remoteIsNewer && remote.geminiApiKey.isNotEmpty
          ? remote.geminiApiKey
          : local.geminiApiKey,
      endpoints: _mergeEndpointConfigs(
        local.endpoints,
        remote.endpoints,
        preferRemote: remoteIsNewer,
      ),
      agentConnectors: _mergeAgentConnectors(
        local.agentConnectors,
        remote.agentConnectors,
        preferRemote: remoteIsNewer,
      ),
      modelContextOverrides: remoteIsNewer
          ? {...local.modelContextOverrides, ...remote.modelContextOverrides}
          : {...remote.modelContextOverrides, ...local.modelContextOverrides},
      genSettings: remoteIsNewer ? remote.genSettings : local.genSettings,
      voiceSettings: remoteIsNewer ? remote.voiceSettings : local.voiceSettings,
      sessions: mergedSessions,
      currentSessionId: mergedSessions.isNotEmpty
          ? mergedSessions.first.id
          : local.currentSessionId,
      memories: mergedMemories,
      tokenUsageData: mergedUsage,
      customCounters: counterMap.values.toList(),
      soundEffectsEnabled: remoteIsNewer
          ? remote.soundEffectsEnabled
          : local.soundEffectsEnabled,
      isLiveVideoEnabled: remoteIsNewer
          ? remote.isLiveVideoEnabled
          : local.isLiveVideoEnabled,
      isLiveFrontCamera: remoteIsNewer
          ? remote.isLiveFrontCamera
          : local.isLiveFrontCamera,
      savedAt: math.max(local.savedAt ?? 0, remote.savedAt ?? 0),
    );
  }

  List<EndpointConfig> _mergeEndpointConfigs(
    List<EndpointConfig> local,
    List<EndpointConfig> remote, {
    required bool preferRemote,
  }) {
    final merged = <String, EndpointConfig>{};
    for (final endpoint in local) {
      merged[_endpointMergeKey(endpoint)] = endpoint;
    }
    for (final endpoint in remote) {
      final key = _endpointMergeKey(endpoint);
      final existing = merged[key];
      if (existing == null) {
        merged[key] = endpoint;
      } else {
        merged[key] = _mergeEndpointConfig(
          existing,
          endpoint,
          preferRemote: preferRemote,
        );
      }
    }
    return merged.values.toList();
  }

  EndpointConfig _mergeEndpointConfig(
    EndpointConfig local,
    EndpointConfig remote, {
    required bool preferRemote,
  }) {
    final primary = preferRemote ? remote : local;
    final fallback = preferRemote ? local : remote;
    final models = LinkedHashSetString(
      preferRemote
          ? [...remote.models, ...local.models]
          : [...local.models, ...remote.models],
    ).toList();
    return EndpointConfig(
      id: primary.id.isNotEmpty ? primary.id : fallback.id,
      url: primary.url.isNotEmpty ? primary.url : fallback.url,
      key: primary.key.isNotEmpty ? primary.key : fallback.key,
      name: primary.name.isNotEmpty ? primary.name : fallback.name,
      skipModelFetch: primary.skipModelFetch,
      models: models,
    );
  }

  String _endpointMergeKey(EndpointConfig endpoint) {
    if (endpoint.id.trim().isNotEmpty) return 'id:${endpoint.id.trim()}';
    final name = endpoint.name.trim().toLowerCase();
    final url = endpoint.url.trim().toLowerCase();
    return 'endpoint:$name|$url';
  }

  List<AgentConnector> _mergeAgentConnectors(
    List<AgentConnector> local,
    List<AgentConnector> remote, {
    required bool preferRemote,
  }) {
    final merged = <String, AgentConnector>{};
    for (final connector in local) {
      merged[_agentConnectorMergeKey(connector)] = connector;
    }
    for (final connector in remote) {
      final key = _agentConnectorMergeKey(connector);
      final existing = merged[key];
      if (existing == null) {
        merged[key] = connector;
      } else {
        final remoteWins =
            connector.updatedAt > existing.updatedAt ||
            (connector.updatedAt == existing.updatedAt && preferRemote);
        merged[key] = remoteWins
            ? connector.copyWith(
                targets: _mergeConnectorTargets(
                  existing.targets,
                  connector.targets,
                  preferRemote: true,
                ),
              )
            : existing.copyWith(
                targets: _mergeConnectorTargets(
                  existing.targets,
                  connector.targets,
                  preferRemote: false,
                ),
              );
      }
    }
    return merged.values.toList();
  }

  List<ConnectorTarget> _mergeConnectorTargets(
    List<ConnectorTarget> local,
    List<ConnectorTarget> remote, {
    required bool preferRemote,
  }) {
    final merged = <String, ConnectorTarget>{
      for (final target in local) _connectorTargetMergeKey(target): target,
    };
    for (final target in remote) {
      final key = _connectorTargetMergeKey(target);
      final existing = merged[key];
      if (existing == null) {
        merged[key] = target;
      } else {
        final remoteWins =
            target.updatedAt > existing.updatedAt ||
            (target.updatedAt == existing.updatedAt && preferRemote);
        merged[key] = remoteWins ? target : existing;
      }
    }
    return merged.values.toList();
  }

  String _agentConnectorMergeKey(AgentConnector connector) {
    if (connector.id.trim().isNotEmpty) return 'id:${connector.id.trim()}';
    final name = connector.name.trim().toLowerCase();
    final url = connector.baseUrl.trim().toLowerCase();
    return 'agent:$name|$url';
  }

  String _connectorTargetMergeKey(ConnectorTarget target) {
    if (target.id.trim().isNotEmpty) return 'id:${target.id.trim()}';
    return 'target:${target.connectorId}|${target.modelId}';
  }

  Future<void> authenticate(
    String username,
    String password, {
    required bool signUp,
  }) async {
    syncStatus = signUp ? 'Creating account...' : 'Signing in...';
    notifyListeners();
    final result = signUp
        ? await _sync.signUp(
            username,
            password,
            syncSettings.copyWith(enabled: true),
          )
        : await _sync.login(
            username,
            password,
            syncSettings.copyWith(enabled: true),
          );
    final nextSync = syncSettings.copyWith(enabled: true);
    if (!signUp &&
        result.remoteState != null &&
        _hasRemoteData(result.remoteState!)) {
      _applyState(
        PersistedAppState.fromJson({
          ...result.remoteState!.toJson(includeSecrets: true),
          'currentUser': result.user.toJson(),
          'authToken': result.token,
          'syncSettings': nextSync.toJson(),
        }),
        notify: false,
      );
    } else {
      _resetForAccount(result.user, result.token, nextSync);
    }
    syncStatus = signUp
        ? 'Account created. Starting with a fresh workspace.'
        : 'Signed in. Sync is enabled.';
    notifyListeners();
    await _persist();
  }

  void continueAsGuest() {
    final guest = UserAccount(
      id: 'guest-${DateTime.now().millisecondsSinceEpoch}',
      username: 'guest',
      displayName: 'Guest',
      isGuest: true,
    );
    currentUser = guest;
    authToken = '';
    userName = 'Guest';
    syncSettings = syncSettings.copyWith(enabled: false);
    syncStatus = 'Guest mode. Local sessions are saved on this device.';
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> saveGuestSession(String username, String password) async {
    if (currentUser?.isGuest != true) return;
    syncStatus = 'Creating account and saving guest session...';
    notifyListeners();
    final result = await _sync.signUp(
      username,
      password,
      syncSettings.copyWith(enabled: true),
    );
    currentUser = result.user;
    authToken = result.token;
    userName = result.user.label;
    syncSettings = syncSettings.copyWith(enabled: true);
    await _sync.pushRemoteState(buildState());
    lastSyncAt = DateTime.now().millisecondsSinceEpoch;
    syncStatus = 'Guest session saved and synced to database.';
    notifyListeners();
    await _persist();
  }

  void _resetForAccount(UserAccount user, String token, SyncSettings nextSync) {
    final session = Session.empty('1', 'model:gemini-2.5-flash');
    currentUser = user;
    authToken = token;
    userName = user.label;
    syncSettings = nextSync;
    geminiApiKey = '';
    endpoints = const [
      EndpointConfig(
        id: '1',
        name: 'OpenAI',
        url: 'https://api.openai.com/v1',
        key: '',
      ),
    ];
    genSettings = const GenerationSettings();
    voiceSettings = const VoiceSettings();
    sessions = [session];
    currentSessionId = session.id;
    memories = const [];
    tokenUsageData = const [];
    customCounters = const [];
    selectedModel = 'gemini-2.5-flash';
    selectedTargetId = 'model:gemini-2.5-flash';
    agentConnectors = const [];
    modelContextOverrides = const {};
    isThinkingMode = false;
    isArtifactMode = false;
    lastSyncAt = null;
  }

  bool _hasRemoteData(PersistedAppState state) {
    return state.sessions.isNotEmpty ||
        state.memories.isNotEmpty ||
        state.geminiApiKey.isNotEmpty ||
        state.endpoints.isNotEmpty ||
        state.tokenUsageData.isNotEmpty;
  }

  Future<void> signOut() async {
    currentUser = null;
    authToken = '';
    userName = 'User';
    currentView = AppView.chat;
    syncStatus = '';
    notifyListeners();
    await _storage.clearAuth();
    await _persist();
  }

  void setView(AppView view) {
    currentView = view;
    notifyListeners();
  }

  bool handleSystemBack() {
    if (currentView != AppView.chat) {
      currentView = AppView.chat;
      notifyListeners();
      return true;
    }
    return false;
  }

  void toggleTheme() {
    unawaited(HapticFeedback.lightImpact());
    theme = isDark ? 'light' : 'dark';
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setVisualTheme(String value) {
    final normalized = switch (value.trim().toLowerCase()) {
      'liquid-glass' || 'liquidglass' || 'glass' => 'liquid-glass',
      'aurora-neon' || 'auroraneon' || 'aurora' || 'neon' => 'aurora-neon',
      'modern-minimal' || 'modernminimal' || 'minimal' => 'modern-minimal',
      'ios26' || 'vision' => 'ios26',
      'midnight-bloom' ||
      'midnightbloom' ||
      'midnight' ||
      'bloom' => 'midnight-bloom',
      _ => 'default',
    };
    if (visualTheme == normalized) return;
    unawaited(HapticFeedback.lightImpact());
    visualTheme = normalized;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void toggleThinkingMode() {
    isThinkingMode = !isThinkingMode;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void toggleArtifactMode() {
    isArtifactMode = !isArtifactMode;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setArtifactMode(bool enabled) {
    if (isArtifactMode == enabled) return;
    isArtifactMode = enabled;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setSoundEffectsEnabled(bool enabled) {
    if (soundEffectsEnabled == enabled) return;
    soundEffectsEnabled = enabled;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setSelectedModel(String model) {
    final trimmed = model.trim().isEmpty ? 'gemini-2.5-flash' : model.trim();
    applyChatTarget(
      ChatTarget.model(trimmed, provider: _modelProviderLabel(trimmed)),
      insertDivider: false,
    );
  }

  bool requiresTargetSwitchConfirmation(ChatTarget target) {
    final current = activeChatTarget;
    if (current.id == target.id) return false;
    return current.type != ChatTargetType.model ||
        target.type != ChatTargetType.model;
  }

  void applyChatTarget(
    ChatTarget target, {
    bool fork = false,
    bool insertDivider = true,
  }) {
    final previous = activeChatTarget;
    if (previous.id == target.id) return;

    if (target.isModel) {
      selectedModel = target.modelId ?? target.displayName;
    }
    selectedTargetId = target.id;
    currentView = AppView.chat;

    final now = DateTime.now();
    final session = currentSession;
    final shouldInsertDivider =
        insertDivider &&
        session.messages.isNotEmpty &&
        (previous.type != ChatTargetType.model ||
            target.type != ChatTargetType.model);
    final handoff = _buildHandoffSummary(session, previous, target);
    final targetHistory = _appendTargetHistory(
      session.targetHistory,
      target.id,
    );
    final startedTarget = session.startedWithTargetId.isEmpty
        ? previous.id
        : session.startedWithTargetId;

    if (fork) {
      final forked = Session.empty(null, target.id).copyWith(
        title: '${session.title} (Branch)',
        messages: session.messages,
        createdAt: now.millisecondsSinceEpoch,
        updatedAt: now.millisecondsSinceEpoch,
        currentTargetId: target.id,
        startedWithTargetId: target.id,
        lastTargetId: target.id,
        targetHistory: targetHistory,
        handoffSummary: handoff,
      );
      sessions = [forked, ...sessions];
      currentSessionId = forked.id;
      notifyListeners();
      unawaited(_persistAndScheduleRemote());
      return;
    }

    final switchEvent = TargetSwitchEvent(
      id: 'switch-${now.microsecondsSinceEpoch}',
      chatId: session.id,
      fromTargetId: previous.id,
      toTargetId: target.id,
      handoffSummary: handoff,
      createdAt: now.millisecondsSinceEpoch,
    );
    final messages = [
      ...session.messages,
      if (shouldInsertDivider)
        Message(
          id: 'switch-${now.microsecondsSinceEpoch}',
          text:
              'Switched from ${formatTargetName(previous.displayName)} to ${formatTargetName(target.displayName)}',
          sender: 'system',
          timestamp: DateFormat('hh:mm a').format(now),
          targetId: target.id,
          targetType: target.type,
          targetName: target.displayName,
          connectorId: target.connectorId,
          modelOrAgentId: target.modelId,
        ),
    ];

    _replaceSession(
      session.id,
      session.copyWith(
        messages: messages,
        currentTargetId: target.id,
        startedWithTargetId: startedTarget,
        lastTargetId: target.id,
        targetHistory: targetHistory,
        handoffSummary: handoff,
        targetSwitchEvents: [...session.targetSwitchEvents, switchEvent],
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void createSessionForTarget(ChatTarget target) {
    if (target.isModel) {
      selectedModel = target.modelId ?? target.displayName;
    }
    selectedTargetId = target.id;

    if (currentSession.messages.isEmpty) {
      if (currentSession.currentTargetId != target.id) {
        sessions = sessions.map((s) {
          if (s.id == currentSessionId) {
            return s.copyWith(
              currentTargetId: target.id,
              startedWithTargetId: target.id,
              lastTargetId: target.id,
            );
          }
          return s;
        }).toList();
        unawaited(_persistAndScheduleRemote());
      }
      currentView = AppView.chat;
      notifyListeners();
      return;
    }

    final session = Session.empty(null, target.id);
    sessions = [session, ...sessions];
    currentSessionId = session.id;
    currentView = AppView.chat;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void startChatWithConnector(String connectorId) {
    final connector = agentConnectors
        .where((item) => item.id == connectorId)
        .firstOrNull;
    if (connector == null) return;
    createSessionForTarget(ChatTarget.agent(connector: connector));
  }

  void upsertAgentConnector(AgentConnector connector) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = connector.copyWith(updatedAt: now);
    final exists = agentConnectors.any((item) => item.id == connector.id);
    agentConnectors = exists
        ? agentConnectors
              .map((item) => item.id == connector.id ? next : item)
              .toList()
        : [next, ...agentConnectors];
    if (next.isDefault) {
      agentConnectors = agentConnectors
          .map(
            (item) =>
                item.id == next.id ? item : item.copyWith(isDefault: false),
          )
          .toList();
    }
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void deleteAgentConnector(String id) {
    agentConnectors = agentConnectors.where((item) => item.id != id).toList();
    if (selectedTargetId == 'agent:$id') {
      selectedTargetId = 'model:$selectedModel';
    }
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setConnectorEnabled(String id, bool enabled) {
    agentConnectors = agentConnectors
        .map(
          (item) => item.id == id
              ? item.copyWith(
                  enabled: enabled,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                )
              : item,
        )
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setDefaultConnector(String id) {
    agentConnectors = agentConnectors
        .map((item) => item.copyWith(isDefault: item.id == id))
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  Future<void> testAgentConnector(String id) async {
    final connector = agentConnectors
        .where((item) => item.id == id)
        .firstOrNull;
    if (connector == null) return;
    final started = DateTime.now();
    _updateConnector(
      id,
      connector.copyWith(
        status: ConnectorStatus.unknown,
        lastError: 'Testing connection...',
        updatedAt: started.millisecondsSinceEpoch,
      ),
    );
    try {
      try {
        await _ai
            .fetchAvailableModelsForEndpoint(
              endpoint: _endpointForConnector(connector),
              syncSettings: syncSettings,
            )
            .timeout(const Duration(seconds: 12));
      } catch (e) {
        // Fallback for servers like Hermes that return 500/404 for /models
        if (e.toString().contains('500') || e.toString().contains('404')) {
          await _ai
              .pingEndpoint(
                endpoint: _endpointForConnector(connector),
                syncSettings: syncSettings,
              )
              .timeout(const Duration(seconds: 12));
        } else {
          rethrow;
        }
      }
      final latency = DateTime.now().difference(started).inMilliseconds;
      _updateConnector(
        id,
        connector.copyWith(
          status: ConnectorStatus.online,
          latencyMs: latency,
          lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
          lastError: '',
          logs: _appendConnectorLog(
            connector.logs,
            'Connection OK (${latency}ms)',
          ),
        ),
      );
    } catch (error) {
      final status = _connectorStatusForError(error);
      _updateConnector(
        id,
        connector.copyWith(
          status: status,
          latencyMs: null,
          lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
          lastError: error.toString().replaceFirst('Exception: ', ''),
          logs: _appendConnectorLog(
            connector.logs,
            'Connection failed: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
          clearLatency: true,
        ),
      );
    }
  }

  Future<void> syncAgentConnectorTargets(String id) async {
    final connector = agentConnectors
        .where((item) => item.id == id)
        .firstOrNull;
    if (connector == null) return;
    try {
      List<Map<String, dynamic>> modelsData = [];
      try {
        modelsData = await _ai
            .fetchAvailableModelsForEndpoint(
              endpoint: _endpointForConnector(connector),
              syncSettings: syncSettings,
            )
            .timeout(const Duration(seconds: 16));
      } catch (e) {
        if (e.toString().contains('500') || e.toString().contains('404')) {
          await _ai
              .pingEndpoint(
                endpoint: _endpointForConnector(connector),
                syncSettings: syncSettings,
              )
              .timeout(const Duration(seconds: 16));
          // If ping succeeds, use existing targets or default to agent name
          modelsData = connector.targets.isNotEmpty
              ? connector.targets
                    .map(
                      (t) => {
                        'id': t.modelId,
                        'context_length': t.contextLength,
                      },
                    )
                    .toList()
              : [
                  {'id': connector.name.toLowerCase().replaceAll(' ', '-')},
                ];
        } else {
          rethrow;
        }
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final targets = modelsData
          .where((m) => (m['id'] as String).trim().isNotEmpty)
          .map((m) {
            final name = m['id'] as String;
            return ConnectorTarget(
              id: '${connector.id}:$name',
              connectorId: connector.id,
              modelId: name,
              displayName: name,
              contextLength: m['context_length'] as int?,
              createdAt: now,
              updatedAt: now,
            );
          })
          .toList();
      _updateConnector(
        id,
        connector.copyWith(
          targets: targets,
          status: ConnectorStatus.online,
          lastCheckedAt: now,
          lastError: '',
          logs: _appendConnectorLog(
            connector.logs,
            'Synced ${targets.length} target(s).',
          ),
        ),
      );
    } catch (error) {
      _updateConnector(
        id,
        connector.copyWith(
          status: ConnectorStatus.syncFailed,
          lastCheckedAt: DateTime.now().millisecondsSinceEpoch,
          lastError: error.toString().replaceFirst('Exception: ', ''),
          logs: _appendConnectorLog(
            connector.logs,
            'Target sync failed: ${error.toString().replaceFirst('Exception: ', '')}',
          ),
        ),
      );
    }
  }

  List<String> _appendTargetHistory(List<String> history, String targetId) {
    if (targetId.isEmpty) return history;
    final next = [...history.where((item) => item.isNotEmpty)];
    if (next.isEmpty || next.last != targetId) next.add(targetId);
    return next.length > 24 ? next.sublist(next.length - 24) : next;
  }

  List<String> _appendConnectorLog(List<String> logs, String entry) {
    final time = DateFormat('HH:mm:ss').format(DateTime.now());
    final next = ['$time $entry', ...logs];
    return next.take(40).toList();
  }

  void _updateConnector(String id, AgentConnector next) {
    agentConnectors = agentConnectors
        .map((item) => item.id == id ? next : item)
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  EndpointConfig _endpointForConnector(AgentConnector connector) {
    return EndpointConfig(
      id: 'connector-${connector.id}',
      url: connector.baseUrl,
      key: connector.encryptedApiKey,
      name: connector.name,
      skipModelFetch: !connector.capabilities.supportsModelsEndpoint,
      models: connector.targets.map((target) => target.modelId).toList(),
    );
  }

  ConnectorStatus _connectorStatusForError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('key') ||
        text.contains('auth') ||
        text.contains('401') ||
        text.contains('403')) {
      return ConnectorStatus.authFailed;
    }
    if (text.contains('timeout')) return ConnectorStatus.timeout;
    return ConnectorStatus.offline;
  }

  String _buildHandoffSummary(
    Session session,
    ChatTarget previous,
    ChatTarget target,
  ) {
    if (session.messages.isEmpty) return '';
    final recent = session.messages
        .where((message) => !message.isSystem && message.text.trim().isNotEmpty)
        .toList()
        .reversed
        .take(6)
        .toList()
        .reversed;
    final summary = recent
        .map((message) {
          final role = message.isUser ? 'User' : 'Assistant';
          final text = message.text.replaceAll(RegExp(r'\s+'), ' ').trim();
          return '$role: ${text.length > 220 ? '${text.substring(0, 220)}...' : text}';
        })
        .join('\n');
    return [
      'Previous target: ${previous.displayName}',
      'Next target: ${target.displayName}',
      if (summary.isNotEmpty) 'Recent conversation:\n$summary',
    ].join('\n');
  }

  void createSession() {
    String targetId = activeChatTarget.id;
    if (targetId.startsWith('agent:')) {
      targetId = 'model:$selectedModel';
      selectedTargetId = targetId;
    }

    if (currentSession.messages.isEmpty) {
      if (currentSession.currentTargetId != targetId) {
        sessions = sessions.map((s) {
          if (s.id == currentSessionId) {
            return s.copyWith(
              currentTargetId: targetId,
              startedWithTargetId: targetId,
              lastTargetId: targetId,
            );
          }
          return s;
        }).toList();
        unawaited(_persistAndScheduleRemote());
      }
      currentView = AppView.chat;
      notifyListeners();
      return;
    }

    final session = Session.empty(null, targetId);
    sessions = [session, ...sessions];
    currentSessionId = session.id;
    currentView = AppView.chat;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void headerChatShortcut() {
    createSession();
  }

  void selectSession(String id) {
    currentSessionId = id;
    final session = sessions.where((item) => item.id == id).firstOrNull;
    final targetId = session?.lastTargetId.isNotEmpty == true
        ? session!.lastTargetId
        : session?.currentTargetId;
    if (targetId != null && targetId.isNotEmpty) {
      selectedTargetId = targetId;
      if (targetId.startsWith('model:')) {
        selectedModel = targetId.substring(6);
      }
    }
    currentView = AppView.chat;
    notifyListeners();
    unawaited(_persist(touchSavedAt: false));
  }

  void deleteSession(String id) {
    final now = DateTime.now().millisecondsSinceEpoch;
    sessions = sessions
        .map(
          (session) => session.id == id
              ? session.copyWith(deleted: true, updatedAt: now)
              : session,
        )
        .toList();
    if (activeSessions.isEmpty) {
      final session = Session.empty(null, activeChatTarget.id);
      sessions = [...sessions, session];
      currentSessionId = session.id;
    } else if (id == currentSessionId) {
      currentSessionId = activeSessions.first.id;
    }
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void pinSession(String id) {
    sessions = sessions
        .map(
          (session) => session.id == id
              ? session.copyWith(
                  pinned: !session.pinned,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                )
              : session,
        )
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void renameSession(String id, String title) {
    final cleaned = title.trim().isEmpty ? 'New Session' : title.trim();
    sessions = sessions
        .map(
          (session) => session.id == id
              ? session.copyWith(
                  title: cleaned,
                  updatedAt: DateTime.now().millisecondsSinceEpoch,
                )
              : session,
        )
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void clearAllSessions() {
    final now = DateTime.now().millisecondsSinceEpoch;
    sessions = sessions.map((item) {
      if (!item.currentTargetId.startsWith('agent:')) {
        return item.copyWith(deleted: true, updatedAt: now);
      }
      return item;
    }).toList();

    // If we just deleted the current session, switch to a valid one
    final active = activeSessions;
    if (active.isEmpty) {
      final session = Session.empty(null, 'model:$selectedModel');
      sessions = [...sessions, session];
      currentSessionId = session.id;
    } else if (sessions.firstWhere((s) => s.id == currentSessionId).deleted) {
      currentSessionId = active.first.id;
    }

    currentView = AppView.chat;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void clearAgentSessions(String connectorId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    sessions = sessions.map((item) {
      if (item.currentTargetId == 'agent:$connectorId') {
        return item.copyWith(deleted: true, updatedAt: now);
      }
      return item;
    }).toList();

    // If we just deleted the current session, switch to a valid one
    final active = activeSessions;
    if (active.isEmpty) {
      final session = Session.empty(null, 'model:$selectedModel');
      sessions = [...sessions, session];
      currentSessionId = session.id;
    } else if (sessions.firstWhere((s) => s.id == currentSessionId).deleted) {
      currentSessionId = active.first.id;
    }

    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateMemory(String id, String content) {
    memories = memories
        .map(
          (memory) =>
              memory.id == id ? memory.copyWith(content: content) : memory,
        )
        .toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void deleteMemory(String id) {
    memories = memories.where((memory) => memory.id != id).toList();
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  Memory? saveMemory(
    String content, {
    String key = '',
    String type = 'preference',
    String scope = 'global',
    String sensitivity = 'low',
  }) {
    final clean = content.trim();
    if (clean.isEmpty || _isDuplicateMemory(clean)) return null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final memory = Memory(
      id: now.toString(),
      content: clean,
      timestamp: now,
      key: key.isEmpty ? Memory.inferKey(clean) : key,
      type: type,
      scope: scope,
      sensitivity: sensitivity,
    );
    memories = [memory, ...memories];
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
    return memory;
  }

  Future<void> sendMessage(
    String prompt,
    List<AttachmentData> attachments,
  ) async {
    if (isGenerating || (prompt.trim().isEmpty && attachments.isEmpty)) return;
    unawaited(HapticFeedback.lightImpact());
    unawaited(_playSound('send_user_message.wav'));
    unawaited(_playSound('loading_ai_response.wav'));

    _cancelStreamFlush(resetText: true);
    _generationStopRequested = false;
    Timer? loadingAudioTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) {
      if (!isGenerating || _generationStopRequested) {
        timer.cancel();
      } else {
        unawaited(_playSound('loading_ai_response.wav'));
      }
    });

    final session = currentSession;
    final target = activeChatTarget;
    final request = _requestConfigForTarget(target);
    final requestPrompt = _promptWithTargetContext(
      prompt.trim(),
      session,
      target,
    );
    final now = DateTime.now();
    final userMessage = Message(
      id: now.millisecondsSinceEpoch.toString(),
      text: prompt.trim(),
      sender: 'user',
      timestamp: DateFormat('hh:mm a').format(now),
      attachments: attachments,
      tokenCount: countTokens(prompt),
    );
    final history = _historyForRequest(session);
    final botId = (now.millisecondsSinceEpoch + 1).toString();
    final modelForRequest = request.model;
    final generationId = '${now.microsecondsSinceEpoch}-$botId';
    final botMessage = Message(
      id: botId,
      text: '',
      sender: 'bot',
      timestamp: DateFormat('hh:mm a').format(now),
      model: modelForRequest,
      targetId: target.id,
      targetType: target.type,
      targetName: target.displayName,
      connectorId: target.connectorId,
      modelOrAgentId: target.modelId,
    );
    final isFirstMessage = history.isEmpty;
    final fallbackTitle = cleanTitle(
      prompt.split(RegExp(r'\s+')).take(4).join(' '),
    );
    final nextSession = session.copyWith(
      title: isFirstMessage && fallbackTitle.isNotEmpty
          ? fallbackTitle
          : session.title,
      messages: [...session.messages, userMessage, botMessage],
      currentTargetId: target.id,
      startedWithTargetId: session.startedWithTargetId.isEmpty
          ? target.id
          : session.startedWithTargetId,
      lastTargetId: target.id,
      targetHistory: _appendTargetHistory(session.targetHistory, target.id),
      updatedAt: now.millisecondsSinceEpoch,
    );
    _replaceSession(session.id, nextSession);
    isGenerating = true;
    _activeGenerationId = generationId;
    _activeStreamSessionId = session.id;
    _activeStreamBotId = botId;
    syncStatus = '';
    _maybeSaveUserMemory(prompt);
    notifyListeners();

    try {
      if (request.configurationError != null) {
        throw Exception(request.configurationError);
      }
      final response = await _ai.sendMessage(
        prompt: requestPrompt,
        attachments: attachments,
        history: history,
        selectedModel: modelForRequest,
        endpoints: request.endpoints,
        endpointModels: request.endpointModels,
        contextLimit: request.contextWindow,
        genSettings: genSettings,
        voiceSettings: voiceSettings,
        geminiApiKey: geminiApiKey,
        memories: genSettings.memoryEnabled ? memories : const [],
        thinkingMode: isThinkingMode,
        artifactMode: isArtifactMode,
        syncSettings: syncSettings,
        onStatus: (status) {
          _queueStreamText(generationId, session.id, botId, status);
        },
        onText: (text) {
          if (loadingAudioTimer != null) {
            loadingAudioTimer?.cancel();
            loadingAudioTimer = null;
          }
          _queueStreamText(generationId, session.id, botId, text);
        },
      );

      if (_activeGenerationId != generationId || _generationStopRequested) {
        return;
      }
      _queueStreamText(generationId, session.id, botId, response.text);
      _flushStreamText(generationId, session.id, botId, force: true);
      _updateBotMessage(
        session.id,
        botId,
        response.text,
        tokenCount: response.outputTokens,
      );
      tokenUsageData = [
        ...tokenUsageData,
        TokenUsageRecord(
          timestamp: DateTime.now().millisecondsSinceEpoch,
          model: modelForRequest,
          endpoint: response.endpointName,
          inputTokens: response.inputTokens,
          outputTokens: response.outputTokens,
          totalTokens: response.inputTokens + response.outputTokens,
          cachedInputTokens: response.cachedInputTokens,
          cacheCreationInputTokens: response.cacheCreationInputTokens,
        ),
      ];

      if (isFirstMessage && !_generationStopRequested) {
        unawaited(
          _generateSessionTitle(
            sessionId: session.id,
            model: genSettings.titleModelEnabled && genSettings.titleModel.trim().isNotEmpty
                ? genSettings.titleModel.trim()
                : (target.isModel ? modelForRequest : selectedModel),
          ),
        );
      }
    } catch (error) {
      if (_activeGenerationId != generationId || _generationStopRequested) {
        return;
      }
      _updateBotMessage(
        session.id,
        botId,
        'Error: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      loadingAudioTimer?.cancel();
      loadingAudioTimer = null;
      if (_activeGenerationId == generationId || !isGenerating) {
        _cancelStreamFlush(resetText: true);
        _activeGenerationId = null;
        _activeStreamSessionId = null;
        _activeStreamBotId = null;
        _generationStopRequested = false;
        isGenerating = false;
        notifyListeners();
        await _persistAndScheduleRemote();
      }
    }
  }

  void stopGeneration() {
    final generationId = _activeGenerationId;
    final sessionId = _activeStreamSessionId;
    final botId = _activeStreamBotId;
    if (generationId != null && sessionId != null && botId != null) {
      _flushStreamText(generationId, sessionId, botId, force: true);
    }
    _generationStopRequested = true;
    _activeGenerationId = null;
    _activeStreamSessionId = null;
    _activeStreamBotId = null;
    _cancelStreamFlush(resetText: true);
    _ai.cancelActiveRequests();
    isGenerating = false;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  Future<void> startLiveConversation() async {
    if (isLiveActive || isLiveConnecting) return;

    if (!kIsWeb) {
      final micStatus = await Permission.microphone.request();
      if (micStatus != PermissionStatus.granted) {
        syncStatus = 'Microphone permission is required for Live Mode.';
        notifyListeners();
        return;
      }
    }

    unawaited(_playSound('start_voice_mode.wav'));

    final liveModels = _liveModelCandidates();
    isLiveActive = true;
    isLiveConnecting = true;
    isLiveRecording = false;
    liveInputLevel = 0;
    liveStatus = 'Connecting to Gemini Live...';
    syncStatus = '';
    notifyListeners();

    try {
      await _startLiveForegroundService();
    } catch (error) {
      syncStatus =
          'Live background notification unavailable: ${error.toString().replaceFirst('Exception: ', '')}';
      notifyListeners();
    }

    Object? lastError;
    for (final liveModel in liveModels) {
      late GeminiLiveService service;
      service = GeminiLiveService(
        apiKey: geminiApiKey,
        model: liveModel,
        voiceSettings: voiceSettings,
        history: currentSession.messages,
        memories: genSettings.memoryEnabled ? memories : const [],
        thinkingMode: isThinkingMode,
        userName: userName,
        onStatus: (status) {
          if (_liveService != service) return;
          liveStatus = status;
          if (status.contains('Connected') || status.contains('Listening')) {
            isLiveConnecting = false;
          }
          notifyListeners();
        },
        onInputTranscript: (text, finished) {
          if (_liveService != service) return;
          _appendLiveTranscript(
            text: text,
            sender: 'user',
            model: liveModel,
            finished: finished,
          );
        },
        onOutputTranscript: (text, finished) {
          if (_liveService != service) return;
          _pulseLiveOutput();
          _appendLiveTranscript(
            text: text,
            sender: 'bot',
            model: liveModel,
            finished: finished,
          );
        },
        onLevel: (level) {
          if (_liveService != service) return;
          _setLiveInputLevel(level);
        },
        onOutputLevel: (level) {
          if (_liveService != service) return;
          _setLiveOutputLevel(level);
        },
        onRecordingChanged: (value) {
          if (_liveService != service) return;
          isLiveRecording = value;
          notifyListeners();
        },
        onTurnComplete: () {
          if (_liveService != service) return;
          _liveUserMessageId = null;
          _liveBotMessageId = null;
          unawaited(_persistAndScheduleRemote());
        },
        onError: (error) {
          if (_liveService != service) return;
          lastError = error;
          liveStatus = _cleanLiveError(error);
          _appendLiveTranscript(
            text: '❌ Live Error: $liveStatus',
            sender: 'bot',
            model: liveModel,
            finished: true,
          );
          notifyListeners();
        },
        onClosed: () {
          if (_liveService != service) return;
          _clearLiveState();
          _liveService = null;
          unawaited(LiveForegroundService.stop());
          notifyListeners();
        },
      );
      _liveService = service;
      liveStatus = 'Connecting to Gemini Live ($liveModel)...';
      notifyListeners();

      try {
        await service.start();
        if (_liveService == service) {
          isLiveConnecting = false;
          isLiveActive = true;
          notifyListeners();
        }
        return;
      } catch (error) {
        lastError = error;
        if (_liveService == service) {
          _liveService = null;
        }
        await service.dispose();
        isLiveActive = true;
        isLiveConnecting = true;
        isLiveRecording = false;
        liveInputLevel = 0;
      }
    }

    final message = _cleanLiveError(lastError ?? 'No Live model connected.');
    syncStatus = message;
    liveStatus = message;
    _clearLiveState(clearStatus: false);
    _liveService = null;
    unawaited(LiveForegroundService.stop());
    notifyListeners();
  }

  Future<void> stopLiveConversation() async {
    unawaited(_playSound('end_voice_mode.wav'));
    final service = _liveService;
    _liveService = null;
    _clearLiveState();
    notifyListeners();
    await service?.dispose();
    await LiveForegroundService.stop();
    await _persistAndScheduleRemote();
  }

  Future<void> toggleLiveRecording() async {
    if (!isLiveActive && !isLiveConnecting) {
      await startLiveConversation();
      return;
    }
    try {
      await _liveService?.toggleRecording();
    } catch (error) {
      final message = _cleanLiveError(error);
      liveStatus = message;
      syncStatus = message;
      notifyListeners();
    }
  }

  void toggleLiveVideo() {
    if (!isLiveActive && !isLiveConnecting) return;
    isLiveVideoEnabled = !isLiveVideoEnabled;
    notifyListeners();
  }

  void toggleLiveCameraFacing() {
    isLiveFrontCamera = !isLiveFrontCamera;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void sendLiveVideoFrame(Uint8List bytes, {String mimeType = 'image/jpeg'}) {
    _liveService?.sendVideoFrame(bytes, mimeType: mimeType);
  }

  void deleteMessage(String messageId) {
    final session = currentSession;
    final index = session.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index == -1) return;
    final messages = [...session.messages];
    if (messages[index].isUser &&
        index + 1 < messages.length &&
        !messages[index + 1].isUser) {
      messages.removeRange(index, index + 2);
    } else {
      messages.removeAt(index);
    }
    _replaceSession(
      session.id,
      session.copyWith(
        messages: messages,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void editMessage(String messageId, String text) {
    final session = currentSession;
    final index = session.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index == -1) return;
    unawaited(HapticFeedback.lightImpact());
    final messages = [...session.messages];
    final attachments = messages[index].attachments;
    final trimmed = messages.sublist(0, index);

    final newSession = Session.empty(null, activeChatTarget.id);
    final forkedSession = newSession.copyWith(
      title: '${session.title} (Branch)',
      messages: trimmed,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

    sessions = [forkedSession, ...sessions];
    currentSessionId = forkedSession.id;
    notifyListeners();
    unawaited(sendMessage(text, attachments));
  }

  void regenerateLast() {
    final session = currentSession;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].isUser) {
        unawaited(HapticFeedback.lightImpact());
        final user = session.messages[i];
        final trimmed = session.messages.sublist(0, i);

        final newSession = Session.empty(null, activeChatTarget.id);
        final forkedSession = newSession.copyWith(
          title: '${session.title} (Branch)',
          messages: trimmed,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        sessions = [forkedSession, ...sessions];
        currentSessionId = forkedSession.id;
        notifyListeners();
        unawaited(sendMessage(user.text, user.attachments));
        return;
      }
    }
  }

  String formatTargetName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return 'Chat Target';
    if (clean.toLowerCase() == 'gemini-2.5-flash') return 'Gemini 2.5 Flash';
    return clean
        .split(RegExp(r'[-_]'))
        .where((part) => part.isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          if (lower == 'gpt') return 'GPT';
          if (lower == 'ai') return 'AI';
          if (lower == 'api') return 'API';
          if (lower.length <= 2 && RegExp(r'^\d+$').hasMatch(lower)) {
            return part;
          }
          return part.substring(0, 1).toUpperCase() + part.substring(1);
        })
        .join(' ');
  }

  String contextWindowKeyForTarget(ChatTarget target) {
    if (target.isAgentServer && target.connectorId != null) {
      return 'agent:${target.connectorId}:${target.modelId ?? target.displayName}';
    }
    return 'model:${target.modelId ?? target.displayName}';
  }

  int? contextWindowOverrideForTarget(ChatTarget target) {
    return modelContextOverrides[contextWindowKeyForTarget(target)] ??
        modelContextOverrides[target.id] ??
        (target.modelId == null
            ? null
            : modelContextOverrides['model:${target.modelId}']);
  }

  int contextWindowForTarget(ChatTarget target) {
    return contextWindowOverrideForTarget(target) ??
        target.contextLength ??
        contextWindow(target.modelId ?? selectedModel);
  }

  String contextWindowSourceForTarget(ChatTarget target) {
    if (contextWindowOverrideForTarget(target) != null) return 'Custom';
    if (target.contextLength != null) return 'Verified from API';
    return 'Estimated context length';
  }

  void updateContextWindowOverride(ChatTarget target, int? tokens) {
    final key = contextWindowKeyForTarget(target);
    final next = Map<String, int>.from(modelContextOverrides);
    if (tokens == null || tokens <= 0) {
      next.remove(key);
    } else {
      next[key] = tokens.clamp(1024, 8000000).toInt();
    }
    modelContextOverrides = next;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  String _modelProviderLabel(String model) {
    final endpointModel = endpointModels
        .where((item) => item.name == model)
        .firstOrNull;
    if (endpointModel != null) {
      final endpoint = endpoints
          .where((item) => item.id == endpointModel.endpointId)
          .firstOrNull;
      return endpoint?.name.trim().isNotEmpty == true
          ? endpoint!.name
          : 'Endpoint';
    }
    return model.toLowerCase().startsWith('gemini') ? 'Gemini' : 'Model';
  }

  _TargetRequestConfig _requestConfigForTarget(ChatTarget target) {
    if (target.isModel) {
      final model = target.modelId?.trim().isNotEmpty == true
          ? target.modelId!.trim()
          : selectedModel;
      return _TargetRequestConfig(
        model: model,
        endpoints: endpoints,
        endpointModels: endpointModels,
        contextWindow: contextWindowForTarget(target),
      );
    }

    final connector = agentConnectors
        .where((item) => item.id == target.connectorId)
        .firstOrNull;
    if (connector == null) {
      return _TargetRequestConfig(
        model: target.modelId ?? target.displayName,
        endpoints: endpoints,
        endpointModels: endpointModels,
        contextWindow: contextWindowForTarget(target),
        configurationError: 'Agent server is no longer configured.',
      );
    }
    if (!connector.enabled) {
      return _TargetRequestConfig(
        model: target.modelId ?? connector.name,
        endpoints: endpoints,
        endpointModels: endpointModels,
        contextWindow: contextWindowForTarget(target),
        configurationError: '${connector.name} is disabled.',
      );
    }
    if (connector.baseUrl.trim().isEmpty) {
      return _TargetRequestConfig(
        model: target.modelId ?? connector.name,
        endpoints: endpoints,
        endpointModels: endpointModels,
        contextWindow: contextWindowForTarget(target),
        configurationError: '${connector.name} has no Base URL configured.',
      );
    }
    final endpoint = _endpointForConnector(connector);
    final model = target.modelId?.trim().isNotEmpty == true
        ? target.modelId!.trim()
        : (connector.targets.isNotEmpty
              ? connector.targets.first.modelId
              : connector.name.toLowerCase().replaceAll(' ', '-'));
    return _TargetRequestConfig(
      model: model,
      endpoints: [...endpoints, endpoint],
      endpointModels: [
        ...endpointModels,
        EndpointModel(name: model, endpointId: endpoint.id),
      ],
      contextWindow: contextWindowForTarget(target),
    );
  }

  String _promptWithTargetContext(
    String prompt,
    Session session,
    ChatTarget target,
  ) {
    final handoff = session.handoffSummary.trim();
    if (handoff.isEmpty || target.isAgentServer) return prompt;
    return '[Target handoff summary]\n$handoff\n[End handoff summary]\n\n$prompt';
  }

  List<Message> _historyForRequest(Session session) {
    return session.messages
        .where((message) => !message.isSystem)
        .toList(growable: false);
  }

  void updateProfile({String? name, AppLanguage? nextLanguage}) {
    userName = name ?? userName;
    language = nextLanguage ?? language;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateGeminiKey(String value) {
    geminiApiKey = value;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateEndpoints(List<EndpointConfig> value) {
    endpoints = value;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateGenerationSettings(GenerationSettings value) {
    genSettings = value;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateMemoryEnabled(bool value) {
    genSettings = genSettings.copyWith(memoryEnabled: value);
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateVoiceSettings(VoiceSettings value) {
    voiceSettings = value;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void updateSyncSettings(SyncSettings value) {
    syncSettings = value;
    notifyListeners();
    unawaited(_persist(touchSavedAt: false));
  }

  void updateCustomCounters(List<CustomCounter> value) {
    customCounters = value;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void resetTokenUsage() {
    tokenUsageData = const [];
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  Future<void> fetchModels() async {
    isFetchingModels = true;
    modelFetchStatus = 'Fetching models...';
    notifyListeners();
    try {
      final catalog = await _ai.fetchModels(
        geminiApiKey: geminiApiKey,
        endpoints: endpoints,
        syncSettings: syncSettings,
      );
      geminiModels = catalog.geminiModels;
      endpointModels = catalog.endpointModels;
      models = catalog.combined();
      if (!models.contains(selectedModel)) models = [selectedModel, ...models];
      final warningText = catalog.warnings.isEmpty
          ? ''
          : ' ${catalog.warnings.take(2).join(' ')}';
      modelFetchStatus =
          'Loaded ${models.length} models (${endpointModels.length} endpoint).$warningText';
    } catch (error) {
      modelFetchStatus = error.toString().replaceFirst('Exception: ', '');
    } finally {
      isFetchingModels = false;
      notifyListeners();
    }
  }

  Future<List<String>> fetchEndpointModels(EndpointConfig endpoint) async {
    final list = await _ai.fetchAvailableModelsForEndpoint(
      endpoint: endpoint,
      syncSettings: syncSettings,
    );
    return list.map((m) => m['id'] as String).toList();
  }

  Future<void> saveSettings() async {
    await fetchModels();
    syncStatus = 'Settings saved.';
    notifyListeners();
    await _persistAndScheduleRemote();
  }

  Future<void> syncNow() async {
    if (currentUser == null ||
        currentUser!.isGuest ||
        authToken.isEmpty ||
        !syncSettings.enabled) {
      syncStatus = 'Sign in or save guest session first.';
      notifyListeners();
      return;
    }
    syncStatus = 'Syncing...';
    notifyListeners();
    try {
      final remote = await _sync.pullRemoteState(authToken, syncSettings);
      if (remote != null) {
        _applyState(_mergeRemote(buildState(), remote), notify: false);
      }
      await _sync.pushRemoteState(buildState());
      lastSyncAt = DateTime.now().millisecondsSinceEpoch;
      syncStatus = 'Successfully synced to database.';
    } catch (error) {
      syncStatus = error.toString().replaceFirst('Exception: ', '');
    }
    notifyListeners();
    await _persist(touchSavedAt: false);
  }

  void _replaceSession(String id, Session next) {
    sessions = sessions
        .map((session) => session.id == id ? next : session)
        .toList();
  }

  void _queueStreamText(
    String generationId,
    String sessionId,
    String botId,
    String text,
  ) {
    if (_activeGenerationId != generationId || _generationStopRequested) return;
    _pendingStreamText = text;
    _streamFlushTimer ??= Timer(_streamFlushDelay(text.length), () {
      _streamFlushTimer = null;
      _flushStreamText(generationId, sessionId, botId);
    });
  }

  Duration _streamFlushDelay(int textLength) {
    if (textLength > 12000) return const Duration(milliseconds: 160);
    if (textLength > 6000) return const Duration(milliseconds: 120);
    return const Duration(milliseconds: 80);
  }

  void _flushStreamText(
    String generationId,
    String sessionId,
    String botId, {
    bool force = false,
  }) {
    if (_activeGenerationId != generationId || _pendingStreamText.isEmpty) {
      return;
    }
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;

    final text = _pendingStreamText;
    if (!force && text == _lastDisplayedStreamText) return;

    _lastDisplayedStreamText = text;
    _updateBotMessage(sessionId, botId, text);
  }

  void _cancelStreamFlush({bool resetText = false}) {
    _streamFlushTimer?.cancel();
    _streamFlushTimer = null;
    if (resetText) {
      _pendingStreamText = '';
      _lastDisplayedStreamText = '';
    }
  }

  void _updateBotMessage(
    String sessionId,
    String botId,
    String text, {
    int? tokenCount,
  }) {
    final session = sessions.where((item) => item.id == sessionId).firstOrNull;
    if (session == null) return;
    final messages = session.messages
        .map(
          (message) => message.id == botId
              ? message.copyWith(text: text, tokenCount: tokenCount)
              : message,
        )
        .toList();
    _replaceSession(
      sessionId,
      session.copyWith(
        messages: messages,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
  }

  void _appendLiveTranscript({
    required String text,
    required String sender,
    required String model,
    required bool finished,
  }) {
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;

    final session = currentSession;
    final isUser = sender == 'user';
    final activeId = isUser ? _liveUserMessageId : _liveBotMessageId;
    final now = DateTime.now();
    final messages = [...session.messages];
    final index = activeId == null
        ? -1
        : messages.indexWhere((message) => message.id == activeId);

    if (index == -1) {
      final id =
          'live-$sender-${now.microsecondsSinceEpoch}-${messages.length}';
      if (isUser) {
        _liveUserMessageId = id;
        if (finished) _maybeSaveUserMemory(clean);
      } else {
        _liveBotMessageId = id;
      }
      messages.add(
        Message(
          id: id,
          text: clean,
          sender: sender,
          timestamp: DateFormat('hh:mm a').format(now),
          model: isUser ? null : model,
          tokenCount: finished ? countTokens(clean) : null,
        ),
      );
    } else {
      final existing = messages[index];
      final merged = _mergeTranscript(existing.text, clean);
      messages[index] = existing.copyWith(
        text: merged,
        tokenCount: finished ? countTokens(merged) : null,
      );
      if (isUser && finished) {
        _maybeSaveUserMemory(merged);
      }
    }

    if (finished) {
      if (isUser) {
        _liveUserMessageId = null;
      } else {
        _liveBotMessageId = null;
      }
    }

    final firstUserSpeech = isUser && session.messages.isEmpty;
    final title = firstUserSpeech
        ? cleanTitle(clean).split(RegExp(r'\s+')).take(4).join(' ')
        : session.title;

    _replaceSession(
      session.id,
      session.copyWith(
        title: title.isEmpty ? session.title : title,
        messages: messages,
        updatedAt: now.millisecondsSinceEpoch,
      ),
    );
    notifyListeners();

    final finishedFirstUserSpeech =
        isUser &&
        finished &&
        session.messages.where((m) => m.isUser).length <= 1;
    if (finishedFirstUserSpeech) {
      // For live mode, we just wait until the session has at least 2 messages
      // to generate the title properly with context. If it's a fast response, it might be caught here.
      // Otherwise, the general text chat flow handles it. Live mode will eventually trigger this.
      if (session.messages.length >= 2) {
        unawaited(_generateSessionTitle(sessionId: session.id, model: model));
      }
    }
  }

  String _mergeTranscript(String existing, String chunk) {
    final left = existing.trim();
    final right = chunk.trim();
    if (left.isEmpty) return right;
    if (right.isEmpty || left.endsWith(right)) return left;
    if (right.startsWith(left)) return right;
    final spacer = RegExp(r'[\s,.;:!?]$').hasMatch(left) ? '' : ' ';
    return '$left$spacer$right';
  }

  void _clearLiveState({bool clearStatus = true}) {
    isLiveActive = false;
    isLiveConnecting = false;
    isLiveRecording = false;
    isLiveVideoEnabled = false;
    liveInputLevel = 0;
    liveOutputLevel = 0;
    _liveInputReleaseTimer?.cancel();
    _liveInputReleaseTimer = null;
    _liveOutputPulseTimer?.cancel();
    _liveOutputPulseTimer = null;
    _liveUserMessageId = null;
    _liveBotMessageId = null;
    if (clearStatus) liveStatus = '';
  }

  List<String> _liveModelCandidates() {
    final selected = selectedModel.trim();
    final candidates = [
      if (_isLiveCapableModel(selected)) selected,
      'gemini-3.1-flash-live-preview',
      'gemini-2.5-flash-native-audio-preview-12-2025',
      ...models,
      ...geminiModels,
      'gemini-live-2.5-flash-preview',
    ].where(_isLiveCapableModel);
    final seen = <String>{};
    return candidates.where((model) => seen.add(model)).toList();
  }

  bool _isLiveCapableModel(String model) {
    final value = model.toLowerCase();
    return value.contains('live') || value.contains('native-audio');
  }

  Future<void> _startLiveForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await Permission.notification.request();
    } catch (_) {}
    await LiveForegroundService.start();
  }

  Future<void> _generateSessionTitle({
    required String sessionId,
    required String model,
  }) async {
    final session = sessions.where((item) => item.id == sessionId).firstOrNull;
    if (session == null || session.messages.isEmpty) return;

    final history = session.messages.take(2).toList();
    if (history.isEmpty) return;
    final titleModel =
        genSettings.titleModelEnabled &&
            genSettings.titleModel.trim().isNotEmpty
        ? genSettings.titleModel.trim()
        : model;

    try {
      final generated = await _ai.generateTitle(
        messages: history,
        selectedModel: titleModel,
        endpoints: endpoints,
        endpointModels: endpointModels,
        geminiApiKey: geminiApiKey,
        syncSettings: syncSettings,
      );

      final title = cleanTitle(generated);
      if (title.trim().isEmpty) return;

      final currentSession = sessions
          .where((item) => item.id == sessionId)
          .firstOrNull;
      if (currentSession == null || currentSession.messages.isEmpty) return;

      _replaceSession(
        sessionId,
        currentSession.copyWith(
          title: title,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _persistAndScheduleRemote();
      notifyListeners();
    } catch (_) {}
  }

  void _pulseLiveOutput() {
    _setLiveOutputLevel(
      liveOutputLevel < 0.32 ? 0.32 : liveOutputLevel,
      releaseAfter: const Duration(milliseconds: 520),
    );
  }

  void _setLiveInputLevel(double level) {
    final visualLevel = _visualLiveLevel(level);
    liveInputLevel = visualLevel >= liveInputLevel
        ? visualLevel
        : liveInputLevel * 0.38 + visualLevel * 0.62;
    _liveInputReleaseTimer?.cancel();
    if (liveInputLevel <= 0.01) {
      liveInputLevel = 0;
      _liveInputReleaseTimer = null;
      notifyListeners();
      return;
    }
    _liveInputReleaseTimer = Timer(const Duration(milliseconds: 240), () {
      liveInputLevel = 0;
      notifyListeners();
    });
    notifyListeners();
  }

  void _setLiveOutputLevel(
    double level, {
    Duration releaseAfter = const Duration(milliseconds: 260),
  }) {
    final visualLevel = _visualLiveLevel(level);
    liveOutputLevel = visualLevel >= liveOutputLevel
        ? visualLevel
        : liveOutputLevel * 0.42 + visualLevel * 0.58;
    _liveOutputPulseTimer?.cancel();
    if (liveOutputLevel <= 0) {
      _liveOutputPulseTimer = null;
      notifyListeners();
      return;
    }
    _liveOutputPulseTimer = Timer(releaseAfter, () {
      liveOutputLevel = 0;
      notifyListeners();
    });
    notifyListeners();
  }

  double _visualLiveLevel(double rms) {
    final value = rms.clamp(0.0, 1.0).toDouble();
    if (value <= 0.004) return 0;
    final gated = ((value - 0.004) / 0.115).clamp(0.0, 1.0).toDouble();
    return math.pow(gated, 0.55).toDouble().clamp(0.0, 1.0).toDouble();
  }

  String _cleanLiveError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '').trim();
    if (value.isEmpty) return 'Gemini Live failed.';
    return value.startsWith('Gemini Live') ? value : 'Gemini Live: $value';
  }

  void _maybeSaveUserMemory(String text) {
    if (!genSettings.memoryEnabled) return;
    final actions = const MemoryAgent().analyze(
      message: text,
      existingMemories: memories,
    );
    _applyMemoryActions(actions);
  }

  void _applyMemoryActions(List<MemoryAgentAction> actions) {
    var next = [...memories];
    var changed = false;
    for (final action in actions) {
      if (action.action == 'ignore') continue;
      if (action.action == 'delete') {
        final before = next.length;
        next = next
            .where((memory) => !_memoryMatchesKey(memory, action.key))
            .toList();
        changed = changed || next.length != before;
        continue;
      }
      if (!action.applies || action.value.trim().isEmpty) continue;

      final clean = action.value.trim();
      final existingIndex = next.indexWhere(
        (memory) =>
            _memoryMatchesKey(memory, action.key) ||
            _normalizeMemory(memory.content) == _normalizeMemory(clean),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      if (existingIndex == -1) {
        next.insert(
          0,
          Memory(
            id: '$now-${next.length}',
            content: clean,
            timestamp: now,
            key: action.key,
            type: action.type,
            scope: action.scope,
            sensitivity: action.sensitivity,
          ),
        );
        changed = true;
        continue;
      }

      final existing = next[existingIndex];
      if (existing.content != clean ||
          existing.key != action.key ||
          existing.type != action.type ||
          existing.scope != action.scope ||
          existing.sensitivity != action.sensitivity) {
        next[existingIndex] = existing.copyWith(
          content: clean,
          timestamp: now,
          key: action.key,
          type: action.type,
          scope: action.scope,
          sensitivity: action.sensitivity,
        );
        changed = true;
      }
    }

    if (!changed) return;
    next.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    memories = next;
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  bool _isDuplicateMemory(String content) {
    final normalized = _normalizeMemory(content);
    final key = Memory.inferKey(content);
    return memories.any((memory) {
      if (_normalizeMemory(memory.content) == normalized) return true;
      return key.isNotEmpty && _memoryMatchesKey(memory, key);
    });
  }

  bool _memoryMatchesKey(Memory memory, String key) {
    if (key.isEmpty || key == 'none') return false;
    final memoryKey = memory.key.isNotEmpty
        ? memory.key
        : Memory.inferKey(memory.content);
    if (memoryKey == key) return true;
    if (key == 'preferred_framework' &&
        memoryKey == 'preferred_mobile_framework') {
      return true;
    }
    return false;
  }

  String _normalizeMemory(String content) => content
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Future<void> _persist({bool touchSavedAt = true}) async {
    if (touchSavedAt) {
      _stateSavedAt = DateTime.now().millisecondsSinceEpoch;
    } else if (_stateSavedAt == 0) {
      _stateSavedAt = DateTime.now().millisecondsSinceEpoch;
    }
    await _storage.save(buildState());
  }

  Future<void> _persistAndScheduleRemote() async {
    await _persist();
    _scheduleRemoteSync();
  }

  void _scheduleRemoteSync() {
    if (currentUser == null ||
        currentUser!.isGuest ||
        authToken.isEmpty ||
        !syncSettings.enabled) {
      return;
    }
    final hashState = buildState().toJson(includeSecrets: true)
      ..remove('savedAt');
    final stateHash = jsonEncode(hashState);
    if (stateHash == lastPushedHash) return;
    _remoteSyncTimer?.cancel();
    _remoteSyncTimer = Timer(const Duration(seconds: 15), () async {
      try {
        syncStatus = 'Syncing to remote...';
        notifyListeners();
        await _sync.pushRemoteState(buildState());
        lastPushedHash = stateHash;
        lastSyncAt = DateTime.now().millisecondsSinceEpoch;
        syncStatus = 'Successfully synced to database.';
        notifyListeners();
        await _persist(touchSavedAt: false);
      } catch (error) {
        syncStatus = error.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _remoteSyncTimer?.cancel();
    _liveInputReleaseTimer?.cancel();
    _liveOutputPulseTimer?.cancel();
    final live = _liveService;
    if (live != null) unawaited(live.dispose());
    _cancelStreamFlush(resetText: true);
    _ai.dispose();
    unawaited(LiveForegroundService.stop());
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _TargetRequestConfig {
  const _TargetRequestConfig({
    required this.model,
    required this.endpoints,
    required this.endpointModels,
    required this.contextWindow,
    this.configurationError,
  });

  final String model;
  final List<EndpointConfig> endpoints;
  final List<EndpointModel> endpointModels;
  final int contextWindow;
  final String? configurationError;
}
