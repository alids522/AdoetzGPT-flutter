import 'dart:convert';

enum AppView { chat, settings, tokenUsage }

enum AppLanguage { en, id }

AppLanguage normalizeLanguage(Object? value) {
  return value == 'en' || value == AppLanguage.en
      ? AppLanguage.en
      : AppLanguage.id;
}

String languageCode(AppLanguage language) =>
    language == AppLanguage.en ? 'en' : 'id';

String stringValue(Object? value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
}

int intValue(Object? value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool boolValue(Object? value, [bool fallback = false]) {
  if (value is bool) return value;
  if (value is String) return value.toLowerCase() == 'true';
  return fallback;
}

List<Map<String, dynamic>> mapList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  return const [];
}

class AttachmentData {
  const AttachmentData({
    required this.name,
    required this.type,
    required this.data,
    this.url,
  });

  final String name;
  final String type;
  final String data;
  final String? url;

  factory AttachmentData.fromJson(Map<String, dynamic> json) {
    return AttachmentData(
      name: stringValue(json['name']),
      type: stringValue(json['type']),
      data: stringValue(json['data']),
      url: json['url'] == null ? null : stringValue(json['url']),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'data': data,
    if (url != null) 'url': url,
  };
}

class Message {
  const Message({
    required this.id,
    required this.text,
    required this.sender,
    required this.timestamp,
    this.model,
    this.attachments = const [],
    this.tokenCount,
  });

  final String id;
  final String text;
  final String sender;
  final String timestamp;
  final String? model;
  final List<AttachmentData> attachments;
  final int? tokenCount;

  bool get isUser => sender == 'user';

  Message copyWith({
    String? text,
    String? sender,
    String? timestamp,
    String? model,
    List<AttachmentData>? attachments,
    int? tokenCount,
    bool clearModel = false,
    bool clearTokenCount = false,
  }) {
    return Message(
      id: id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      model: clearModel ? null : model ?? this.model,
      attachments: attachments ?? this.attachments,
      tokenCount: clearTokenCount ? null : tokenCount ?? this.tokenCount,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: stringValue(json['id']),
      text: stringValue(json['text']),
      sender: stringValue(json['sender'], 'bot'),
      timestamp: stringValue(json['timestamp']),
      model: json['model'] == null ? null : stringValue(json['model']),
      attachments: mapList(
        json['attachments'],
      ).map(AttachmentData.fromJson).toList(),
      tokenCount: json['tokenCount'] == null
          ? null
          : intValue(json['tokenCount']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'sender': sender,
    'timestamp': timestamp,
    if (model != null) 'model': model,
    if (attachments.isNotEmpty)
      'attachments': attachments.map((item) => item.toJson()).toList(),
    if (tokenCount != null) 'tokenCount': tokenCount,
  };
}

class Session {
  const Session({
    required this.id,
    required this.title,
    required this.messages,
    required this.updatedAt,
    this.pinned = false,
    this.deleted = false,
  });

  final String id;
  final String title;
  final List<Message> messages;
  final int updatedAt;
  final bool pinned;
  final bool deleted;

  Session copyWith({
    String? title,
    List<Message>? messages,
    int? updatedAt,
    bool? pinned,
    bool? deleted,
  }) {
    return Session(
      id: id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      deleted: deleted ?? this.deleted,
    );
  }

  factory Session.empty([String? id]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Session(
      id: id ?? now.toString(),
      title: 'New Session',
      messages: const [],
      updatedAt: now,
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: stringValue(json['id']),
      title: stringValue(json['title'], 'New Session'),
      messages: mapList(json['messages']).map(Message.fromJson).toList(),
      updatedAt: intValue(
        json['updatedAt'],
        DateTime.now().millisecondsSinceEpoch,
      ),
      pinned: boolValue(json['pinned']),
      deleted: boolValue(json['deleted']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((item) => item.toJson()).toList(),
    'updatedAt': updatedAt,
    if (pinned) 'pinned': pinned,
    if (deleted) 'deleted': deleted,
  };
}

class EndpointConfig {
  const EndpointConfig({
    required this.id,
    required this.url,
    required this.key,
    required this.name,
    this.skipModelFetch = false,
    this.models = const [],
  });

  final String id;
  final String url;
  final String key;
  final String name;
  final bool skipModelFetch;
  final List<String> models;

  EndpointConfig copyWith({
    String? id,
    String? url,
    String? key,
    String? name,
    bool? skipModelFetch,
    List<String>? models,
  }) {
    return EndpointConfig(
      id: id ?? this.id,
      url: url ?? this.url,
      key: key ?? this.key,
      name: name ?? this.name,
      skipModelFetch: skipModelFetch ?? this.skipModelFetch,
      models: models ?? this.models,
    );
  }

  factory EndpointConfig.fromJson(Map<String, dynamic> json) {
    return EndpointConfig(
      id: stringValue(json['id']),
      url: stringValue(json['url']),
      key: stringValue(json['key']),
      name: stringValue(json['name'], 'Endpoint'),
      skipModelFetch: boolValue(json['skipModelFetch']),
      models: (json['models'] is List)
          ? (json['models'] as List).map((item) => item.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'key': key,
    'name': name,
    if (skipModelFetch) 'skipModelFetch': skipModelFetch,
    if (models.isNotEmpty) 'models': models,
  };
}

class EndpointModel {
  const EndpointModel({required this.name, required this.endpointId});

  final String name;
  final String endpointId;
}

class GenerationSettings {
  const GenerationSettings({
    this.imageModel = 'gemini',
    this.videoModel = 'veo',
    this.memoryEnabled = true,
    this.webSearchMode = 'auto',
    this.webSearchEngine = 'gemini',
    this.webSearchProvider = 'gemini',
    this.webSearchModel = 'gemini-flash-lite-latest',
    this.webSearchEndpointId = '',
    this.googleSearchApiKey = '',
    this.googleSearchCx = '',
    this.tavilyApiKey = '',
    this.hapticStreamingEnabled = false,
  });

  final String imageModel;
  final String videoModel;
  final bool memoryEnabled;
  final String webSearchMode;
  final String webSearchEngine;
  final String webSearchProvider;
  final String webSearchModel;
  final String webSearchEndpointId;
  final String googleSearchApiKey;
  final String googleSearchCx;
  final String tavilyApiKey;
  final bool hapticStreamingEnabled;

  GenerationSettings copyWith({
    String? imageModel,
    String? videoModel,
    bool? memoryEnabled,
    String? webSearchMode,
    String? webSearchEngine,
    String? webSearchProvider,
    String? webSearchModel,
    String? webSearchEndpointId,
    String? googleSearchApiKey,
    String? googleSearchCx,
    String? tavilyApiKey,
    bool? hapticStreamingEnabled,
  }) {
    final nextEngine = webSearchEngine ?? this.webSearchEngine;
    return GenerationSettings(
      imageModel: imageModel ?? this.imageModel,
      videoModel: videoModel ?? this.videoModel,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
      webSearchMode: webSearchMode ?? this.webSearchMode,
      webSearchEngine: nextEngine,
      webSearchProvider:
          webSearchProvider ??
          (nextEngine == 'endpoint' ? 'endpoint' : 'gemini'),
      webSearchModel: webSearchModel ?? this.webSearchModel,
      webSearchEndpointId: webSearchEndpointId ?? this.webSearchEndpointId,
      googleSearchApiKey: googleSearchApiKey ?? this.googleSearchApiKey,
      googleSearchCx: googleSearchCx ?? this.googleSearchCx,
      tavilyApiKey: tavilyApiKey ?? this.tavilyApiKey,
      hapticStreamingEnabled:
          hapticStreamingEnabled ?? this.hapticStreamingEnabled,
    );
  }

  factory GenerationSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GenerationSettings();
    final engine = stringValue(
      json['webSearchEngine'],
      json['webSearchProvider'] == 'endpoint' ? 'endpoint' : 'gemini',
    );
    return GenerationSettings(
      imageModel: stringValue(json['imageModel'], 'gemini'),
      videoModel: stringValue(json['videoModel'], 'veo'),
      memoryEnabled: json.containsKey('memoryEnabled')
          ? boolValue(json['memoryEnabled'])
          : true,
      webSearchMode: stringValue(json['webSearchMode'], 'auto'),
      webSearchEngine: engine,
      webSearchProvider: engine == 'endpoint' ? 'endpoint' : 'gemini',
      webSearchModel: stringValue(
        json['webSearchModel'],
        'gemini-flash-lite-latest',
      ),
      webSearchEndpointId: stringValue(json['webSearchEndpointId']),
      googleSearchApiKey: stringValue(json['googleSearchApiKey']),
      googleSearchCx: stringValue(json['googleSearchCx']),
      tavilyApiKey: stringValue(json['tavilyApiKey']),
      hapticStreamingEnabled: boolValue(json['hapticStreamingEnabled']),
    );
  }

  Map<String, dynamic> toJson() => {
    'imageModel': imageModel,
    'videoModel': videoModel,
    'memoryEnabled': memoryEnabled,
    'webSearchMode': webSearchMode,
    'webSearchEngine': webSearchEngine,
    'webSearchProvider': webSearchProvider,
    'webSearchModel': webSearchModel,
    'webSearchEndpointId': webSearchEndpointId,
    'googleSearchApiKey': googleSearchApiKey,
    'googleSearchCx': googleSearchCx,
    'tavilyApiKey': tavilyApiKey,
    'hapticStreamingEnabled': hapticStreamingEnabled,
  };
}

class CustomPersonality {
  const CustomPersonality({
    required this.id,
    required this.name,
    required this.prompt,
  });

  final String id;
  final String name;
  final String prompt;

  factory CustomPersonality.fromJson(Map<String, dynamic> json) {
    return CustomPersonality(
      id: stringValue(json['id']),
      name: stringValue(json['name']),
      prompt: stringValue(json['prompt']),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'prompt': prompt};
}

class VoiceSettings {
  const VoiceSettings({
    this.voice = 'Zephyr',
    this.personality = 'Assistant',
    this.customPersonality = '',
    this.textPersonality = 'Assistant',
    this.customTextPersonality = '',
    this.customVoicePersonalities = const [],
    this.customTextPersonalities = const [],
  });

  final String voice;
  final String personality;
  final String customPersonality;
  final String textPersonality;
  final String customTextPersonality;
  final List<CustomPersonality> customVoicePersonalities;
  final List<CustomPersonality> customTextPersonalities;

  VoiceSettings copyWith({
    String? voice,
    String? personality,
    String? customPersonality,
    String? textPersonality,
    String? customTextPersonality,
    List<CustomPersonality>? customVoicePersonalities,
    List<CustomPersonality>? customTextPersonalities,
  }) {
    return VoiceSettings(
      voice: voice ?? this.voice,
      personality: personality ?? this.personality,
      customPersonality: customPersonality ?? this.customPersonality,
      textPersonality: textPersonality ?? this.textPersonality,
      customTextPersonality:
          customTextPersonality ?? this.customTextPersonality,
      customVoicePersonalities:
          customVoicePersonalities ?? this.customVoicePersonalities,
      customTextPersonalities:
          customTextPersonalities ?? this.customTextPersonalities,
    );
  }

  factory VoiceSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const VoiceSettings();
    return VoiceSettings(
      voice: stringValue(json['voice'], 'Zephyr'),
      personality: stringValue(json['personality'], 'Assistant'),
      customPersonality: stringValue(json['customPersonality']),
      textPersonality: stringValue(json['textPersonality'], 'Assistant'),
      customTextPersonality: stringValue(json['customTextPersonality']),
      customVoicePersonalities: mapList(
        json['customVoicePersonalities'],
      ).map(CustomPersonality.fromJson).toList(),
      customTextPersonalities: mapList(
        json['customTextPersonalities'],
      ).map(CustomPersonality.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'voice': voice,
    'personality': personality,
    'customPersonality': customPersonality,
    'textPersonality': textPersonality,
    'customTextPersonality': customTextPersonality,
    'customVoicePersonalities': customVoicePersonalities
        .map((item) => item.toJson())
        .toList(),
    'customTextPersonalities': customTextPersonalities
        .map((item) => item.toJson())
        .toList(),
  };
}

class Memory {
  const Memory({
    required this.id,
    required this.content,
    required this.timestamp,
  });

  final String id;
  final String content;
  final int timestamp;

  Memory copyWith({String? content}) =>
      Memory(id: id, content: content ?? this.content, timestamp: timestamp);

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: stringValue(json['id']),
      content: stringValue(json['content']),
      timestamp: intValue(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'timestamp': timestamp,
  };
}

class TokenUsageRecord {
  const TokenUsageRecord({
    required this.timestamp,
    required this.model,
    required this.endpoint,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
  });

  final int timestamp;
  final String model;
  final String endpoint;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  factory TokenUsageRecord.fromJson(Map<String, dynamic> json) {
    return TokenUsageRecord(
      timestamp: intValue(json['timestamp']),
      model: stringValue(json['model']),
      endpoint: stringValue(json['endpoint']),
      inputTokens: intValue(json['inputTokens']),
      outputTokens: intValue(json['outputTokens']),
      totalTokens: intValue(json['totalTokens']),
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'model': model,
    'endpoint': endpoint,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
  };
}

class CustomCounter {
  const CustomCounter({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.color,
  });

  final String id;
  final String name;
  final int createdAt;
  final String color;

  CustomCounter copyWith({String? name, int? createdAt, String? color}) {
    return CustomCounter(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      color: color ?? this.color,
    );
  }

  factory CustomCounter.fromJson(Map<String, dynamic> json) {
    return CustomCounter(
      id: stringValue(json['id']),
      name: stringValue(json['name']),
      createdAt: intValue(json['createdAt']),
      color: stringValue(json['color'], '#ffffff'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'color': color,
  };
}

class UserAccount {
  const UserAccount({
    required this.id,
    required this.username,
    this.email,
    this.displayName,
    this.isGuest = false,
  });

  final String id;
  final String username;
  final String? email;
  final String? displayName;
  final bool isGuest;

  String get label => displayName?.isNotEmpty == true ? displayName! : username;

  factory UserAccount.guest() => const UserAccount(
    id: 'guest-local',
    username: 'guest',
    displayName: 'Guest',
    isGuest: true,
  );

  factory UserAccount.fromJson(Map<String, dynamic>? json) {
    if (json == null) return UserAccount.guest();
    final username = stringValue(
      json['username'],
      stringValue(
        json['email'],
        stringValue(
          json['displayName'],
          boolValue(json['isGuest']) ? 'guest' : 'user',
        ),
      ),
    );
    return UserAccount(
      id: stringValue(
        json['id'],
        '${boolValue(json['isGuest']) ? 'guest' : 'user'}-$username',
      ),
      username: username,
      email: json['email'] == null ? null : stringValue(json['email']),
      displayName: stringValue(
        json['displayName'],
        boolValue(json['isGuest']) ? 'Guest' : username,
      ),
      isGuest: boolValue(json['isGuest']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    if (email != null) 'email': email,
    'displayName': displayName ?? username,
    if (isGuest) 'isGuest': true,
  };
}

class DatabaseSettings {
  const DatabaseSettings({
    this.databaseUrl = '',
    this.database = '',
    this.schemaName = 'adoetzgpt',
    this.user = '',
    this.password = '',
    this.port = '',
  });

  final String databaseUrl;
  final String database;
  final String schemaName;
  final String user;
  final String password;
  final String port;

  DatabaseSettings copyWith({
    String? databaseUrl,
    String? database,
    String? schemaName,
    String? user,
    String? password,
    String? port,
  }) {
    return DatabaseSettings(
      databaseUrl: databaseUrl ?? this.databaseUrl,
      database: database ?? this.database,
      schemaName: schemaName ?? this.schemaName,
      user: user ?? this.user,
      password: password ?? this.password,
      port: port ?? this.port,
    );
  }

  factory DatabaseSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DatabaseSettings();
    return DatabaseSettings(
      databaseUrl: stringValue(json['databaseUrl']),
      database: stringValue(json['database']),
      schemaName: stringValue(json['schemaName'], 'adoetzgpt'),
      user: stringValue(json['user']),
      password: stringValue(json['password']),
      port: stringValue(json['port']),
    );
  }

  Map<String, dynamic> toJson({bool includePassword = true}) => {
    'databaseUrl': databaseUrl,
    'database': database,
    'schemaName': schemaName.isEmpty ? 'adoetzgpt' : schemaName,
    'user': user,
    'password': includePassword ? password : '',
    'port': port,
  };
}

class SyncSettings {
  const SyncSettings({
    this.enabled = false,
    this.apiBaseUrl = '',
    this.database = const DatabaseSettings(),
    this.backupDatabases = const [],
    this.autoSyncBackups = false,
  });

  final bool enabled;
  final String apiBaseUrl;
  final DatabaseSettings database;
  final List<DatabaseSettings> backupDatabases;
  final bool autoSyncBackups;

  SyncSettings copyWith({
    bool? enabled,
    String? apiBaseUrl,
    DatabaseSettings? database,
    List<DatabaseSettings>? backupDatabases,
    bool? autoSyncBackups,
  }) {
    return SyncSettings(
      enabled: enabled ?? this.enabled,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      database: database ?? this.database,
      backupDatabases: backupDatabases ?? this.backupDatabases,
      autoSyncBackups: autoSyncBackups ?? this.autoSyncBackups,
    );
  }

  factory SyncSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SyncSettings();
    final db = DatabaseSettings.fromJson(
      json['database'] is Map
          ? Map<String, dynamic>.from(json['database'])
          : json,
    );
    return SyncSettings(
      enabled: boolValue(json['enabled']),
      apiBaseUrl: stringValue(json['apiBaseUrl']),
      database: db.copyWith(
        schemaName: db.schemaName.isNotEmpty
            ? db.schemaName
            : stringValue(json['schemaName'], 'adoetzgpt'),
      ),
      backupDatabases: mapList(
        json['backupDatabases'],
      ).map(DatabaseSettings.fromJson).toList(),
      autoSyncBackups: boolValue(json['autoSyncBackups']),
    );
  }

  Map<String, dynamic> toJson({bool includePassword = true}) => {
    'enabled': enabled,
    'apiBaseUrl': apiBaseUrl,
    'database': database.toJson(includePassword: includePassword),
    'backupDatabases': backupDatabases
        .map((db) => db.toJson(includePassword: includePassword))
        .toList(),
    'autoSyncBackups': autoSyncBackups,
  };
}

class PersistedAppState {
  const PersistedAppState({
    required this.currentUser,
    required this.authToken,
    required this.syncSettings,
    required this.language,
    required this.theme,
    required this.visualTheme,
    required this.selectedModel,
    required this.isThinkingMode,
    required this.isArtifactMode,
    required this.userName,
    required this.geminiApiKey,
    required this.endpoints,
    required this.genSettings,
    required this.voiceSettings,
    required this.sessions,
    required this.currentSessionId,
    required this.memories,
    required this.tokenUsageData,
    required this.customCounters,
    required this.soundEffectsEnabled,
    required this.isLiveVideoEnabled,
    required this.isLiveFrontCamera,
    this.savedAt,
  });

  final UserAccount? currentUser;
  final String authToken;
  final SyncSettings syncSettings;
  final AppLanguage language;
  final String theme;
  final String visualTheme;
  final String selectedModel;
  final bool isThinkingMode;
  final bool isArtifactMode;
  final String userName;
  final String geminiApiKey;
  final List<EndpointConfig> endpoints;
  final GenerationSettings genSettings;
  final VoiceSettings voiceSettings;
  final List<Session> sessions;
  final String currentSessionId;
  final List<Memory> memories;
  final List<TokenUsageRecord> tokenUsageData;
  final List<CustomCounter> customCounters;
  final bool soundEffectsEnabled;
  final bool isLiveVideoEnabled;
  final bool isLiveFrontCamera;
  final int? savedAt;

  factory PersistedAppState.defaults() {
    final session = Session.empty('1');
    return PersistedAppState(
      currentUser: null,
      authToken: '',
      syncSettings: const SyncSettings(),
      language: AppLanguage.id,
      theme: 'dark',
      visualTheme: 'default',
      selectedModel: 'gemini-2.5-flash',
      isThinkingMode: false,
      isArtifactMode: false,
      userName: 'User',
      geminiApiKey: '',
      endpoints: const [
        EndpointConfig(
          id: '1',
          name: 'OpenAI',
          url: 'https://api.openai.com/v1',
          key: '',
        ),
      ],
      genSettings: const GenerationSettings(),
      voiceSettings: const VoiceSettings(),
      sessions: [session],
      currentSessionId: session.id,
      memories: const [],
      tokenUsageData: const [],
      customCounters: const [],
      soundEffectsEnabled: true,
      isLiveVideoEnabled: false,
      isLiveFrontCamera: false,
    );
  }

  factory PersistedAppState.fromJson(Map<String, dynamic> json) {
    final sessions = mapList(json['sessions']).map(Session.fromJson).toList();
    final defaults = PersistedAppState.defaults();
    return PersistedAppState(
      currentUser: json['currentUser'] == null
          ? null
          : UserAccount.fromJson(
              Map<String, dynamic>.from(json['currentUser']),
            ),
      authToken: stringValue(json['authToken']),
      syncSettings: SyncSettings.fromJson(
        json['syncSettings'] is Map
            ? Map<String, dynamic>.from(json['syncSettings'])
            : null,
      ),
      language: normalizeLanguage(json['language']),
      theme: stringValue(json['theme'], 'dark') == 'light' ? 'light' : 'dark',
      visualTheme: _normalizeVisualTheme(json['visualTheme']),
      selectedModel: stringValue(json['selectedModel'], defaults.selectedModel),
      isThinkingMode: boolValue(json['isThinkingMode']),
      isArtifactMode: boolValue(json['isArtifactMode']),
      userName: stringValue(json['userName'], defaults.userName),
      geminiApiKey: stringValue(json['geminiApiKey']),
      endpoints: mapList(
        json['endpoints'],
      ).map(EndpointConfig.fromJson).toList().ifEmpty(defaults.endpoints),
      genSettings: GenerationSettings.fromJson(
        json['genSettings'] is Map
            ? Map<String, dynamic>.from(json['genSettings'])
            : null,
      ),
      voiceSettings: VoiceSettings.fromJson(
        json['voiceSettings'] is Map
            ? Map<String, dynamic>.from(json['voiceSettings'])
            : null,
      ),
      sessions: sessions.isEmpty ? defaults.sessions : sessions,
      currentSessionId: stringValue(
        json['currentSessionId'],
        sessions.isEmpty ? defaults.currentSessionId : sessions.first.id,
      ),
      memories: mapList(json['memories']).map(Memory.fromJson).toList(),
      tokenUsageData: mapList(
        json['tokenUsageData'],
      ).map(TokenUsageRecord.fromJson).toList(),
      customCounters: mapList(
        json['customCounters'],
      ).map(CustomCounter.fromJson).toList(),
      soundEffectsEnabled: boolValue(json['soundEffectsEnabled'], true),
      isLiveVideoEnabled: boolValue(json['isLiveVideoEnabled']),
      isLiveFrontCamera: boolValue(json['isLiveFrontCamera']),
      savedAt: json['savedAt'] == null ? null : intValue(json['savedAt']),
    );
  }

  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
    'currentUser': currentUser?.toJson(),
    'authToken': includeSecrets ? authToken : '',
    'syncSettings': syncSettings.toJson(includePassword: includeSecrets),
    'language': languageCode(language),
    'theme': theme,
    'visualTheme': visualTheme,
    'selectedModel': selectedModel,
    'isThinkingMode': isThinkingMode,
    'isArtifactMode': isArtifactMode,
    'userName': userName,
    'geminiApiKey': includeSecrets ? geminiApiKey : '',
    'endpoints': endpoints
        .map(
          (item) =>
              includeSecrets ? item.toJson() : item.copyWith(key: '').toJson(),
        )
        .toList(),
    'genSettings': genSettings.toJson(),
    'voiceSettings': voiceSettings.toJson(),
    'sessions': sessions
        .map((item) => item.toJson())
        .toList(),
    'currentSessionId': currentSessionId,
    'memories': memories.map((item) => item.toJson()).toList(),
    'tokenUsageData': tokenUsageData.map((item) => item.toJson()).toList(),
    'customCounters': customCounters.map((item) => item.toJson()).toList(),
    'soundEffectsEnabled': soundEffectsEnabled,
    'isLiveVideoEnabled': isLiveVideoEnabled,
    'isLiveFrontCamera': isLiveFrontCamera,
    'savedAt': savedAt ?? DateTime.now().millisecondsSinceEpoch,
  };

  String encode({bool includeSecrets = true}) =>
      jsonEncode(toJson(includeSecrets: includeSecrets));
}

String _normalizeVisualTheme(Object? value) {
  final key = stringValue(value, 'default').trim().toLowerCase();
  return switch (key) {
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
}

extension _ListFallback<T> on List<T> {
  List<T> ifEmpty(List<T> fallback) => isEmpty ? fallback : this;
}
