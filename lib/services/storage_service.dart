import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

class StorageService {
  static const appStateKey = 'adoetzgpt.appState';

  Future<PersistedAppState?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(appStateKey) ?? prefs.getString('appState');
    if (raw == null || raw.isEmpty) return null;
    try {
      return PersistedAppState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(PersistedAppState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appStateKey, _compactForStorage(state).encode());
  }

  Future<void> clearAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('currentUser');
    await prefs.remove('authToken');
  }

  PersistedAppState _compactForStorage(PersistedAppState state) {
    final compactSessions = state.sessions.map((session) {
      final compactMessages = session.messages.map((message) {
        final compactText = _compactText(message.text, 12000);
        final attachments = message.attachments.map((attachment) {
          return AttachmentData(
            name: attachment.name,
            type: attachment.type,
            data: attachment.data.length <= 500000 ? attachment.data : '',
            url: null,
          );
        }).toList();
        return message.copyWith(text: compactText, attachments: attachments);
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
      genSettings: state.genSettings,
      voiceSettings: state.voiceSettings,
      sessions: compactSessions,
      currentSessionId: state.currentSessionId,
      memories: state.memories,
      tokenUsageData: state.tokenUsageData.length > 500
          ? state.tokenUsageData.sublist(state.tokenUsageData.length - 500)
          : state.tokenUsageData,
      customCounters: state.customCounters,
      soundEffectsEnabled: state.soundEffectsEnabled,
      isLiveVideoEnabled: state.isLiveVideoEnabled,
      isLiveFrontCamera: state.isLiveFrontCamera,
      savedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String _compactText(String text, int limit) {
    if (text.length <= limit) return text;
    final head = (limit * 0.65).floor();
    final tail = (limit * 0.35).floor();
    return '${text.substring(0, head)}\n\n[Earlier saved content compacted]\n\n${text.substring(text.length - tail)}';
  }
}
