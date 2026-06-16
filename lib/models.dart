import 'dart:convert';

import 'package:uuid/uuid.dart';

const _idGenerator = Uuid();

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

double doubleValue(Object? value, [double fallback = 0.0]) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
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

Map<String, int> _intMap(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value).map(
    (key, item) => MapEntry(key, intValue(item)),
  )..removeWhere((key, item) => key.trim().isEmpty || item <= 0);
}

Map<String, double> _doubleMap(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value).map(
    (key, item) => MapEntry(key, doubleValue(item)),
  )..removeWhere((key, item) => key.trim().isEmpty || item < 0);
}

enum ChatTargetType { model, agentServer }

ChatTargetType chatTargetTypeFromJson(Object? value) {
  final text = stringValue(value, 'model').trim().toLowerCase();
  return text == 'agent_server' || text == 'agentserver'
      ? ChatTargetType.agentServer
      : ChatTargetType.model;
}

String chatTargetTypeCode(ChatTargetType value) =>
    value == ChatTargetType.agentServer ? 'agent_server' : 'model';

enum ConnectorStatus {
  online,
  offline,
  authFailed,
  timeout,
  unknown,
  streamingFailed,
  syncFailed,
}

ConnectorStatus connectorStatusFromJson(Object? value) {
  final text = stringValue(value, 'unknown').trim().toLowerCase();
  return switch (text) {
    'online' => ConnectorStatus.online,
    'offline' => ConnectorStatus.offline,
    'auth_failed' || 'authfailed' => ConnectorStatus.authFailed,
    'timeout' => ConnectorStatus.timeout,
    'streaming_failed' || 'streamingfailed' => ConnectorStatus.streamingFailed,
    'sync_failed' || 'syncfailed' => ConnectorStatus.syncFailed,
    _ => ConnectorStatus.unknown,
  };
}

String connectorStatusCode(ConnectorStatus value) => switch (value) {
  ConnectorStatus.online => 'online',
  ConnectorStatus.offline => 'offline',
  ConnectorStatus.authFailed => 'auth_failed',
  ConnectorStatus.timeout => 'timeout',
  ConnectorStatus.streamingFailed => 'streaming_failed',
  ConnectorStatus.syncFailed => 'sync_failed',
  ConnectorStatus.unknown => 'unknown',
};

String connectorStatusLabel(ConnectorStatus value) => switch (value) {
  ConnectorStatus.online => 'Online',
  ConnectorStatus.offline => 'Offline',
  ConnectorStatus.authFailed => 'Auth failed',
  ConnectorStatus.timeout => 'Timeout',
  ConnectorStatus.streamingFailed => 'Streaming failed',
  ConnectorStatus.syncFailed => 'Sync failed',
  ConnectorStatus.unknown => 'Unknown',
};

enum ConnectorType { openclawGateway, hermesAgent, genericOpenAiCompatible }

ConnectorType connectorTypeFromJson(Object? value) {
  final text = stringValue(
    value,
    'generic_openai_compatible',
  ).trim().toLowerCase();
  return switch (text) {
    'openclaw_gateway' || 'openclaw' => ConnectorType.openclawGateway,
    'hermes_agent' || 'hermes' => ConnectorType.hermesAgent,
    _ => ConnectorType.genericOpenAiCompatible,
  };
}

String connectorTypeCode(ConnectorType value) => switch (value) {
  ConnectorType.openclawGateway => 'openclaw_gateway',
  ConnectorType.hermesAgent => 'hermes_agent',
  ConnectorType.genericOpenAiCompatible => 'generic_openai_compatible',
};

String connectorTypeLabel(ConnectorType value) => switch (value) {
  ConnectorType.openclawGateway => 'OpenClaw',
  ConnectorType.hermesAgent => 'Hermes',
  ConnectorType.genericOpenAiCompatible => 'OpenAI Compatible',
};

enum ToolPermissionMode {
  toolsDisabled,
  safeAuto,
  askBeforeWrite,
  askBeforeEveryTool,
}

ToolPermissionMode toolPermissionModeFromJson(Object? value) {
  final text = stringValue(value, 'ask_before_write').trim().toLowerCase();
  return switch (text) {
    'tools_disabled' || 'disabled' => ToolPermissionMode.toolsDisabled,
    'safe_auto' || 'safe' => ToolPermissionMode.safeAuto,
    'ask_before_every_tool' ||
    'ask_every' => ToolPermissionMode.askBeforeEveryTool,
    _ => ToolPermissionMode.askBeforeWrite,
  };
}

String toolPermissionModeCode(ToolPermissionMode value) => switch (value) {
  ToolPermissionMode.toolsDisabled => 'tools_disabled',
  ToolPermissionMode.safeAuto => 'safe_auto',
  ToolPermissionMode.askBeforeWrite => 'ask_before_write',
  ToolPermissionMode.askBeforeEveryTool => 'ask_before_every_tool',
};

String toolPermissionModeLabel(ToolPermissionMode value) => switch (value) {
  ToolPermissionMode.toolsDisabled => 'Tools disabled',
  ToolPermissionMode.safeAuto => 'Safe auto',
  ToolPermissionMode.askBeforeWrite => 'Ask before write',
  ToolPermissionMode.askBeforeEveryTool => 'Ask before every tool',
};

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
    this.targetId,
    this.targetType,
    this.targetName,
    this.connectorId,
    this.modelOrAgentId,
    this.toolEventIds = const [],
    this.isEstimatedTokenCount = true,
    this.generationTimeMs,
  });

  final String id;
  final String text;
  final String sender;
  final String timestamp;
  final String? model;
  final List<AttachmentData> attachments;
  final int? tokenCount;
  final String? targetId;
  final ChatTargetType? targetType;
  final String? targetName;
  final String? connectorId;
  final String? modelOrAgentId;
  final List<String> toolEventIds;
  final bool isEstimatedTokenCount;
  final int? generationTimeMs;

  bool get isUser => sender == 'user';
  bool get isSystem => sender == 'system';

  Message copyWith({
    String? text,
    String? sender,
    String? timestamp,
    String? model,
    List<AttachmentData>? attachments,
    int? tokenCount,
    String? targetId,
    ChatTargetType? targetType,
    String? targetName,
    String? connectorId,
    String? modelOrAgentId,
    List<String>? toolEventIds,
    bool? isEstimatedTokenCount,
    int? generationTimeMs,
    bool clearModel = false,
    bool clearTokenCount = false,
    bool clearTarget = false,
  }) {
    return Message(
      id: id,
      text: text ?? this.text,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      model: clearModel ? null : model ?? this.model,
      attachments: attachments ?? this.attachments,
      tokenCount: clearTokenCount ? null : tokenCount ?? this.tokenCount,
      targetId: clearTarget ? null : targetId ?? this.targetId,
      targetType: clearTarget ? null : targetType ?? this.targetType,
      targetName: clearTarget ? null : targetName ?? this.targetName,
      connectorId: clearTarget ? null : connectorId ?? this.connectorId,
      modelOrAgentId: clearTarget
          ? null
          : modelOrAgentId ?? this.modelOrAgentId,
      toolEventIds: clearTarget ? const [] : toolEventIds ?? this.toolEventIds,
      isEstimatedTokenCount: isEstimatedTokenCount ?? this.isEstimatedTokenCount,
      generationTimeMs: generationTimeMs ?? this.generationTimeMs,
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
      targetId: json['target_id'] == null && json['targetId'] == null
          ? null
          : stringValue(json['target_id'], stringValue(json['targetId'])),
      targetType: json['target_type'] == null && json['targetType'] == null
          ? null
          : chatTargetTypeFromJson(json['target_type'] ?? json['targetType']),
      targetName: json['target_name'] == null && json['targetName'] == null
          ? null
          : stringValue(json['target_name'], stringValue(json['targetName'])),
      connectorId: json['connector_id'] == null && json['connectorId'] == null
          ? null
          : stringValue(json['connector_id'], stringValue(json['connectorId'])),
      modelOrAgentId:
          json['model_or_agent_id'] == null && json['modelOrAgentId'] == null
          ? null
          : stringValue(
              json['model_or_agent_id'],
              stringValue(json['modelOrAgentId']),
            ),
      toolEventIds: (json['tool_event_ids'] is List)
          ? (json['tool_event_ids'] as List)
                .map((item) => item.toString())
                .toList()
          : (json['toolEventIds'] is List)
          ? (json['toolEventIds'] as List)
                .map((item) => item.toString())
                .toList()
          : const [],
      isEstimatedTokenCount: json.containsKey('isEstimatedTokenCount') 
          ? json['isEstimatedTokenCount'] == true 
          : true,
      generationTimeMs: json['generationTimeMs'] != null ? intValue(json['generationTimeMs']) : null,
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
    if (targetId != null) 'target_id': targetId,
    if (targetType != null) 'target_type': chatTargetTypeCode(targetType!),
    if (targetName != null) 'target_name': targetName,
    if (connectorId != null) 'connector_id': connectorId,
    if (modelOrAgentId != null) 'model_or_agent_id': modelOrAgentId,
    if (toolEventIds.isNotEmpty) 'tool_event_ids': toolEventIds,
    'isEstimatedTokenCount': isEstimatedTokenCount,
    if (generationTimeMs != null) 'generationTimeMs': generationTimeMs,
  };
}

class Session {
  const Session({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.deleted = false,
    this.currentTargetId = '',
    this.startedWithTargetId = '',
    this.lastTargetId = '',
    this.targetHistory = const [],
    this.handoffSummary = '',
    this.targetSwitchEvents = const [],
  });

  final String id;
  final String title;
  final List<Message> messages;
  final int createdAt;
  final int updatedAt;
  final bool pinned;
  final bool deleted;
  final String currentTargetId;
  final String startedWithTargetId;
  final String lastTargetId;
  final List<String> targetHistory;
  final String handoffSummary;
  final List<TargetSwitchEvent> targetSwitchEvents;

  Session copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    int? createdAt,
    int? updatedAt,
    bool? pinned,
    bool? deleted,
    String? currentTargetId,
    String? startedWithTargetId,
    String? lastTargetId,
    List<String>? targetHistory,
    String? handoffSummary,
    List<TargetSwitchEvent>? targetSwitchEvents,
  }) {
    return Session(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pinned: pinned ?? this.pinned,
      deleted: deleted ?? this.deleted,
      currentTargetId: currentTargetId ?? this.currentTargetId,
      startedWithTargetId: startedWithTargetId ?? this.startedWithTargetId,
      lastTargetId: lastTargetId ?? this.lastTargetId,
      targetHistory: targetHistory ?? this.targetHistory,
      handoffSummary: handoffSummary ?? this.handoffSummary,
      targetSwitchEvents: targetSwitchEvents ?? this.targetSwitchEvents,
    );
  }

  factory Session.empty([String? id, String? targetId]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveTargetId = targetId ?? '';
    return Session(
      id: id ?? 'session-${_idGenerator.v4()}',
      title: effectiveTargetId.startsWith('agent:')
          ? 'New Agent Chat'
          : 'New Chat',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      currentTargetId: effectiveTargetId,
      startedWithTargetId: effectiveTargetId,
      lastTargetId: effectiveTargetId,
      targetHistory: effectiveTargetId.isEmpty ? const [] : [effectiveTargetId],
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    final updatedAt = intValue(
      json['updatedAt'],
      DateTime.now().millisecondsSinceEpoch,
    );
    final currentTargetId = stringValue(
      json['current_target_id'],
      stringValue(json['currentTargetId']),
    );
    final startedWithTargetId = stringValue(
      json['started_with_target_id'],
      stringValue(json['startedWithTargetId'], currentTargetId),
    );
    final lastTargetId = stringValue(
      json['last_target_id'],
      stringValue(json['lastTargetId'], currentTargetId),
    );
    final targetHistory = (json['target_history'] is List)
        ? (json['target_history'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList()
        : (json['targetHistory'] is List)
        ? (json['targetHistory'] as List)
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    return Session(
      id: stringValue(json['id']),
      title: stringValue(json['title'], 'New Chat'),
      messages: mapList(json['messages']).map(Message.fromJson).toList(),
      createdAt: intValue(
        json['createdAt'],
        intValue(json['created_at'], updatedAt),
      ),
      updatedAt: updatedAt,
      pinned: boolValue(json['pinned']),
      deleted: boolValue(json['deleted']),
      currentTargetId: currentTargetId,
      startedWithTargetId: startedWithTargetId,
      lastTargetId: lastTargetId,
      targetHistory: targetHistory,
      handoffSummary: stringValue(
        json['handoff_summary'],
        stringValue(json['handoffSummary']),
      ),
      targetSwitchEvents: mapList(
        json['target_switch_events'] ?? json['targetSwitchEvents'],
      ).map(TargetSwitchEvent.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((item) => item.toJson()).toList(),
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    if (pinned) 'pinned': pinned,
    if (deleted) 'deleted': deleted,
    if (currentTargetId.isNotEmpty) 'current_target_id': currentTargetId,
    if (startedWithTargetId.isNotEmpty)
      'started_with_target_id': startedWithTargetId,
    if (lastTargetId.isNotEmpty) 'last_target_id': lastTargetId,
    if (targetHistory.isNotEmpty) 'target_history': targetHistory,
    if (handoffSummary.isNotEmpty) 'handoff_summary': handoffSummary,
    if (targetSwitchEvents.isNotEmpty)
      'target_switch_events': targetSwitchEvents
          .map((event) => event.toJson())
          .toList(),
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
    this.enabled = true,
  });

  final String id;
  final String url;
  final String key;
  final String name;
  final bool skipModelFetch;
  final List<String> models;
  final bool enabled;

  EndpointConfig copyWith({
    String? id,
    String? url,
    String? key,
    String? name,
    bool? skipModelFetch,
    List<String>? models,
    bool? enabled,
  }) {
    return EndpointConfig(
      id: id ?? this.id,
      url: url ?? this.url,
      key: key ?? this.key,
      name: name ?? this.name,
      skipModelFetch: skipModelFetch ?? this.skipModelFetch,
      models: models ?? this.models,
      enabled: enabled ?? this.enabled,
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
      enabled: json['enabled'] == null ? true : boolValue(json['enabled']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'key': key,
    'name': name,
    'skipModelFetch': skipModelFetch,
    'models': models,
    'enabled': enabled,
  };
}

class EndpointModel {
  const EndpointModel({required this.name, required this.endpointId});

  final String name;
  final String endpointId;
}

class ConnectorCapabilities {
  const ConnectorCapabilities({
    this.supportsStreaming = true,
    this.supportsChatCompletions = true,
    this.supportsResponsesApi = false,
    this.supportsModelsEndpoint = true,
    this.supportsTools = false,
    this.rawCapabilitiesJson = const {},
  });

  final bool supportsStreaming;
  final bool supportsChatCompletions;
  final bool supportsResponsesApi;
  final bool supportsModelsEndpoint;
  final bool supportsTools;
  final Map<String, dynamic> rawCapabilitiesJson;

  ConnectorCapabilities copyWith({
    bool? supportsStreaming,
    bool? supportsChatCompletions,
    bool? supportsResponsesApi,
    bool? supportsModelsEndpoint,
    bool? supportsTools,
    Map<String, dynamic>? rawCapabilitiesJson,
  }) {
    return ConnectorCapabilities(
      supportsStreaming: supportsStreaming ?? this.supportsStreaming,
      supportsChatCompletions:
          supportsChatCompletions ?? this.supportsChatCompletions,
      supportsResponsesApi: supportsResponsesApi ?? this.supportsResponsesApi,
      supportsModelsEndpoint:
          supportsModelsEndpoint ?? this.supportsModelsEndpoint,
      supportsTools: supportsTools ?? this.supportsTools,
      rawCapabilitiesJson: rawCapabilitiesJson ?? this.rawCapabilitiesJson,
    );
  }

  factory ConnectorCapabilities.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConnectorCapabilities();
    return ConnectorCapabilities(
      supportsStreaming: boolValue(json['supports_streaming'], true),
      supportsChatCompletions: boolValue(
        json['supports_chat_completions'],
        true,
      ),
      supportsResponsesApi: boolValue(json['supports_responses_api']),
      supportsModelsEndpoint: boolValue(json['supports_models_endpoint'], true),
      supportsTools: boolValue(json['supports_tools']),
      rawCapabilitiesJson: json['raw_capabilities_json'] is Map
          ? Map<String, dynamic>.from(json['raw_capabilities_json'])
          : const {},
    );
  }

  Map<String, dynamic> toJson() => {
    'supports_streaming': supportsStreaming,
    'supports_chat_completions': supportsChatCompletions,
    'supports_responses_api': supportsResponsesApi,
    'supports_models_endpoint': supportsModelsEndpoint,
    'supports_tools': supportsTools,
    'raw_capabilities_json': rawCapabilitiesJson,
  };
}

class ConnectorTarget {
  const ConnectorTarget({
    required this.id,
    required this.connectorId,
    required this.modelId,
    required this.displayName,
    this.contextLength,
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String connectorId;
  final String modelId;
  final String displayName;
  final int? contextLength;
  final bool enabled;
  final int createdAt;
  final int updatedAt;

  ConnectorTarget copyWith({
    String? id,
    String? connectorId,
    String? modelId,
    String? displayName,
    int? contextLength,
    bool? enabled,
    int? createdAt,
    int? updatedAt,
  }) {
    return ConnectorTarget(
      id: id ?? this.id,
      connectorId: connectorId ?? this.connectorId,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      contextLength: contextLength ?? this.contextLength,
      enabled: enabled ?? this.enabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ConnectorTarget.fromJson(Map<String, dynamic> json) {
    final modelId = stringValue(json['model_id'], stringValue(json['modelId']));
    final now = DateTime.now().millisecondsSinceEpoch;
    final rawContextLength = json['context_length'] ?? json['contextLength'];
    final parsedContextLength = intValue(rawContextLength);
    return ConnectorTarget(
      id: stringValue(
        json['id'],
        '${stringValue(json['connector_id'], stringValue(json['connectorId']))}:$modelId',
      ),
      connectorId: stringValue(
        json['connector_id'],
        stringValue(json['connectorId']),
      ),
      modelId: modelId,
      displayName: stringValue(
        json['display_name'],
        stringValue(json['displayName'], modelId),
      ),
      contextLength: parsedContextLength > 0 ? parsedContextLength : null,
      enabled: boolValue(json['enabled'], true),
      createdAt: intValue(json['created_at'], intValue(json['createdAt'], now)),
      updatedAt: intValue(json['updated_at'], intValue(json['updatedAt'], now)),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'connector_id': connectorId,
    'model_id': modelId,
    'display_name': displayName,
    if (contextLength != null) 'context_length': contextLength,
    'enabled': enabled,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

class AgentConnector {
  const AgentConnector({
    required this.id,
    this.userId = '',
    required this.name,
    this.type = ConnectorType.genericOpenAiCompatible,
    this.baseUrl = '',
    this.encryptedApiKey = '',
    this.enabled = true,
    this.status = ConnectorStatus.unknown,
    this.latencyMs,
    this.lastCheckedAt,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.permissionMode = ToolPermissionMode.askBeforeWrite,
    this.capabilities = const ConnectorCapabilities(),
    this.targets = const [],
    this.lastError = '',
    this.logs = const [],
  });

  final String id;
  final String userId;
  final String name;
  final ConnectorType type;
  final String baseUrl;
  final String encryptedApiKey;
  final bool enabled;
  final ConnectorStatus status;
  final int? latencyMs;
  final int? lastCheckedAt;
  final bool isDefault;
  final int createdAt;
  final int updatedAt;
  final ToolPermissionMode permissionMode;
  final ConnectorCapabilities capabilities;
  final List<ConnectorTarget> targets;
  final String lastError;
  final List<String> logs;

  String get providerLabel => connectorTypeLabel(type);

  AgentConnector copyWith({
    String? id,
    String? userId,
    String? name,
    ConnectorType? type,
    String? baseUrl,
    String? encryptedApiKey,
    bool? enabled,
    ConnectorStatus? status,
    int? latencyMs,
    int? lastCheckedAt,
    bool? isDefault,
    int? createdAt,
    int? updatedAt,
    ToolPermissionMode? permissionMode,
    ConnectorCapabilities? capabilities,
    List<ConnectorTarget>? targets,
    String? lastError,
    List<String>? logs,
    bool clearLatency = false,
    bool clearLastCheckedAt = false,
  }) {
    return AgentConnector(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      type: type ?? this.type,
      baseUrl: baseUrl ?? this.baseUrl,
      encryptedApiKey: encryptedApiKey ?? this.encryptedApiKey,
      enabled: enabled ?? this.enabled,
      status: status ?? this.status,
      latencyMs: clearLatency ? null : latencyMs ?? this.latencyMs,
      lastCheckedAt: clearLastCheckedAt
          ? null
          : lastCheckedAt ?? this.lastCheckedAt,
      isDefault: isDefault ?? this.isDefault,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      permissionMode: permissionMode ?? this.permissionMode,
      capabilities: capabilities ?? this.capabilities,
      targets: targets ?? this.targets,
      lastError: lastError ?? this.lastError,
      logs: logs ?? this.logs,
    );
  }

  factory AgentConnector.empty({String? id}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final connectorId = id ?? now.toString();
    return AgentConnector(
      id: connectorId,
      name: 'New Agent Server',
      createdAt: now,
      updatedAt: now,
    );
  }

  factory AgentConnector.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = stringValue(json['id']);
    return AgentConnector(
      id: id,
      userId: stringValue(json['user_id'], stringValue(json['userId'])),
      name: stringValue(json['name'], 'Agent Server'),
      type: connectorTypeFromJson(json['type']),
      baseUrl: stringValue(json['base_url'], stringValue(json['baseUrl'])),
      encryptedApiKey: stringValue(
        json['encrypted_api_key'],
        stringValue(json['encryptedApiKey'], stringValue(json['apiKey'])),
      ),
      enabled: boolValue(json['enabled'], true),
      status: connectorStatusFromJson(json['status']),
      latencyMs: json['latency_ms'] == null && json['latencyMs'] == null
          ? null
          : intValue(json['latency_ms'], intValue(json['latencyMs'])),
      lastCheckedAt:
          json['last_checked_at'] == null && json['lastCheckedAt'] == null
          ? null
          : intValue(json['last_checked_at'], intValue(json['lastCheckedAt'])),
      isDefault: boolValue(json['is_default'], boolValue(json['isDefault'])),
      createdAt: intValue(json['created_at'], intValue(json['createdAt'], now)),
      updatedAt: intValue(json['updated_at'], intValue(json['updatedAt'], now)),
      permissionMode: toolPermissionModeFromJson(json['permission_mode']),
      capabilities: ConnectorCapabilities.fromJson(
        json['capabilities'] is Map
            ? Map<String, dynamic>.from(json['capabilities'])
            : null,
      ),
      targets: mapList(json['targets'])
          .map(ConnectorTarget.fromJson)
          .map(
            (target) => target.connectorId.isEmpty
                ? target.copyWith(connectorId: id)
                : target,
          )
          .toList(),
      lastError: stringValue(
        json['last_error'],
        stringValue(json['lastError']),
      ),
      logs: (json['logs'] is List)
          ? (json['logs'] as List).map((item) => item.toString()).toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson({bool includeSecrets = true}) => {
    'id': id,
    'user_id': userId,
    'name': name,
    'type': connectorTypeCode(type),
    'base_url': baseUrl,
    'encrypted_api_key': includeSecrets ? encryptedApiKey : '',
    'enabled': enabled,
    'status': connectorStatusCode(status),
    if (latencyMs != null) 'latency_ms': latencyMs,
    if (lastCheckedAt != null) 'last_checked_at': lastCheckedAt,
    'is_default': isDefault,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'permission_mode': toolPermissionModeCode(permissionMode),
    'capabilities': capabilities.toJson(),
    'targets': targets.map((target) => target.toJson()).toList(),
    if (lastError.isNotEmpty) 'last_error': lastError,
    if (logs.isNotEmpty) 'logs': logs,
  };
}

class ChatTarget {
  const ChatTarget({
    required this.id,
    required this.type,
    required this.displayName,
    required this.provider,
    this.connectorId,
    this.modelId,
    this.contextLength,
    this.status = ConnectorStatus.online,
    this.capabilities = const ConnectorCapabilities(),
    this.isDefault = false,
  });

  final String id;
  final ChatTargetType type;
  final String displayName;
  final String provider;
  final String? connectorId;
  final String? modelId;
  final int? contextLength;
  final ConnectorStatus status;
  final ConnectorCapabilities capabilities;
  final bool isDefault;

  bool get isModel => type == ChatTargetType.model;
  bool get isAgentServer => type == ChatTargetType.agentServer;

  factory ChatTarget.model(String model, {String provider = 'Model'}) {
    return ChatTarget(
      id: 'model:$model',
      type: ChatTargetType.model,
      displayName: model,
      provider: provider,
      modelId: model,
    );
  }

  factory ChatTarget.agent({
    required AgentConnector connector,
    ConnectorTarget? target,
  }) {
    final enabledTargets = connector.targets
        .where((item) => item.enabled)
        .toList();
    final selectedTarget =
        target ?? (enabledTargets.isEmpty ? null : enabledTargets.first);
    final modelId =
        selectedTarget?.modelId ??
        connector.name.toLowerCase().replaceAll(' ', '-');
    return ChatTarget(
      id: 'agent:${connector.id}',
      type: ChatTargetType.agentServer,
      displayName: connector.name,
      provider: connector.providerLabel,
      connectorId: connector.id,
      modelId: modelId,
      contextLength: selectedTarget?.contextLength,
      status: connector.status,
      capabilities: connector.capabilities,
      isDefault: connector.isDefault,
    );
  }
}

class TargetSwitchEvent {
  const TargetSwitchEvent({
    required this.id,
    required this.chatId,
    required this.fromTargetId,
    required this.toTargetId,
    required this.handoffSummary,
    required this.createdAt,
  });

  final String id;
  final String chatId;
  final String fromTargetId;
  final String toTargetId;
  final String handoffSummary;
  final int createdAt;

  factory TargetSwitchEvent.fromJson(Map<String, dynamic> json) {
    return TargetSwitchEvent(
      id: stringValue(json['id']),
      chatId: stringValue(json['chat_id'], stringValue(json['chatId'])),
      fromTargetId: stringValue(
        json['from_target_id'],
        stringValue(json['fromTargetId']),
      ),
      toTargetId: stringValue(
        json['to_target_id'],
        stringValue(json['toTargetId']),
      ),
      handoffSummary: stringValue(
        json['handoff_summary'],
        stringValue(json['handoffSummary']),
      ),
      createdAt: intValue(json['created_at'], intValue(json['createdAt'])),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'chat_id': chatId,
    'from_target_id': fromTargetId,
    'to_target_id': toTargetId,
    'handoff_summary': handoffSummary,
    'created_at': createdAt,
  };
}

class GenerationSettings {
  const GenerationSettings({
    this.memoryEnabled = true,
    this.webSearchMode = 'auto',
    this.webSearchEngine = 'gemini',
    this.webSearchProvider = 'gemini',
    this.webSearchModel = 'gemini-flash-lite-latest',
    this.webSearchEndpointId = '',
    this.googleSearchApiKey = '',
    this.googleSearchCx = '',
    this.tavilyApiKey = '',
    this.mistralApiKey = '',
    this.mistralAgentId = '',
    this.hapticStreamingEnabled = false,
    this.titleModelEnabled = true,
    this.titleModel = '',
    this.voiceModel = 'gemini-2.0-flash-exp',
    this.liveModeEnabled = true,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.maxOutputTokens = 8192,
    this.contextLimit = 128000,
  });

  final bool memoryEnabled;
  final String webSearchMode;
  final String webSearchEngine;
  final String webSearchProvider;
  final String webSearchModel;
  final String webSearchEndpointId;
  final String googleSearchApiKey;
  final String googleSearchCx;
  final String tavilyApiKey;
  final String mistralApiKey;
  final String mistralAgentId;
  final bool hapticStreamingEnabled;
  final bool titleModelEnabled;
  final String titleModel;
  final String voiceModel;
  final bool liveModeEnabled;
  final double temperature;
  final double topP;
  final int topK;
  final int maxOutputTokens;
  final int contextLimit;

  GenerationSettings copyWith({
    bool? memoryEnabled,
    String? webSearchMode,
    String? webSearchEngine,
    String? webSearchProvider,
    String? webSearchModel,
    String? webSearchEndpointId,
    String? googleSearchApiKey,
    String? googleSearchCx,
    String? tavilyApiKey,
    String? mistralApiKey,
    String? mistralAgentId,
    bool? hapticStreamingEnabled,
    bool? titleModelEnabled,
    String? titleModel,
    String? voiceModel,
    bool? liveModeEnabled,
    double? temperature,
    double? topP,
    int? topK,
    int? maxOutputTokens,
    int? contextLimit,
  }) {
    final nextEngine = webSearchEngine ?? this.webSearchEngine;
    return GenerationSettings(
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
      mistralApiKey: mistralApiKey ?? this.mistralApiKey,
      mistralAgentId: mistralAgentId ?? this.mistralAgentId,
      hapticStreamingEnabled:
          hapticStreamingEnabled ?? this.hapticStreamingEnabled,
      titleModelEnabled: titleModelEnabled ?? this.titleModelEnabled,
      titleModel: titleModel ?? this.titleModel,
      voiceModel: voiceModel ?? this.voiceModel,
      liveModeEnabled: liveModeEnabled ?? this.liveModeEnabled,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      contextLimit: contextLimit ?? this.contextLimit,
    );
  }

  factory GenerationSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GenerationSettings();
    final engine = stringValue(
      json['webSearchEngine'],
      json['webSearchProvider'] == 'endpoint' ? 'endpoint' : 'gemini',
    );
    return GenerationSettings(
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
      mistralApiKey: stringValue(json['mistralApiKey']),
      mistralAgentId: stringValue(json['mistralAgentId']),
      hapticStreamingEnabled: boolValue(json['hapticStreamingEnabled']),
      titleModelEnabled: json['titleModelEnabled'] ?? true,
      titleModel: stringValue(json['titleModel']),
      voiceModel: stringValue(json['voiceModel'], 'gemini-2.0-flash-exp'),
      liveModeEnabled: json['liveModeEnabled'] ?? true,
      temperature: doubleValue(json['temperature'], 0.7),
      topP: doubleValue(json['topP'], 0.9),
      topK: intValue(json['topK'], 40),
      maxOutputTokens: intValue(json['maxOutputTokens'], 8192),
      contextLimit: intValue(json['contextLimit'], 128000),
    );
  }

  Map<String, dynamic> toJson() => {
    'memoryEnabled': memoryEnabled,
    'webSearchMode': webSearchMode,
    'webSearchEngine': webSearchEngine,
    'webSearchProvider': webSearchProvider,
    'webSearchModel': webSearchModel,
    'webSearchEndpointId': webSearchEndpointId,
    'googleSearchApiKey': googleSearchApiKey,
    'googleSearchCx': googleSearchCx,
    'tavilyApiKey': tavilyApiKey,
    'mistralApiKey': mistralApiKey,
    'mistralAgentId': mistralAgentId,
    'hapticStreamingEnabled': hapticStreamingEnabled,
    'titleModelEnabled': titleModelEnabled,
    'titleModel': titleModel,
    'voiceModel': voiceModel,
    'liveModeEnabled': liveModeEnabled,
    'temperature': temperature,
    'topP': topP,
    'topK': topK,
    'maxOutputTokens': maxOutputTokens,
    'contextLimit': contextLimit,
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
    this.liveModel = '',
    this.customTextPersonalities = const [],
  });

  final String voice;
  final String personality;
  final String customPersonality;
  final String textPersonality;
  final String customTextPersonality;
  final List<CustomPersonality> customVoicePersonalities;
  final List<CustomPersonality> customTextPersonalities;
  final String liveModel;

  VoiceSettings copyWith({
    String? voice,
    String? personality,
    String? customPersonality,
    String? textPersonality,
    String? customTextPersonality,
    List<CustomPersonality>? customVoicePersonalities,
    List<CustomPersonality>? customTextPersonalities,
    String? liveModel,
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
      liveModel: liveModel ?? this.liveModel,
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
      liveModel: stringValue(json['liveModel']),
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
    'liveModel': liveModel,
  };
}

class Memory {
  const Memory({
    required this.id,
    required this.content,
    required this.timestamp,
    this.key = '',
    this.type = 'preference',
    this.scope = 'global',
    this.sensitivity = 'low',
  });

  final String id;
  final String content;
  final int timestamp;
  final String key;
  final String type;
  final String scope;
  final String sensitivity;

  Memory copyWith({
    String? content,
    int? timestamp,
    String? key,
    String? type,
    String? scope,
    String? sensitivity,
  }) => Memory(
    id: id,
    content: content ?? this.content,
    timestamp: timestamp ?? this.timestamp,
    key: key ?? this.key,
    type: type ?? this.type,
    scope: scope ?? this.scope,
    sensitivity: sensitivity ?? this.sensitivity,
  );

  factory Memory.fromJson(Map<String, dynamic> json) {
    final content = stringValue(json['content']);
    return Memory(
      id: stringValue(json['id']),
      content: content,
      timestamp: intValue(json['timestamp']),
      key: stringValue(json['key'], inferKey(content)),
      type: stringValue(json['type'], 'preference'),
      scope: stringValue(json['scope'], 'global'),
      sensitivity: stringValue(json['sensitivity'], 'low'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'timestamp': timestamp,
    if (key.isNotEmpty) 'key': key,
    if (type.isNotEmpty) 'type': type,
    if (scope.isNotEmpty) 'scope': scope,
    if (sensitivity.isNotEmpty) 'sensitivity': sensitivity,
  };

  static String inferKey(String content) {
    final value = content
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (value.contains('name is') || value.contains('named')) {
      return 'user_name';
    }
    if (value.contains('nickname') || value.contains('call user')) {
      return 'nickname';
    }
    if (RegExp(r'\b(dog|dogs|cat|cats|pet|pets)\b').hasMatch(value)) {
      return 'pets';
    }
    if (value.contains('language') || value.contains('indonesian')) {
      return 'preferred_language';
    }
    if (value.contains('tone') ||
        value.contains('verbose') ||
        value.contains('concise') ||
        value.contains('casual')) {
      return 'preferred_tone';
    }
    if (value.contains('flutter') || value.contains('react')) {
      return 'preferred_framework';
    }
    if (value.contains('project') || value.contains('app')) {
      return 'project_requirement';
    }
    return '';
  }
}

class TokenUsageRecord {
  const TokenUsageRecord({
    required this.timestamp,
    required this.model,
    required this.endpoint,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    this.cachedInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.sessionId,
    this.isEstimated = true,
  });

  final int timestamp;
  final String model;
  final String endpoint;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int cachedInputTokens;
  final int cacheCreationInputTokens;
  final String? sessionId;
  final bool isEstimated;

  factory TokenUsageRecord.fromJson(Map<String, dynamic> json) {
    return TokenUsageRecord(
      timestamp: intValue(json['timestamp']),
      model: stringValue(json['model']),
      endpoint: stringValue(json['endpoint']),
      inputTokens: intValue(json['inputTokens']),
      outputTokens: intValue(json['outputTokens']),
      totalTokens: intValue(json['totalTokens']),
      cachedInputTokens: intValue(
        json['cachedInputTokens'] ?? json['cached_input_tokens'],
      ),
      cacheCreationInputTokens: intValue(
        json['cacheCreationInputTokens'] ?? json['cache_creation_input_tokens'],
      ),
      sessionId: stringValue(json['sessionId']),
      isEstimated: json.containsKey('isEstimated') 
          ? json['isEstimated'] == true 
          : true,
    );
  }

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'model': model,
    'endpoint': endpoint,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
    if (cachedInputTokens > 0) 'cachedInputTokens': cachedInputTokens,
    if (cacheCreationInputTokens > 0)
      'cacheCreationInputTokens': cacheCreationInputTokens,
    if (sessionId != null) 'sessionId': sessionId,
    'isEstimated': isEstimated,
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
    this.useSupabase = false,
    this.supabaseUrl = 'https://supabase.alids.app',
    this.supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE3ODE0MjkzOTMsImV4cCI6MjA4Mjc1ODQwMH0.qgQ3hxL9JgRhZ-0vuIAG-myu8w5UeWkG1iNrsjqDvR0',
  });

  final bool enabled;
  final String apiBaseUrl;
  final DatabaseSettings database;
  final List<DatabaseSettings> backupDatabases;
  final bool autoSyncBackups;
  final bool useSupabase;
  final String supabaseUrl;
  final String supabaseAnonKey;

  SyncSettings copyWith({
    bool? enabled,
    String? apiBaseUrl,
    DatabaseSettings? database,
    List<DatabaseSettings>? backupDatabases,
    bool? autoSyncBackups,
    bool? useSupabase,
    String? supabaseUrl,
    String? supabaseAnonKey,
  }) {
    return SyncSettings(
      enabled: enabled ?? this.enabled,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      database: database ?? this.database,
      backupDatabases: backupDatabases ?? this.backupDatabases,
      autoSyncBackups: autoSyncBackups ?? this.autoSyncBackups,
      useSupabase: useSupabase ?? this.useSupabase,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseAnonKey: supabaseAnonKey ?? this.supabaseAnonKey,
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
      useSupabase: boolValue(json['useSupabase']),
      supabaseUrl: stringValue(json['supabaseUrl']),
      supabaseAnonKey: stringValue(json['supabaseAnonKey']),
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
    'useSupabase': useSupabase,
    'supabaseUrl': supabaseUrl,
    if (includePassword) 'supabaseAnonKey': supabaseAnonKey,
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
    required this.selectedTargetId,
    required this.isThinkingMode,
    required this.isArtifactMode,
    required this.userName,
    required this.geminiApiKey,
    required this.endpoints,
    required this.agentConnectors,
    required this.modelContextOverrides,
    required this.modelInputCosts,
    required this.modelOutputCosts,
    required this.modelCacheHitCosts,
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
    this.cachedPasswordHash,
    this.lastSyncAt,
    this.savedAt,
  });

  final UserAccount? currentUser;
  final String authToken;
  final SyncSettings syncSettings;
  final AppLanguage language;
  final String theme;
  final String visualTheme;
  final String selectedModel;
  final String selectedTargetId;
  final bool isThinkingMode;
  final bool isArtifactMode;
  final String userName;
  final String geminiApiKey;
  final List<EndpointConfig> endpoints;
  final List<AgentConnector> agentConnectors;
  final Map<String, int> modelContextOverrides;
  final Map<String, double> modelInputCosts;
  final Map<String, double> modelOutputCosts;
  final Map<String, double> modelCacheHitCosts;
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
  final String? cachedPasswordHash;
  final int? lastSyncAt;
  final int? savedAt;

  factory PersistedAppState.defaults() {
    final session = Session.empty();
    return PersistedAppState(
      currentUser: null,
      authToken: '',
      syncSettings: const SyncSettings(),
      language: AppLanguage.id,
      theme: 'dark',
      visualTheme: 'default',
      selectedModel: 'gemini-2.5-flash',
      selectedTargetId: 'model:gemini-2.5-flash',
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
      agentConnectors: const [],
      modelContextOverrides: const {},
      modelInputCosts: const {},
      modelOutputCosts: const {},
      modelCacheHitCosts: const {},
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
      lastSyncAt: null,
    );
  }

  factory PersistedAppState.fromJson(
    Map<String, dynamic> json, {
    bool allowEmptySessions = false,
  }) {
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
      selectedTargetId: stringValue(
        json['selectedTargetId'],
        stringValue(json['selected_target_id'], ''),
      ),
      isThinkingMode: boolValue(json['isThinkingMode']),
      isArtifactMode: boolValue(json['isArtifactMode']),
      userName: stringValue(json['userName'], defaults.userName),
      geminiApiKey: stringValue(json['geminiApiKey']),
      endpoints: mapList(
        json['endpoints'],
      ).map(EndpointConfig.fromJson).toList().ifEmpty(defaults.endpoints),
      agentConnectors: mapList(
        json['agentConnectors'] ?? json['agent_connectors'],
      ).map(AgentConnector.fromJson).toList(),
      modelContextOverrides: _intMap(
        json['modelContextOverrides'] ?? json['model_context_overrides'],
      ),
      modelInputCosts: _doubleMap(json['modelInputCosts']),
      modelOutputCosts: _doubleMap(json['modelOutputCosts']),
      modelCacheHitCosts: _doubleMap(json['modelCacheHitCosts']),
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
      sessions: sessions.isEmpty && !allowEmptySessions
          ? defaults.sessions
          : sessions,
      currentSessionId: stringValue(
        json['currentSessionId'],
        sessions.isEmpty
            ? (allowEmptySessions ? '' : defaults.currentSessionId)
            : sessions.first.id,
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
      cachedPasswordHash: json['cachedPasswordHash'] as String?,
      lastSyncAt: json['lastSyncAt'] == null
          ? null
          : intValue(json['lastSyncAt']),
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
    'selectedTargetId': selectedTargetId,
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
    'agentConnectors': agentConnectors
        .map((item) => item.toJson(includeSecrets: includeSecrets))
        .toList(),
    'modelContextOverrides': modelContextOverrides,
    'modelInputCosts': modelInputCosts,
    'modelOutputCosts': modelOutputCosts,
    'modelCacheHitCosts': modelCacheHitCosts,
    'genSettings': genSettings.toJson(),
    'voiceSettings': voiceSettings.toJson(),
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'currentSessionId': currentSessionId,
    'memories': memories.map((item) => item.toJson()).toList(),
    'tokenUsageData': tokenUsageData.map((item) => item.toJson()).toList(),
    'customCounters': customCounters.map((item) => item.toJson()).toList(),
    'soundEffectsEnabled': soundEffectsEnabled,
    'isLiveVideoEnabled': isLiveVideoEnabled,
    'isLiveFrontCamera': isLiveFrontCamera,
    if (includeSecrets && cachedPasswordHash != null && cachedPasswordHash!.isNotEmpty) 'cachedPasswordHash': cachedPasswordHash,
    if (lastSyncAt != null) 'lastSyncAt': lastSyncAt,
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
