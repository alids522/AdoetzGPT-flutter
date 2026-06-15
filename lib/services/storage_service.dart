import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class StorageService {
  static const appStateKey = 'adoetzgpt.appState';

  Future<PersistedAppState?> load() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File(path.join(directory.path, 'adoetzgpt_state.json'));
      
      String raw = '';
      if (await file.exists()) {
        raw = await file.readAsString();
      } else {
        // Fallback to SharedPreferences for migration
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(appStateKey) ?? prefs.getString('appState') ?? '';
      }
      
      if (raw.isEmpty) return null;
      return PersistedAppState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PersistedAppState state) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(path.join(directory.path, 'adoetzgpt_state.json'));
    await file.writeAsString(_compactForStorage(state).encode());
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('currentUser');
    await prefs.remove('authToken');
  }

  PersistedAppState _compactForStorage(PersistedAppState state) {
    final compactSessions = state.sessions.map((session) {
      final compactMessages = session.messages.map((message) {
        final attachments = message.attachments.map((attachment) {
          return AttachmentData(
            name: attachment.name,
            type: attachment.type,
            data: attachment.data.length <= 500000 ? attachment.data : '',
            url: null,
          );
        }).toList();
        return message.copyWith(attachments: attachments);
      }).toList();
      return session.copyWith(messages: compactMessages);
    }).toList();

    return PersistedAppState(
      currentUser: state.currentUser,
      authToken: state.authToken,
      syncSettings: state.syncSettings,
      language: state.language,
      theme: state.theme,
      visualTheme: state.visualTheme,
      selectedModel: state.selectedModel,
      selectedTargetId: state.selectedTargetId,
      isThinkingMode: state.isThinkingMode,
      isArtifactMode: state.isArtifactMode,
      userName: state.userName,
      geminiApiKey: state.geminiApiKey,
      endpoints: state.endpoints,
      agentConnectors: state.agentConnectors,
      modelContextOverrides: state.modelContextOverrides,
      modelInputCosts: state.modelInputCosts,
      modelOutputCosts: state.modelOutputCosts,
      modelCacheHitCosts: state.modelCacheHitCosts,
      genSettings: state.genSettings,
      voiceSettings: state.voiceSettings,
      sessions: compactSessions,
      currentSessionId: state.currentSessionId,
      memories: state.memories,
      tokenUsageData: state.tokenUsageData.length > 500
          ? state.tokenUsageData.take(500).toList()
          : state.tokenUsageData,
      customCounters: state.customCounters,
      soundEffectsEnabled: state.soundEffectsEnabled,
      isLiveVideoEnabled: state.isLiveVideoEnabled,
      isLiveFrontCamera: state.isLiveFrontCamera,
      cachedPasswordHash: state.cachedPasswordHash,
      lastSyncAt: state.lastSyncAt,
      savedAt: state.savedAt,
    );
  }
}
