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
  DateTime? _lastHapticAt;

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
  GenerationSettings genSettings = const GenerationSettings();
  VoiceSettings voiceSettings = const VoiceSettings();
  List<Session> sessions = [Session.empty('1')];
  String currentSessionId = '1';
  List<Memory> memories = const [];
  List<TokenUsageRecord> tokenUsageData = const [];
  List<CustomCounter> customCounters = const [];
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
            : Session.empty('default'));
  }

  bool get isDark => theme == 'dark';

  Future<void> initialize() async {
    final saved = await _storage.load();
    _applyState(saved ?? PersistedAppState.defaults(), notify: false);
    if (kIsWeb && syncSettings.apiBaseUrl.trim().isEmpty) {
      syncSettings = syncSettings.copyWith(
        apiBaseUrl: SyncService.defaultWebApiBaseUrl,
      );
    }

    if (activeSessions.isEmpty) {
      final session = Session.empty();
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
    unawaited(_persist());
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
          unawaited(_persist());
        }
      } catch (error) {
        syncStatus = 'Auto-pull failed; using local state.';
        notifyListeners();
      }
    }
  }

  PersistedAppState buildState() {
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
      isThinkingMode: isThinkingMode,
      isArtifactMode: isArtifactMode,
      soundEffectsEnabled: soundEffectsEnabled,
      isLiveVideoEnabled: isLiveVideoEnabled,
      isLiveFrontCamera: isLiveFrontCamera,
      userName: userName,
      geminiApiKey: geminiApiKey,
      endpoints: endpoints,
      genSettings: genSettings,
      voiceSettings: voiceSettings,
      sessions: persistedSessions,
      currentSessionId: persistedCurrentId,
      memories: memories,
      tokenUsageData: tokenUsageData,
      customCounters: customCounters,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _applyState(PersistedAppState state, {bool notify = true}) {
    currentUser = state.currentUser;
    authToken = state.authToken;
    syncSettings = state.syncSettings;
    language = state.language;
    theme = state.theme;
    visualTheme = state.visualTheme;
    selectedModel = state.selectedModel;
    isThinkingMode = state.isThinkingMode;
    isArtifactMode = state.isArtifactMode;
    soundEffectsEnabled = state.soundEffectsEnabled;
    isLiveVideoEnabled = state.isLiveVideoEnabled;
    isLiveFrontCamera = state.isLiveFrontCamera;
    userName = state.userName;
    geminiApiKey = state.geminiApiKey;
    endpoints = state.endpoints.isEmpty ? endpoints : state.endpoints;
    genSettings = state.genSettings;
    voiceSettings = state.voiceSettings;
    sessions = state.sessions.isEmpty ? [Session.empty('1')] : state.sessions;
    currentSessionId = state.currentSessionId;
    memories = state.memories;
    tokenUsageData = state.tokenUsageData;
    customCounters = state.customCounters;
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
      endpoints: remoteIsNewer && remote.endpoints.isNotEmpty
          ? remote.endpoints
          : local.endpoints,
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
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
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
    final session = Session.empty('1');
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
    theme = isDark ? 'light' : 'dark';
    notifyListeners();
    unawaited(_persistAndScheduleRemote());
  }

  void setVisualTheme(String value) {
    final normalized = switch (value.trim().toLowerCase()) {
      'liquid-glass' || 'liquidglass' || 'glass' => 'liquid-glass',
      'aurora-neon' || 'auroraneon' || 'aurora' || 'neon' => 'aurora-neon',
      'modern-minimal' || 'modernminimal' || 'minimal' => 'modern-minimal',
      _ => 'default',
    };
    if (visualTheme == normalized) return;
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
    unawaited(_persist());
  }

  void setSoundEffectsEnabled(bool enabled) {
    if (soundEffectsEnabled == enabled) return;
    soundEffectsEnabled = enabled;
    notifyListeners();
    unawaited(_persist());
  }

  void setSelectedModel(String model) {
    selectedModel = model;
    notifyListeners();
    unawaited(_persist());
  }

  void createSession() {
    if (currentSession.messages.isEmpty) {
      currentView = AppView.chat;
      notifyListeners();
      return;
    }
    final session = Session.empty();
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
    currentView = AppView.chat;
    notifyListeners();
    unawaited(_persist());
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
      final session = Session.empty();
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
    final session = Session.empty();
    sessions = [
      ...sessions.map((item) => item.copyWith(deleted: true, updatedAt: now)),
      session,
    ];
    currentSessionId = session.id;
    currentView = AppView.chat;
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

  Memory? saveMemory(String content) {
    final clean = content.trim();
    if (clean.isEmpty || _isDuplicateMemory(clean)) return null;
    final memory = Memory(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: clean,
      timestamp: DateTime.now().millisecondsSinceEpoch,
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
    unawaited(_playSound('send_user_message.wav'));
    unawaited(_playSound('loading_ai_response.wav'));

    Timer? loadingAudioTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!isGenerating) {
        timer.cancel();
      } else {
        unawaited(_playSound('loading_ai_response.wav'));
      }
    });

    final session = currentSession;
    final now = DateTime.now();
    final userMessage = Message(
      id: now.millisecondsSinceEpoch.toString(),
      text: prompt.trim(),
      sender: 'user',
      timestamp: DateFormat('hh:mm a').format(now),
      attachments: attachments,
      tokenCount: countTokens(prompt),
    );
    final history = session.messages;
    final botId = (now.millisecondsSinceEpoch + 1).toString();
    final modelForRequest = selectedModel;
    final botMessage = Message(
      id: botId,
      text: '',
      sender: 'bot',
      timestamp: DateFormat('hh:mm a').format(now),
      model: modelForRequest,
    );
    final isFirstMessage = history.isEmpty;
    final fallbackTitle = cleanTitle(
      prompt.split(RegExp(r'\s+')).take(4).join(' '),
    );
    final nextSession = session.copyWith(
      title: isFirstMessage && fallbackTitle.isNotEmpty
          ? fallbackTitle
          : session.title,
      messages: [...history, userMessage, botMessage],
      updatedAt: now.millisecondsSinceEpoch,
    );
    _replaceSession(session.id, nextSession);
    isGenerating = true;
    syncStatus = '';
    _maybeSaveUserMemory(prompt);
    notifyListeners();
    if (isFirstMessage) {
      unawaited(
        _generateSessionTitle(
          sessionId: session.id,
          message: prompt.trim(),
          model: modelForRequest,
        ),
      );
    }

    String fullBotText = '';
    String displayedBotText = '';
    Timer? typingTimer;

    void startTypingTimer() {
      typingTimer ??= Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!isGenerating) {
          timer.cancel();
          typingTimer = null;
          if (displayedBotText != fullBotText) {
            _updateBotMessage(session.id, botId, fullBotText);
          }
          return;
        }

        if (displayedBotText.length < fullBotText.length) {
          int diff = fullBotText.length - displayedBotText.length;
          int charsToAdd = (diff / 4).ceil().clamp(1, 40);
          displayedBotText = fullBotText.substring(
            0,
            displayedBotText.length + charsToAdd,
          );
          _updateBotMessage(session.id, botId, displayedBotText);
          _maybeHapticForStreaming(displayedBotText);
        }
      });
    }

    try {
      final response = await _ai.sendMessage(
        prompt: prompt.trim(),
        attachments: attachments,
        history: history,
        selectedModel: modelForRequest,
        endpoints: endpoints,
        endpointModels: endpointModels,
        genSettings: genSettings,
        voiceSettings: voiceSettings,
        geminiApiKey: geminiApiKey,
        memories: genSettings.memoryEnabled ? memories : const [],
        thinkingMode: isThinkingMode,
        artifactMode: isArtifactMode,
        syncSettings: syncSettings,
        onStatus: (status) {
          _updateBotMessage(session.id, botId, status);
        },
        onText: (text) {
          if (loadingAudioTimer != null) {
            loadingAudioTimer?.cancel();
            loadingAudioTimer = null;
          }
          fullBotText = text;
          startTypingTimer();
        },
      );
      typingTimer?.cancel();
      typingTimer = null;
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
        ),
      ];
    } catch (error) {
      _updateBotMessage(
        session.id,
        botId,
        'Error: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      loadingAudioTimer?.cancel();
      loadingAudioTimer = null;
      typingTimer?.cancel();
      typingTimer = null;
      isGenerating = false;
      notifyListeners();
      await _persistAndScheduleRemote();
    }
  }

  void stopGeneration() {
    isGenerating = false;
    notifyListeners();
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
    isLiveVideoEnabled = !isLiveVideoEnabled;
    notifyListeners();
    unawaited(_persist());
  }

  void toggleLiveCameraFacing() {
    isLiveFrontCamera = !isLiveFrontCamera;
    notifyListeners();
    unawaited(_persist());
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
    final messages = [...session.messages];
    final attachments = messages[index].attachments;
    final trimmed = messages.sublist(0, index);
    _replaceSession(
      session.id,
      session.copyWith(
        messages: trimmed,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    notifyListeners();
    unawaited(sendMessage(text, attachments));
  }

  void regenerateLast() {
    final session = currentSession;
    for (var i = session.messages.length - 1; i >= 0; i--) {
      if (session.messages[i].isUser) {
        final user = session.messages[i];
        final trimmed = session.messages.sublist(0, i);
        _replaceSession(
          session.id,
          session.copyWith(
            messages: trimmed,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        notifyListeners();
        unawaited(sendMessage(user.text, user.attachments));
        return;
      }
    }
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
    unawaited(_persist());
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
    return _ai.fetchAvailableModelsForEndpoint(
      endpoint: endpoint,
      syncSettings: syncSettings,
    );
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
    await _persist();
  }

  void _replaceSession(String id, Session next) {
    sessions = sessions
        .map((session) => session.id == id ? next : session)
        .toList();
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
        _maybeSaveUserMemory(clean);
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
      unawaited(
        _generateSessionTitle(
          sessionId: session.id,
          message: clean,
          model: model,
        ),
      );
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
    isLiveFrontCamera = false;
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
    required String message,
    required String model,
  }) async {
    if (message.trim().isEmpty) return;
    try {
      final generated = await _ai.generateTitle(
        message: message,
        selectedModel: model,
        endpoints: endpoints,
        endpointModels: endpointModels,
        geminiApiKey: geminiApiKey,
        syncSettings: syncSettings,
      );
      final title = cleanTitle(
        generated,
      ).split(RegExp(r'\s+')).take(4).join(' ');
      if (title.trim().isEmpty) return;
      final session = sessions
          .where((item) => item.id == sessionId)
          .firstOrNull;
      if (session == null || session.messages.isEmpty) return;
      _replaceSession(
        sessionId,
        session.copyWith(
          title: title.trim(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      notifyListeners();
      unawaited(_persistAndScheduleRemote());
    } catch (_) {}
  }

  void _maybeHapticForStreaming(String text) {
    if (!genSettings.hapticStreamingEnabled ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        text.trim().isEmpty) {
      return;
    }
    final now = DateTime.now();
    final last = _lastHapticAt;
    if (last != null && now.difference(last).inMilliseconds < 40) return;
    _lastHapticAt = now;
    unawaited(HapticFeedback.lightImpact());
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
    final name = _extractRememberedName(text);
    if (name != null) {
      final pretty = name.substring(0, 1).toUpperCase() + name.substring(1);
      saveMemory("The user's name is $pretty.");
      return;
    }
    final remember = RegExp(
      r'\bremember(?: that)?\s+(.{3,220})',
      caseSensitive: false,
    ).firstMatch(text);
    if (remember != null) {
      final content = remember
          .group(1)!
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .replaceAll(RegExp(r'[.!?]+$'), '');
      if (content.isNotEmpty) saveMemory(content);
    }
  }

  bool _isDuplicateMemory(String content) {
    final normalized = _normalizeMemory(content);
    final rememberedName = _extractRememberedName(content);
    return memories.any((memory) {
      if (_normalizeMemory(memory.content) == normalized) return true;
      return rememberedName != null &&
          _extractRememberedName(memory.content) == rememberedName;
    });
  }

  String _normalizeMemory(String content) => content
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String? _extractRememberedName(String content) {
    final normalized = _normalizeMemory(content);
    final match = RegExp(
      r"\b(?:user is named|users name is|user name is|my name is|i am|im|i'm)\s+([a-z0-9_-]{2,})\b",
    ).firstMatch(normalized);
    return match?.group(1);
  }

  Future<void> _persist() async {
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
        await _persist();
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
    unawaited(LiveForegroundService.stop());
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
