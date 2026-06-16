import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

typedef TextDelta = void Function(String text);
typedef StatusCallback = void Function(String status);

class GeneratedResponse {
  const GeneratedResponse({
    required this.text,
    required this.inputTokens,
    required this.outputTokens,
    required this.endpointName,
    this.cachedInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.isEstimated = true,
    this.generationTimeMs,
  });

  final String text;
  final int inputTokens;
  final int outputTokens;
  final String endpointName;
  final int cachedInputTokens;
  final int cacheCreationInputTokens;
  final bool isEstimated;
  final int? generationTimeMs;
}

class ModelCatalog {
  const ModelCatalog({
    required this.geminiModels,
    required this.endpointModels,
    this.warnings = const [],
  });

  final List<String> geminiModels;
  final List<EndpointModel> endpointModels;
  final List<String> warnings;

  List<String> combined() {
    final values = <String>[
      'gemini-2.5-flash',
      ...geminiModels,
      ...endpointModels.map((item) => item.name),
    ];
    return LinkedHashSetString(values).toList();
  }
}

class AiService {
  final _activeClients = <String, http.Client>{};
  final http.Client _globalClient = http.Client();

  void cancelGeneration(String generationId) {
    final client = _activeClients.remove(generationId);
    client?.close();
  }

  void dispose() {
    _globalClient.close();
    for (final client in _activeClients.values) {
      client.close();
    }
    _activeClients.clear();
  }

  static const _textPrompts = {
    'Assistant':
        'You are a highly efficient, polished, and helpful digital assistant. Provide clear, structured, and accurate information. Use Markdown for better readability when appropriate. Maintain a professional yet approachable writing style.',
    'Therapist':
        'You are an empathetic and supportive therapist. Provide thoughtful, reflective responses. Focus on validating the user feelings and offering gentle guidance for self-reflection. Use warm and patient language.',
    'Story teller':
        'You are a creative and descriptive storyteller. Use rich language, evocative imagery, and varied sentence structure to bring your narratives to life. Structure your stories with clear arcs and engaging hooks.',
    'Meditation':
        'You are a calm meditation guide. Use peaceful, mindfulness-focused language. Provide short, rhythmic instructions for relaxation and grounding.',
    'Doctor':
        'You are a professional and reassuring medical consultant. Provide precise, evidence-based, and clear explanations.',
    'Argumentative':
        'You are a sharp-witted debater. Challenge points with logic, evidence, and structured counter-arguments while remaining professional.',
    'Romantic':
        'You are a poetic and expressive companion. Use warm, affectionate, and artistic language.',
    'Conspiracy':
        'You are an intense and analytical investigator of hidden truths. Use an urgent, skeptical writing style.',
    'Natural human':
        'You are having a casual text conversation. Use informal language, contractions, and natural-sounding sentence structures.',
  };

  Future<ModelCatalog> fetchModels({
    required String geminiApiKey,
    required List<EndpointConfig> endpoints,
    required SyncSettings syncSettings,
  }) async {
    final geminiModels = <String>[];
    final warnings = <String>[];
    if (geminiApiKey.trim().isNotEmpty) {
      try {
        final uri = Uri.https(
          'generativelanguage.googleapis.com',
          '/v1beta/models',
          {'key': geminiApiKey.trim()},
        );
        final response = await _globalClient
            .get(uri)
            .timeout(const Duration(seconds: 10));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          final models = data['models'] is List
              ? data['models'] as List
              : const [];
          for (final item in models.whereType<Map>()) {
            final name = stringValue(item['name']).replaceFirst('models/', '');
            final methods = item['supportedGenerationMethods'];
            if (name.isNotEmpty &&
                (methods is! List ||
                    methods.contains('generateContent') ||
                    methods.contains('streamGenerateContent') ||
                    methods.contains('bidiGenerateContent'))) {
              geminiModels.add(name);
            }
          }
        }
      } catch (error) {
        warnings.add(
          'Gemini models could not be fetched: ${_cleanError(error)}',
        );
      }
    }
    if (geminiModels.isEmpty) {
      geminiModels.addAll(const [
        'gemini-2.0-flash',
        'gemini-1.5-pro',
        'gemini-1.5-flash',
      ]);
    }

    final endpointModels = <EndpointModel>[];
    for (final endpoint in endpoints) {
      if (endpoint.models.isNotEmpty) {
        endpointModels.addAll(
          endpoint.models.map(
            (model) => EndpointModel(name: model, endpointId: endpoint.id),
          ),
        );
      }
      if (endpoint.url.trim().isEmpty) {
        continue;
      }
      if (endpoint.skipModelFetch) {
        continue;
      }
      try {
        final headers = <String, String>{};
        if (endpoint.key.trim().isNotEmpty && endpoint.key != 'sk-...') {
          headers['Authorization'] = 'Bearer ${endpoint.key}';
        }
        final response = await _getWithProxyFallback(
          Uri.parse('${_endpointBase(endpoint.url)}/models'),
          headers,
          syncSettings,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body);
          endpointModels.addAll(
            _extractModels(data).map(
              (m) => EndpointModel(
                name: m['id'] as String,
                endpointId: endpoint.id,
              ),
            ),
          );
        } else {
          warnings.add(
            '${endpoint.name} model fetch failed (${response.statusCode}): ${_extractApiError(response.body, 'No response body.')}',
          );
        }
      } catch (error) {
        warnings.add(
          '${endpoint.name} model fetch failed: ${_cleanError(error)}',
        );
      }
    }

    final seen = <String>{};
    final endpointSeen = <String>{};
    return ModelCatalog(
      geminiModels: geminiModels.where((model) => seen.add(model)).toList(),
      endpointModels: endpointModels
          .where((model) => model.name.isNotEmpty)
          .where(
            (model) => endpointSeen.add('${model.endpointId}:${model.name}'),
          )
          .toList(),
      warnings: warnings,
    );
  }

  Future<List<Map<String, dynamic>>> fetchAvailableModelsForEndpoint({
    required EndpointConfig endpoint,
    required SyncSettings syncSettings,
  }) async {
    if (endpoint.url.trim().isEmpty) {
      throw Exception('Endpoint URL is empty.');
    }
    try {
      final headers = <String, String>{};
      if (endpoint.key.trim().isNotEmpty && endpoint.key != 'sk-...') {
        headers['Authorization'] = 'Bearer ${endpoint.key}';
      }
      final response = await _getWithProxyFallback(
        Uri.parse('${_endpointBase(endpoint.url)}/models'),
        headers,
        syncSettings,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return _extractModels(data);
      } else {
        throw Exception(
          'Fetch failed (${response.statusCode}): ${_extractApiError(response.body, 'No response body.')}',
        );
      }
    } catch (error) {
      throw Exception('Model fetch failed: ${_cleanError(error)}');
    }
  }

  Future<void> pingEndpoint({
    required EndpointConfig endpoint,
    required SyncSettings syncSettings,
  }) async {
    if (endpoint.url.trim().isEmpty) {
      throw Exception('Endpoint URL is empty.');
    }
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (endpoint.key.trim().isNotEmpty && endpoint.key != 'sk-...') {
      headers['Authorization'] = 'Bearer ${endpoint.key}';
    }
    final payload = {
      'model': endpoint.models.isNotEmpty
          ? endpoint.models.first
          : endpoint.name.toLowerCase().replaceAll(' ', '-'),
      'messages': [
        {'role': 'user', 'content': 'ping'},
      ],
      'max_tokens': 1,
    };
    final request =
        http.Request(
            'POST',
            Uri.parse('${_endpointBase(endpoint.url)}/chat/completions'),
          )
          ..headers.addAll(headers)
          ..body = jsonEncode(payload);

    final streamed = await _sendWithProxyFallback(_globalClient, request, syncSettings);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      // 400 Bad Request for an invalid model (like OpenClaw) proves the server is online
      if (streamed.statusCode == 400 && body.toLowerCase().contains('model')) {
        return;
      }
      throw Exception(
        _extractApiError(body, 'Ping failed (${streamed.statusCode})'),
      );
    }
  }

  Future<GeneratedResponse> sendMessage({
    required String prompt,
    required List<AttachmentData> attachments,
    required List<Message> history,
    required String selectedModel,
    required List<EndpointConfig> endpoints,
    required List<EndpointModel> endpointModels,
    int? contextLimit,
    required GenerationSettings genSettings,
    required VoiceSettings voiceSettings,
    required String geminiApiKey,
    required List<Memory> memories,
    required bool thinkingMode,
    required bool artifactMode,
    required SyncSettings syncSettings,
    required TextDelta onText,
    required StatusCallback onStatus,
    String? generationId,
  }) async {
    final client = http.Client();
    if (generationId != null) {
      _activeClients[generationId] = client;
    }
    
    try {
      final modelName = selectedModel.trim();
    final endpointModel = _resolveEndpointModel(
      modelName,
      endpoints,
      endpointModels,
    );
    final endpoint = endpointModel == null
        ? null
        : endpoints
              .where((item) => item.id == endpointModel.endpointId)
              .cast<EndpointConfig?>()
              .firstOrNull;

    var searchContext = '';
    final shouldSearch = await _shouldSearch(
      prompt,
      modelName,
      endpoint,
      genSettings,
      geminiApiKey,
    );
    if (shouldSearch) {
      try {
        searchContext = await _performSearch(
          prompt,
          genSettings,
          endpoints,
          endpointModels,
          geminiApiKey,
          syncSettings,
          onStatus,
        );
      } catch (error) {
        onStatus('${_cleanError(error)}. Answering without web results...');
      }
    }

    if (endpoint != null && endpoint.url.trim().isNotEmpty) {
      return await _sendEndpoint(
        client: client,
        prompt: prompt,
        attachments: attachments,
        history: history,
        selectedModel: modelName,
        endpoint: endpoint,
        searchContext: searchContext,
        voiceSettings: voiceSettings,
        memories: memories,
        thinkingMode: thinkingMode,
        artifactMode: artifactMode,
        syncSettings: syncSettings,
        contextLimit: contextLimit,
        onText: onText,
      );
    }

    return await _sendGemini(
      client: client,
      prompt: prompt,
      attachments: attachments,
      history: history,
      selectedModel: modelName,
      searchContext: searchContext,
      voiceSettings: voiceSettings,
      geminiApiKey: geminiApiKey,
      memories: memories,
      thinkingMode: thinkingMode,
      artifactMode: artifactMode,
      contextLimit: contextLimit,
      onText: onText,
    );
    } finally {
      if (generationId != null) {
        _activeClients.remove(generationId);
      }
      client.close();
    }
  }

  Future<String> generateTitle({
    required List<Message> messages,
    required String selectedModel,
    required List<EndpointConfig> endpoints,
    required List<EndpointModel> endpointModels,
    required String geminiApiKey,
    required SyncSettings syncSettings,
  }) async {
    final modelName = selectedModel.trim();
    if (modelName.isEmpty) {
      return _fallbackTitleFromMessages(
        messages.where((m) => m.text.trim().isNotEmpty).take(2).toList(),
      );
    }

    final titleMessages = messages
        .where((message) => message.text.trim().isNotEmpty)
        .take(2)
        .toList();
    final chatHistory = titleMessages
        .map(
          (m) =>
              '${m.isUser ? "User" : "Assistant"}: ${_cleanTitleMessageText(m.text)}',
        )
        .join('\n');
    final fallbackMessage = titleMessages
        .where((m) => m.isUser)
        .map((m) => m.text)
        .firstOrNull;
    final fallbackTitle = _fallbackTitleFromMessages(titleMessages);

    final titlePrompt =
        '''
### Task:
Generate a concise, 3-5 word title with an emoji summarizing the chat history.
### Guidelines:
- The title should clearly represent the main theme or subject of the conversation.
- Use emojis that enhance understanding of the topic, but avoid quotation marks or special formatting.
- Write the title in the chat's primary language; default to English if multilingual.
- Prioritize accuracy over excessive creativity; keep it clear and simple.
- Your entire response must consist solely of the JSON object, without any introductory or concluding text.
- The output must be a single, raw JSON object, without any markdown code fences or other encapsulating text.
- Ensure no conversational text, affirmations, or explanations precede or follow the raw JSON output, as this will cause direct parsing failure.
### Output:
JSON format: { "title": "your concise title here" }
### Examples:
- { "title": "📉 Stock Market Trends" },
- { "title": "🍪 Perfect Chocolate Chip Recipe" },
- { "title": "Evolution of Music Streaming" },
- { "title": "Remote Work Productivity Tips" },
- { "title": "Artificial Intelligence in Healthcare" },
- { "title": "🎮 Video Game Development Insights" }
### Chat History:
<chat_history>
$chatHistory
</chat_history>''';

    final endpointModel = _resolveEndpointModel(
      modelName,
      endpoints,
      endpointModels,
    );
    final endpoint = endpointModel == null
        ? null
        : endpoints
              .where((item) => item.id == endpointModel.endpointId)
              .cast<EndpointConfig?>()
              .firstOrNull;

    try {
      if (endpoint != null &&
          endpoint.url.trim().isNotEmpty &&
          endpoint.key.trim().isNotEmpty) {
        return _sanitizeTitle(
          await _generateEndpointTitle(
            prompt: titlePrompt,
            selectedModel: modelName,
            endpoint: endpoint,
            syncSettings: syncSettings,
          ),
          fallbackSource: fallbackMessage ?? '',
          fallbackTitle: fallbackTitle,
        );
      }
      return _sanitizeTitle(
        await _generateGeminiTitle(
          prompt: titlePrompt,
          selectedModel: modelName,
          geminiApiKey: geminiApiKey,
        ),
        fallbackSource: fallbackMessage ?? '',
        fallbackTitle: fallbackTitle,
      );
    } catch (_) {
      return fallbackTitle;
    }
  }

  Future<GeneratedResponse> _sendEndpoint({
    required http.Client client,
    required String prompt,
    required List<AttachmentData> attachments,
    required List<Message> history,
    required String selectedModel,
    required EndpointConfig endpoint,
    required String searchContext,
    required VoiceSettings voiceSettings,
    required List<Memory> memories,
    required bool thinkingMode,
    required bool artifactMode,
    required SyncSettings syncSettings,
    int? contextLimit,
    required TextDelta onText,
  }) async {
    final memoryText = memories.isEmpty
        ? ''
        : '\n\n=== IMPORTANT USER CONTEXT ===\n${memories.map((m) => '- ${m.content}').join('\n')}\n=== END USER CONTEXT ===\n\n';
    final thinkingInstruction = thinkingMode
        ? ' Start with concise reasoning enclosed in <think>...</think> tags before the final answer.'
        : ' Do not include hidden reasoning, chain-of-thought, reasoning_content, or <think> tags. Answer directly.';
    final systemText =
        '${_systemText(voiceSettings)}$thinkingInstruction\n\nPay attention to any user context or memories shared in the conversation.${artifactMode ? _artifactInstruction : ''}$memoryText';

    final finalPrompt = '$searchContext$prompt';
    final content = attachments.isEmpty
        ? finalPrompt
        : [
            {'type': 'text', 'text': finalPrompt},
            ...attachments.map((file) {
              if (file.type == 'text/extracted') {
                return {
                  'type': 'text',
                  'text':
                      '\n=== Contents of ${file.name} ===\n${file.data}\n=== End of ${file.name} ===\n',
                };
              }
              if (file.type.startsWith('image/')) {
                return {
                  'type': 'image_url',
                  'image_url': {'url': 'data:${file.type};base64,${file.data}'},
                };
              }
              return {
                'type': 'text',
                'text': '\n[Attached file: ${file.name} (${file.type})]',
              };
            }),
          ];

    final messages = [
      {'role': 'system', 'content': systemText},
      ..._openAiHistory(
        history,
        max(
          4000,
          ((contextLimit ?? contextWindow(selectedModel)) * 0.6).floor(),
        ),
      ),
      {'role': 'user', 'content': content},
    ];

    final payload = {
      'model': selectedModel,
      'messages': messages,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (!thinkingMode &&
          selectedModel.toLowerCase().contains('deepseek')) ...{
        'include_reasoning': false,
        'thinking': {'type': 'disabled'},
      },
    };

    final request =
        http.Request(
            'POST',
            Uri.parse('${_endpointBase(endpoint.url)}/chat/completions'),
          )
          ..headers.addAll({'Content-Type': 'application/json'})
          ..body = jsonEncode(payload);

    if (endpoint.key.trim().isNotEmpty && endpoint.key != 'sk-...') {
      request.headers['Authorization'] = 'Bearer ${endpoint.key}';
    }

    final streamed = await _sendWithProxyFallback(client, request, syncSettings);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw Exception(_extractApiError(body, 'Failed to connect to endpoint.'));
    }

    final buffer = StringBuffer();
    final rawBuffer = StringBuffer();
    var inputTokens =
        countTokens(finalPrompt) +
        countTokens(systemText) +
        history.fold<int>(0, (sum, item) => sum + countTokens(item.text));
    var outputTokens = 0;
    var cachedInputTokens = 0;
    var cacheCreationInputTokens = 0;
    var inReasoning = false;
    var isEstimated = true;
    final stopwatch = Stopwatch()..start();

    await for (final line
        in streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final trimmed = line.trim();
      rawBuffer.writeln(trimmed);

      if (!trimmed.startsWith('data: ')) continue;
      final dataText = trimmed.substring(6).trim();
      if (dataText == '[DONE]') break;
      try {
        final data = jsonDecode(dataText);
        final usage = data['usage'];
        if (usage is Map) {
          inputTokens = _usageInputTokens(usage, inputTokens);
          outputTokens = _usageOutputTokens(usage, outputTokens);
          final cacheUsage = _extractPromptCacheUsage(usage);
          cachedInputTokens = max(
            cachedInputTokens,
            cacheUsage.cachedInputTokens,
          );
          cacheCreationInputTokens = max(
            cacheCreationInputTokens,
            cacheUsage.cacheCreationInputTokens,
          );
          isEstimated = false;
        }
        final choice =
            data['choices'] is List && (data['choices'] as List).isNotEmpty
            ? data['choices'][0]
            : null;
        final delta = choice is Map ? choice['delta'] : null;
        if (thinkingMode &&
            delta is Map &&
            delta['reasoning_content'] != null) {
          if (!inReasoning) {
            inReasoning = true;
            buffer.write('<think>\n');
          }
          final text = stringValue(delta['reasoning_content']);
          buffer.write(text);
          onText(buffer.toString());
        }
        final messageObj = choice is Map ? choice['message'] : null;
        var content = delta is Map
            ? stringValue(delta['content'])
            : messageObj is Map
            ? stringValue(messageObj['content'])
            : stringValue(choice is Map ? choice['text'] : '');

        // Fallback for tools if content is empty
        if (content.isEmpty) {
          final tools = delta is Map
              ? delta['tool_calls']
              : (messageObj is Map ? messageObj['tool_calls'] : null);
          if (tools is List && tools.isNotEmpty) {
            content = '\n```json\n// Tool Call\n${jsonEncode(tools)}\n```\n';
          }
        }

        if (content.isNotEmpty) {
          if (inReasoning) {
            inReasoning = false;
            buffer.write('\n</think>\n');
          }
          buffer.write(content);
          onText(
            thinkingMode
                ? buffer.toString()
                : stripThinkingBlocks(buffer.toString()),
          );
        }
      } catch (_) {}
    }
    if (inReasoning) buffer.write('\n</think>\n');

    // Fallback: if the stream didn't yield any text, try parsing the entire raw buffer as a flat JSON response
    // in case the server ignored the "stream: true" flag.
    if (buffer.isEmpty && rawBuffer.isNotEmpty) {
      try {
        final rawStr = rawBuffer.toString().trim();
        if (rawStr.startsWith('{')) {
          final parsed = jsonDecode(rawStr);
          final usage = parsed['usage'];
          if (usage is Map) {
            inputTokens = _usageInputTokens(usage, inputTokens);
            outputTokens = _usageOutputTokens(usage, outputTokens);
            final cacheUsage = _extractPromptCacheUsage(usage);
            cachedInputTokens = max(
              cachedInputTokens,
              cacheUsage.cachedInputTokens,
            );
            cacheCreationInputTokens = max(
              cacheCreationInputTokens,
              cacheUsage.cacheCreationInputTokens,
            );
          }
          final choice = parsed['choices']?[0];
          final content = choice?['message']?['content'] ?? choice?['text'];
          if (content != null) {
            buffer.write(stringValue(content));
          }
        }
      } catch (_) {}
    }

    // Final fallback if absolutely nothing was extracted
    if (buffer.isEmpty && rawBuffer.toString().trim().isNotEmpty) {
      buffer.write('```\n${rawBuffer.toString().trim()}\n```');
    }

    final responseText = thinkingMode
        ? buffer.toString()
        : stripThinkingBlocks(buffer.toString());

    outputTokens = outputTokens == 0 ? countTokens(responseText) : outputTokens;
    return GeneratedResponse(
      text: responseText,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      endpointName: endpoint.name,
      cachedInputTokens: cachedInputTokens,
      cacheCreationInputTokens: cacheCreationInputTokens,
      isEstimated: isEstimated,
      generationTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  Future<GeneratedResponse> _sendGemini({
    required http.Client client,
    required String prompt,
    required List<AttachmentData> attachments,
    required List<Message> history,
    required String selectedModel,
    required String searchContext,
    required VoiceSettings voiceSettings,
    required String geminiApiKey,
    required List<Memory> memories,
    required bool thinkingMode,
    required bool artifactMode,
    int? contextLimit,
    required TextDelta onText,
  }) async {
    final key = geminiApiKey.trim();
    if (key.isEmpty) {
      throw Exception(
        'Gemini API key not found. Please provide one in Settings.',
      );
    }

    final model = selectedModel.replaceFirst('models/', '');
    final memoryList = memories.isEmpty
        ? ''
        : '\n\n=== IMPORTANT USER CONTEXT ===\n${memories.map((m) => '- ${m.content}').join('\n')}\n=== END USER CONTEXT ===\n\n';
    final thinkingInstruction = thinkingMode
        ? ' Start with a thinking process enclosed in <think>...</think> tags before the final answer.'
        : ' Do not include hidden reasoning, chain-of-thought, thoughts, or <think> tags. Answer directly.';
    final systemText =
        '${_systemText(voiceSettings)}$thinkingInstruction\n\nFORMATTING RULE: When providing code, always wrap it in Markdown triple backticks with the appropriate language identifier.${artifactMode ? _artifactInstruction : ''}$memoryList';
    final contents = [
      ..._geminiHistory(
        history,
        max(
          4000,
          ((contextLimit ?? contextWindow(selectedModel)) * 0.6).floor(),
        ),
      ),
      {
        'role': 'user',
        'parts': [
          {'text': '$searchContext$prompt'},
          ...attachments.map((file) {
            if (file.type == 'text/extracted') {
              return {
                'text':
                    '\n=== Contents of ${file.name} ===\n${file.data}\n=== End of ${file.name} ===\n',
              };
            }
            return {
              'inlineData': {'data': file.data, 'mimeType': file.type},
            };
          }),
        ],
      },
    ];

    final body = {
      'systemInstruction': {
        'parts': [
          {'text': systemText},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'maxOutputTokens': 65536,
        if (thinkingMode && model.toLowerCase().contains('thinking'))
          'thinkingConfig': {'includeThoughts': true},
      },
    };

    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:streamGenerateContent',
      {'key': key, 'alt': 'sse'},
    );
    final request = http.Request('POST', uri)
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode(body);
    final streamed = await client.send(request);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final error = await streamed.stream.bytesToString();
      throw Exception(_extractApiError(error, 'Gemini request failed.'));
    }

    final buffer = StringBuffer();
    var inThought = false;
    await for (final line
        in streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data: ')) continue;
      try {
        final data = jsonDecode(trimmed.substring(6));
        final parts = data['candidates']?[0]?['content']?['parts'];
        if (parts is! List) continue;
        for (final part in parts.whereType<Map>()) {
          final isThought = part['thought'] == true;
          if (isThought && !thinkingMode) continue;
          if (isThought && !inThought) {
            inThought = true;
            buffer.write('<think>\n');
          } else if (!isThought && inThought) {
            inThought = false;
            buffer.write('\n</think>\n');
          }
          if (part['text'] != null) buffer.write(stringValue(part['text']));
          if (part['executableCode'] is Map) {
            buffer.write(
              '\n```python\n${stringValue(part['executableCode']['code'])}\n```\n',
            );
          }
          if (part['executionResult'] is Map) {
            buffer.write(
              '\n```\n${stringValue(part['executionResult']['output'])}\n```\n',
            );
          }
        }
        onText(
          thinkingMode
              ? buffer.toString()
              : stripThinkingBlocks(buffer.toString()),
        );
      } catch (_) {}
    }
    if (inThought) buffer.write('\n</think>\n');
    final responseText = thinkingMode
        ? buffer.toString()
        : stripThinkingBlocks(buffer.toString());
    final inputTokens =
        countTokens(prompt) +
        countTokens(systemText) +
        history.fold<int>(0, (sum, item) => sum + countTokens(item.text));
    final outputTokens = countTokens(responseText);
    return GeneratedResponse(
      text: responseText,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      endpointName: 'Gemini',
    );
  }

  Future<String> _generateEndpointTitle({
    required String prompt,
    required String selectedModel,
    required EndpointConfig endpoint,
    required SyncSettings syncSettings,
  }) async {
    final request =
        http.Request(
            'POST',
            Uri.parse('${_endpointBase(endpoint.url)}/chat/completions'),
          )
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${endpoint.key}',
          })
          ..body = jsonEncode({
            'model': selectedModel,
            'messages': [
              {'role': 'user', 'content': prompt},
            ],
            'stream': false,
            'temperature': 0.2,
            'max_tokens': 1000,
          });

    final streamed = await _sendWithProxyFallback(http.Client(), request, syncSettings);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(_extractApiError(body, 'Title generation failed.'));
    }
    final data = jsonDecode(body);
    final choices = data['choices'];
    if (choices is List && choices.isNotEmpty) {
      final choice = choices.first;
      if (choice is Map) {
        final message = choice['message'];
        if (message is Map) {
          final content = stringValue(message['content']).trim();
          if (content.isNotEmpty) return content;
        }
        final text = stringValue(choice['text']).trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  Future<String> _generateGeminiTitle({
    required String prompt,
    required String selectedModel,
    required String geminiApiKey,
  }) async {
    final key = geminiApiKey.trim();
    if (key.isEmpty) return '';
    final model = selectedModel.replaceFirst('models/', '');
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      {'key': key},
    );
    final response = await _globalClient
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 800},
          }),
        )
        .timeout(const Duration(seconds: 18));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractApiError(response.body, 'Gemini title generation failed.'),
      );
    }
    return _geminiText(jsonDecode(response.body));
  }

  String _sanitizeTitle(
    String value, {
    String fallbackSource = '',
    String fallbackTitle = '',
  }) {
    // Strip thinking blocks from models like DeepSeek, Qwen, etc.
    var processedValue = value
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
    if (processedValue.isEmpty) processedValue = value;

    final fallback = fallbackTitle.trim().isNotEmpty
        ? fallbackTitle.trim()
        : _fallbackTitleFromMessage(fallbackSource);

    // First try robust JSON parsing (OpenWebUI style)
    final sanitized = processedValue
        .replaceAll('\u2018', '"')
        .replaceAll('\u2019', '"')
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"');

    var jsonText = '';
    // Look for a JSON block wrapped in markdown, otherwise fallback to finding brackets
    final blockMatch = RegExp(r'```(?:json)?\s*(\{[\s\S]*?\})\s*```', caseSensitive: false).firstMatch(sanitized);
    if (blockMatch != null) {
      jsonText = blockMatch.group(1)!;
    } else {
      final start = sanitized.indexOf('{');
      final end = sanitized.lastIndexOf('}') + 1;
      if (start != -1 && end > start) {
        jsonText = sanitized.substring(start, end);
      }
    }

    var cleaned = '';
    if (jsonText.isNotEmpty) {
      try {
        final parsed = jsonDecode(jsonText);
        if (parsed is Map && parsed.containsKey('title')) {
          cleaned = stringValue(parsed['title']);
        }
      } catch (_) {}
    }

    // If JSON parsing fails or returns empty, fallback to legacy cleaning on the raw string
    if (cleaned.isEmpty) {
      cleaned = value
          .replaceAll(RegExp(r'^title:\s*', caseSensitive: false), '')
          .replaceAll(
            RegExp(
              r'^(?:input\s+message|user\s+message|message|conversation|prompt)\s*[:\-]?\s*',
              caseSensitive: false,
            ),
            '',
          )
          .replaceAll(RegExp(r'''["'`_*#\[\]()]'''), '')
          .replaceAll(RegExp(r'\n+'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    if (cleaned.isEmpty) return fallback;
    final normalizedCleaned = _normalizedTitle(cleaned);
    final normalizedSource = _normalizedTitle(fallbackSource);
    if (normalizedCleaned == normalizedSource ||
        normalizedSource.startsWith(normalizedCleaned) ||
        normalizedCleaned.startsWith(normalizedSource)) {
      return fallback;
    }

    cleaned = cleaned.split(RegExp(r'\s+')).take(5).join(' ');
    final titled = _titleCase(cleaned);
    return titled.length > 42 ? titled.substring(0, 42).trim() : titled;
  }

  String _fallbackTitleFromMessages(List<Message> messages) {
    final firstUser = messages.where((m) => m.isUser).firstOrNull;
    if (firstUser == null) return 'New Chat';
    final assistant = messages
        .where((m) => !m.isUser && !m.isSystem)
        .firstOrNull;
    final userText = firstUser.text.trim();
    final assistantText = assistant?.text.trim() ?? '';
    final normalizedUser = _normalizedTitle(userText);
    final normalizedAssistant = _normalizedTitle(assistantText);
    final mentionedModel = _modelMentionFromText(userText);

    if (_looksLikeGreeting(normalizedUser)) {
      if (mentionedModel.isNotEmpty) return '$mentionedModel Greeting';
      if (normalizedAssistant.contains('how can i help') ||
          normalizedAssistant.contains('how may i help') ||
          normalizedAssistant.contains('can i help')) {
        return 'Assistant Greeting';
      }
      return 'Greeting Exchange';
    }

    return _fallbackTitleFromMessage(userText);
  }

  String _fallbackTitleFromMessage(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'''["'`_*#\[\]()]'''), '')
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'New Chat';

    final normalized = _normalizedTitle(cleaned);
    if (RegExp(r'\bwho\s+are\s+you\b').hasMatch(normalized)) {
      return 'Who Am I';
    }
    if (RegExp(r'\bwhat\s+are\s+you\b').hasMatch(normalized)) {
      return 'What Am I';
    }
    if (RegExp(r'\bwhat\s+can\s+you\s+do\b').hasMatch(normalized)) {
      return 'Assistant Capabilities';
    }

    final topic = _extractTitleTopic(cleaned);
    if (topic.isNotEmpty && _normalizedTitle(topic) != normalized) {
      final topicWords = topic.split(RegExp(r'\s+'));
      final title = topicWords.length <= 3 ? '$topic Basics' : topic;
      return _titleCase(title.split(RegExp(r'\s+')).take(4).join(' '));
    }

    final words = cleaned.split(RegExp(r'\s+')).take(4).join(' ');
    return _titleCase(words);
  }

  String _cleanTitleMessageText(String value) {
    return value
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<details[\s\S]*?</details>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), '')
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeGreeting(String normalized) {
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    if (words.isEmpty || words.length > 4) return false;
    return words.any((word) {
      final clean = word.replaceAll('-', '');
      return const {
        'hi',
        'hey',
        'hello',
        'helo',
        'hllo',
        'helllo',
        'hwllo',
        'halo',
        'hai',
        'yo',
      }.contains(clean);
    });
  }

  String _modelMentionFromText(String value) {
    final normalized = _normalizedTitle(value);
    if (RegExp(r'\bdeep\s*seek\b|\bdeepseek\b').hasMatch(normalized)) {
      return 'DeepSeek';
    }
    if (RegExp(r'\bgemini\b').hasMatch(normalized)) return 'Gemini';
    if (RegExp(r'\bgemma\b').hasMatch(normalized)) return 'Gemma';
    if (RegExp(r'\bmistral\b').hasMatch(normalized)) return 'Mistral';
    if (RegExp(r'\bgpt\b|\bchatgpt\b').hasMatch(normalized)) return 'GPT';
    if (RegExp(r'\bclaude\b').hasMatch(normalized)) return 'Claude';
    return '';
  }

  String _extractTitleTopic(String value) {
    var topic = value
        .replaceAll(
          RegExp(r'\bin\s+simple\s+terms\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\b(?:simple|simply|basic|basics)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    topic = topic
        .replaceFirst(
          RegExp(
            r'^(?:please\s+)?(?:explain|describe|define|summarize|tell\s+me\s+about)\s+(?:what\s+(?:is|are)\s+)?',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(
          RegExp(r'^(?:what|who)\s+(?:is|are)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return topic;
  }

  String _normalizedTitle(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _titleCase(String value) {
    const smallWords = {
      'a',
      'an',
      'and',
      'are',
      'as',
      'at',
      'for',
      'in',
      'of',
      'on',
      'or',
      'the',
      'to',
    };
    final words = value
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    return [
      for (var i = 0; i < words.length; i++)
        _titleWord(
          words[i],
          keepLowercase: i > 0 && smallWords.contains(words[i].toLowerCase()),
        ),
    ].join(' ');
  }

  String _titleWord(String word, {required bool keepLowercase}) {
    final lower = word.toLowerCase();
    if (!RegExp(r'[a-z0-9]', caseSensitive: false).hasMatch(word)) {
      return word;
    }
    if (keepLowercase) return lower;
    if (lower == 'ai') return 'AI';
    if (lower == 'gpt') return 'GPT';
    if (lower == 'html') return 'HTML';
    if (lower == 'api') return 'API';
    if (lower == 'deepseek') return 'DeepSeek';
    if (lower == 'i') return 'I';
    return lower.substring(0, 1).toUpperCase() + lower.substring(1);
  }

  Future<http.StreamedResponse> _sendWithProxyFallback(
    http.Client client,
    http.Request request,
    SyncSettings syncSettings,
  ) async {
    try {
      return await client.send(request);
    } catch (error) {
      final base = syncSettings.apiBaseUrl.trim().replaceAll(RegExp(r'/$'), '');
      if (base.isEmpty) rethrow;
      final proxy = http.Request(request.method, Uri.parse('$base/api/proxy'))
        ..headers.addAll(request.headers)
        ..headers['x-target-url'] = request.url.toString()
        ..bodyBytes = request.bodyBytes;
      return client.send(proxy);
    }
  }

  Future<http.Response> _getWithProxyFallback(
    Uri uri,
    Map<String, String> headers,
    SyncSettings syncSettings,
  ) async {
    try {
      return await _globalClient
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      final base = _proxyBase(syncSettings);
      if (base.isEmpty) rethrow;
      return _globalClient
          .get(
            Uri.parse('$base/api/proxy'),
            headers: {...headers, 'x-target-url': uri.toString()},
          )
          .timeout(const Duration(seconds: 20));
    }
  }

  String _proxyBase(SyncSettings syncSettings) {
    final configured = syncSettings.apiBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/$'), '');
    }
    return kIsWeb ? 'http://127.0.0.1:3000' : '';
  }

  List<Map<String, dynamic>> _extractModels(dynamic data) {
    final rawItems = switch (data) {
      List() => data,
      Map() when data['data'] is List => data['data'] as List,
      Map() when data['models'] is List => data['models'] as List,
      Map() when data['items'] is List => data['items'] as List,
      _ => const [],
    };
    return rawItems
        .map((item) {
          if (item is String) return {'id': item};
          if (item is Map) {
            final name = stringValue(
              item['id'],
              stringValue(item['name'], stringValue(item['model'])),
            );
            final ctx =
                item['context_length'] ??
                item['max_tokens'] ??
                item['max_context'];
            return {
              'id': name,
              if (ctx != null && int.tryParse(ctx.toString()) != null)
                'context_length': int.parse(ctx.toString()),
            };
          }
          return {'id': ''};
        })
        .map((m) {
          final id = (m['id'] as String)
              .replaceFirst(RegExp(r'^models/'), '')
              .trim();
          return {
            'id': id,
            if (m.containsKey('context_length'))
              'context_length': m['context_length'],
          };
        })
        .where((m) => (m['id'] as String).isNotEmpty)
        .toList();
  }

  Future<bool> _shouldSearch(
    String prompt,
    String model,
    EndpointConfig? endpoint,
    GenerationSettings settings,
    String geminiApiKey,
  ) async {
    if (settings.webSearchMode == 'off') return false;
    if (settings.webSearchMode == 'on') return true;
    final text = prompt.toLowerCase();
    const triggers = [
      'latest',
      'recent',
      'today',
      'current',
      'news',
      'price',
      'stock',
      'score',
      'schedule',
      'weather',
      'happening',
      '2026',
      'search web',
      'search the web',
      'search on web',
      'search internet',
      'search the internet',
      'google this',
      'find out',
      'what is the latest',
      'who won',
      'what is the weather',
      // Indonesian triggers
      'terbaru',
      'terkini',
      'hari ini',
      'sekarang',
      'berita',
      'harga',
      'cuaca',
      'jadwal',
      'sedang terjadi',
    ];
    return triggers.any(text.contains);
  }

  Future<String> _performSearch(
    String query,
    GenerationSettings settings,
    List<EndpointConfig> endpoints,
    List<EndpointModel> endpointModels,
    String geminiApiKey,
    SyncSettings syncSettings,
    StatusCallback onStatus,
  ) async {
    final engine = settings.webSearchEngine;
    onStatus('Searching the web...');
    if (engine == 'duckduckgo') {
      final response = await http.post(
        Uri.parse('https://lite.duckduckgo.com/lite/'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        },
        body: 'q=${Uri.encodeQueryComponent(query)}',
      );

      final html = response.body;
      final results = <Map<String, String>>[];
      
      final linkRegex = RegExp(r"<a[^>]+href=\x22([^\x22]+)\x22[^>]*class='result-link'[^>]*>(.*?)</a>");
      final snippetRegex = RegExp(r"<td class='result-snippet'>\s*(.*?)\s*</td>", dotAll: true);
      
      final linkMatches = linkRegex.allMatches(html).toList();
      final snippetMatches = snippetRegex.allMatches(html).toList();

      for (int i = 0; i < linkMatches.length; i++) {
        var url = linkMatches[i].group(1) ?? '';
        if (url.startsWith('//')) {
          url = 'https:$url';
        } else if (url.startsWith('/')) {
          url = 'https://lite.duckduckgo.com$url';
        }
        var title = linkMatches[i].group(2) ?? '';
        title = title.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&#x27;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&');
        
        var snippet = i < snippetMatches.length ? snippetMatches[i].group(1) ?? '' : '';
        snippet = snippet.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&#x27;', "'").replaceAll('&quot;', '"').replaceAll('&amp;', '&');
        
        if (url.isNotEmpty && title.isNotEmpty && !url.contains('duckduckgo.com/lite/')) {
          results.add({
            'title': title.trim(),
            'url': url,
            'snippet': snippet.trim(),
          });
        }
      }

      if (results.isEmpty) {
        throw Exception('DuckDuckGo returned no web results.');
      }
      onStatus('Found ${results.length} DuckDuckGo results.');
      return _searchBlock(results.take(8).toList());
    }

    if (engine == 'google-custom') {
      if (settings.googleSearchApiKey.trim().isEmpty ||
          settings.googleSearchCx.trim().isEmpty) {
        throw Exception(
          'Google Custom Search API key and search engine ID are required.',
        );
      }
      final uri = Uri.https('www.googleapis.com', '/customsearch/v1', {
        'key': settings.googleSearchApiKey.trim(),
        'cx': settings.googleSearchCx.trim(),
        'q': query,
        'num': '8',
      });
      final data = await _getJson(uri);
      final items = data['items'] is List ? data['items'] as List : const [];
      final results = items
          .whereType<Map>()
          .map(
            (item) => {
              'title': stringValue(item['title'], 'Untitled'),
              'url': stringValue(item['link']),
              'snippet': stringValue(item['snippet']),
            },
          )
          .toList();
      if (results.isEmpty) {
        throw Exception('Google Custom Search returned no results.');
      }
      onStatus('Found ${results.length} Google results.');
      return _searchBlock(results);
    }

    if (engine == 'tavily') {
      if (settings.tavilyApiKey.trim().isEmpty) {
        throw Exception('Tavily API key is not configured.');
      }
      final response = await _globalClient.post(
        Uri.https('api.tavily.com', '/search'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': settings.tavilyApiKey.trim(),
          'query': query,
          'search_depth': 'advanced',
          'include_answer': true,
          'max_results': 8,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          _extractApiError(response.body, 'Tavily search failed.'),
        );
      }
      final data = jsonDecode(response.body);
      final items = data['results'] is List
          ? data['results'] as List
          : const [];
      final results = items
          .whereType<Map>()
          .map(
            (item) => {
              'title': stringValue(item['title'], 'Untitled'),
              'url': stringValue(item['url']),
              'snippet': stringValue(item['content']),
            },
          )
          .toList();
      if (results.isEmpty) throw Exception('Tavily returned no results.');
      final answer = stringValue(data['answer']);
      onStatus('Found ${results.length} Tavily results.');
      return '\n\n[Web Search Results]\n${answer.isEmpty ? '' : 'Tavily AI Summary: $answer\n\n'}${_formatResults(results)}\n[End of Search Results]\n\nUsing the search results above as context, answer the user question. Cite source links when available:\n';
    }

    if (engine == 'mistral') {
      if (settings.mistralApiKey.isEmpty || settings.mistralAgentId.isEmpty) {
        throw Exception('Mistral API Key or Agent ID is not configured.');
      }
      final request =
          http.Request(
              'POST',
              Uri.parse('https://api.mistral.ai/v1/conversations'),
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer ${settings.mistralApiKey}',
            })
            ..body = jsonEncode({
              'agent_id': settings.mistralAgentId,
              'inputs': [
                {'role': 'user', 'content': query},
              ],
            });
      final response = await _sendWithProxyFallback(_globalClient, request, syncSettings);
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractApiError(body, 'Mistral web search failed.'));
      }
      final data = jsonDecode(body);
      String text = '';
      final outputs = data['outputs'];
      if (outputs is List) {
        final outputMsg = outputs.firstWhere(
          (e) => e is Map && e['type'] == 'message.output',
          orElse: () => null,
        );
        if (outputMsg != null) {
          final content = outputMsg['content'];
          if (content is List) {
            for (var part in content) {
              if (part is Map && part['type'] == 'text') {
                text += stringValue(part['text']);
              }
              if (part is Map && part['type'] == 'tool_reference') {
                final title = stringValue(part['title']);
                final url = stringValue(part['url']);
                if (title.isNotEmpty && url.isNotEmpty) {
                  text += '\nSource: [$title]($url)\n';
                }
              }
            }
          } else if (content is String) {
            text = content;
          }
        }
      }
      text = text.trim();
      if (text.isEmpty) {
        throw Exception('Mistral returned an empty search result.');
      }
      onStatus('Generated Mistral web search summary.');
      return '\n\n[Web Search Results]\n$text\n[End of Search Results]\n\nUsing the search results above as context, answer the user question. Cite source links when available:\n';
    }

    if (engine == 'endpoint') {
      final endpoint = endpoints
          .where((item) => item.id == settings.webSearchEndpointId)
          .cast<EndpointConfig?>()
          .firstOrNull;
      if (endpoint == null ||
          endpoint.url.isEmpty ||
          endpoint.key.isEmpty ||
          settings.webSearchModel.isEmpty) {
        throw Exception('Web search endpoint or model is not configured.');
      }
      final request =
          http.Request(
              'POST',
              Uri.parse('${_endpointBase(endpoint.url)}/chat/completions'),
            )
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${endpoint.key}',
            })
            ..body = jsonEncode({
              'model': settings.webSearchModel,
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Use live web search if available. Return a concise research summary with source links.',
                },
                {'role': 'user', 'content': query},
              ],
              'temperature': 0.2,
            });
      final response = await _sendWithProxyFallback(_globalClient, request, syncSettings);
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_extractApiError(body, 'Endpoint web search failed.'));
      }
      final data = jsonDecode(body);
      final text = stringValue(
        data['choices']?[0]?['message']?['content'],
      ).trim();
      if (text.isEmpty) {
        throw Exception('Endpoint web search returned no text.');
      }
      onStatus('Endpoint search complete.');
      return '\n\n[Web Search Results]\n$text\n[End of Search Results]\n\nUsing the search results above as context, answer the user question. Cite source links when available:\n';
    }

    if (geminiApiKey.trim().isEmpty) {
      throw Exception(
        'Gemini API key is required for Gemini Grounding search.',
      );
    }
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/${settings.webSearchModel.isEmpty ? 'gemini-flash-lite-latest' : settings.webSearchModel}:generateContent',
      {'key': geminiApiKey.trim()},
    );
    final response = await _globalClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': query},
            ],
          },
        ],
        'tools': [
          {'googleSearch': {}},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _extractApiError(response.body, 'Gemini web search failed.'),
      );
    }
    final data = jsonDecode(response.body);
    final text = _geminiText(data);
    if (text.isEmpty) throw Exception('Gemini web search returned no text.');
    onStatus('Gemini search complete.');
    return '\n\n[Web Search Results]\n$text\n[End of Search Results]\n\nUsing the search results above as context, answer the user question. Cite source links when available:\n';
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _globalClient
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed with status ${response.statusCode}.');
    }
    return Map<String, dynamic>.from(jsonDecode(response.body));
  }

  String _searchBlock(List<Map<String, String>> results) {
    return '\n\n[Web Search Results]\n${_formatResults(results)}\n[End of Search Results]\n\nUsing the search results above as context, answer the user question. Cite source links when available:\n';
  }

  String _formatResults(List<Map<String, String>> results) {
    return results
        .asMap()
        .entries
        .map((entry) {
          final value = entry.value;
          return '[${entry.key + 1}] ${value['title']}\n${value['url']}\n${value['snippet']}';
        })
        .join('\n\n');
  }

  String _systemText(VoiceSettings settings) {
    if (settings.textPersonality == 'Custom') {
      return settings.customTextPersonality.isEmpty
          ? _textPrompts['Assistant']!
          : settings.customTextPersonality;
    }
    if (settings.textPersonality.startsWith('custom-text:')) {
      final id = settings.textPersonality.replaceFirst('custom-text:', '');
      return settings.customTextPersonalities
              .where((item) => item.id == id)
              .firstOrNull
              ?.prompt ??
          _textPrompts['Assistant']!;
    }
    return _textPrompts[settings.textPersonality] ?? _textPrompts['Assistant']!;
  }

  EndpointModel? _resolveEndpointModel(
    String modelName,
    List<EndpointConfig> endpoints,
    List<EndpointModel> endpointModels,
  ) {
    final direct = endpointModels
        .where((item) => item.name == modelName)
        .cast<EndpointModel?>()
        .firstOrNull;
    if (direct != null) return direct;
    for (final endpoint in endpoints) {
      if (endpoint.models.any((model) => model == modelName)) {
        return EndpointModel(name: modelName, endpointId: endpoint.id);
      }
    }
    final nonGeminiHint =
        modelName.contains('/') ||
        [
          'llama',
          'qwen',
          'mistral',
          'gpt',
          'deepseek',
          'claude',
        ].any(modelName.toLowerCase().contains);
    if (nonGeminiHint &&
        endpoints.isNotEmpty &&
        !modelName.toLowerCase().startsWith('gemini')) {
      return EndpointModel(name: modelName, endpointId: endpoints.first.id);
    }
    return null;
  }

  List<Map<String, dynamic>> _openAiHistory(
    List<Message> messages,
    int tokenBudget,
  ) {
    final result = <Map<String, dynamic>>[];
    var used = 0;
    for (final message in messages.reversed) {
      final tokens = countTokens(message.text) + 8;
      if (result.isNotEmpty && used + tokens > tokenBudget) break;
      used += tokens;
      result.insert(0, {
        'role': message.isUser ? 'user' : 'assistant',
        'content': _messageText(message),
      });
    }
    return result;
  }

  List<Map<String, dynamic>> _geminiHistory(
    List<Message> messages,
    int tokenBudget,
  ) {
    final result = <Map<String, dynamic>>[];
    var used = 0;
    for (final message in messages.reversed) {
      final tokens = countTokens(message.text) + 8;
      if (result.isNotEmpty && used + tokens > tokenBudget) break;
      used += tokens;
      result.insert(0, {
        'role': message.isUser ? 'user' : 'model',
        'parts': [
          {'text': _messageText(message)},
        ],
      });
    }
    if (result.isNotEmpty && result.first['role'] == 'model') {
      result.insert(0, {
        'role': 'user',
        'parts': [
          {'text': 'Continue from the previous conversation.'},
        ],
      });
    }
    return result;
  }

  String _messageText(Message message) {
    final attachmentNotes = message.attachments
        .map((item) => '[Attachment: ${item.name} (${item.type})]')
        .join('\n');
    return [
      parseText(message.text).mainContent.trim(),
      attachmentNotes,
    ].where((item) => item.isNotEmpty).join('\n');
  }

  String _geminiText(dynamic data) {
    final parts = data['candidates']?[0]?['content']?['parts'];
    if (parts is! List) return '';
    return parts
        .whereType<Map>()
        .map((part) => stringValue(part['text']))
        .where((text) => text.isNotEmpty)
        .join();
  }

  String _extractApiError(String body, String fallback) {
    final trimmed = body.trim();
    if (trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html') ||
        trimmed.contains('<html')) {
      return '$fallback Endpoint returned HTML instead of JSON. Check the Base URL; OpenRouter should be https://openrouter.ai/api/v1.';
    }
    try {
      final data = jsonDecode(body);
      final errorNode = data['error'];
      final message = errorNode is Map
          ? errorNode['message']
          : (errorNode ?? data['message']);
      return stringValue(message, fallback);
    } catch (_) {
      if (trimmed.isEmpty) return fallback;
      return trimmed.length > 360 ? '${trimmed.substring(0, 360)}...' : trimmed;
    }
  }

  String _cleanError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  String _trimSlash(String value) => value.trim().replaceAll(RegExp(r'/$'), '');

  String _endpointBase(String value) {
    final base = _trimSlash(value);
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme) return base;
    if (uri.host.toLowerCase().contains('openrouter.ai') &&
        !uri.path.toLowerCase().contains('/api/v1')) {
      return '${uri.scheme}://${uri.host}/api/v1';
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.toLowerCase().endsWith('/chat/completions')) {
      final nextPath = path.substring(
        0,
        path.length - '/chat/completions'.length,
      );
      return uri.replace(path: nextPath.isEmpty ? '/' : nextPath).toString();
    }
    if (path.toLowerCase().endsWith('/chat')) {
      final nextPath = path.substring(0, path.length - '/chat'.length);
      return uri.replace(path: nextPath.isEmpty ? '/' : nextPath).toString();
    }
    return base;
  }

  static const _artifactInstruction =
      '\n\nARTIFACT MODE ENABLED: Create complete multi-file web projects. Start every code block with a file header comment such as // file: path/name.ext or <!-- file: path/name.html -->. Provide full file contents.';
}

class ParsedText {
  const ParsedText({
    this.thinkContent,
    required this.mainContent,
    required this.isThinkingStill,
  });

  final String? thinkContent;
  final String mainContent;
  final bool isThinkingStill;
}

ParsedText parseText(String text) {
  final regex = RegExp(r'<think>([\s\S]*?)(</think>|$)', caseSensitive: false);
  final match = regex.firstMatch(text);
  if (match == null) {
    return ParsedText(mainContent: text, isThinkingStill: false);
  }
  final hasClosed = text.toLowerCase().contains('</think>');
  var main = '';
  if (hasClosed) {
    final before = text.split(RegExp(r'<think>', caseSensitive: false)).first;
    final after = text.split(RegExp(r'</think>', caseSensitive: false)).last;
    main = '$before $after'.trim();
  } else {
    main = text.split(RegExp(r'<think>', caseSensitive: false)).first.trim();
  }
  return ParsedText(
    thinkContent: match.group(1),
    mainContent: main,
    isThinkingStill: !hasClosed,
  );
}

String stripThinkingBlocks(String text) {
  final withoutClosed = text.replaceAll(
    RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
    '',
  );
  return withoutClosed
      .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
      .trimLeft();
}

class _PromptCacheUsage {
  const _PromptCacheUsage({
    required this.cachedInputTokens,
    required this.cacheCreationInputTokens,
  });

  final int cachedInputTokens;
  final int cacheCreationInputTokens;
}

_PromptCacheUsage _extractPromptCacheUsage(Map<dynamic, dynamic> usage) {
  final promptDetails = _mapValue(
    usage['prompt_tokens_details'] ??
        usage['promptTokensDetails'] ??
        usage['input_tokens_details'] ??
        usage['inputTokensDetails'],
  );
  final cachedInputTokens = _firstPositiveInt([
    usage['cached_tokens'],
    usage['cachedTokens'],
    usage['cached_input_tokens'],
    usage['cachedInputTokens'],
    usage['cache_read_input_tokens'],
    usage['cacheReadInputTokens'],
    usage['prompt_cache_hit_tokens'],
    usage['promptCacheHitTokens'],
    usage['prompt_cache_read_tokens'],
    usage['promptCacheReadTokens'],
    promptDetails?['cached_tokens'],
    promptDetails?['cachedTokens'],
    promptDetails?['cache_read_tokens'],
    promptDetails?['cacheReadTokens'],
    promptDetails?['cache_read_input_tokens'],
    promptDetails?['cacheReadInputTokens'],
  ]);
  final cacheCreationInputTokens = _firstPositiveInt([
    usage['cache_creation_input_tokens'],
    usage['cacheCreationInputTokens'],
    usage['prompt_cache_creation_tokens'],
    usage['promptCacheCreationTokens'],
    usage['prompt_cache_miss_tokens'],
    usage['promptCacheMissTokens'],
    promptDetails?['cache_creation_tokens'],
    promptDetails?['cacheCreationTokens'],
    promptDetails?['cache_creation_input_tokens'],
    promptDetails?['cacheCreationInputTokens'],
  ]);
  return _PromptCacheUsage(
    cachedInputTokens: cachedInputTokens,
    cacheCreationInputTokens: cacheCreationInputTokens,
  );
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

int _firstPositiveInt(Iterable<Object?> values) {
  for (final value in values) {
    final parsed = intValue(value);
    if (parsed > 0) return parsed;
  }
  return 0;
}

int _usageInputTokens(Map<dynamic, dynamic> usage, int fallback) {
  final parsed = _firstPositiveInt([
    usage['prompt_tokens'],
    usage['promptTokens'],
    usage['input_tokens'],
    usage['inputTokens'],
  ]);
  return parsed > 0 ? parsed : fallback;
}

int _usageOutputTokens(Map<dynamic, dynamic> usage, int fallback) {
  final parsed = _firstPositiveInt([
    usage['completion_tokens'],
    usage['completionTokens'],
    usage['output_tokens'],
    usage['outputTokens'],
  ]);
  return parsed > 0 ? parsed : fallback;
}

int countTokens(String text) => max(1, (text.length / 4).ceil());

String formatTokenCount(int tokens) {
  if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
  if (tokens >= 1000) return '${(tokens / 1000).round()}K';
  return tokens.toString();
}

int contextWindow(String model) {
  final normalized = model.toLowerCase().trim();
  if (normalized.contains('gemini-1.5-pro')) return 2000000;
  if (normalized.contains('gemini')) return 1000000;
  if (normalized.contains('claude')) return 200000;
  if (normalized.contains('o1')) return 200000;
  if (normalized.contains('gpt-4o') ||
      normalized.contains('gpt-4-turbo') ||
      normalized.contains('gpt')) {
    return 128000;
  }
  if (normalized.contains('llama-3.1') ||
      normalized.contains('llama-3.3') ||
      normalized.contains('qwen')) {
    return 131072;
  }
  if (normalized.contains('mistral') || normalized.contains('deepseek')) {
    return 128000;
  }
  return 128000;
}

String cleanTitle(String raw) {
  final cleaned = raw
      .trim()
      .replaceAll(RegExp(r'''^["']|["']$'''), '')
      .replaceAll(RegExp(r'^title:\s*', caseSensitive: false), '')
      .replaceAll(RegExp(r'[.!?,;:]+$'), '')
      .split(RegExp(r'\s+'))
      .take(6)
      .join(' ');
  return cleaned.length > 50 ? cleaned.substring(0, 50).trim() : cleaned;
}

class LinkedHashSetString {
  LinkedHashSetString(Iterable<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty && !_seen.contains(value)) {
        _seen.add(value);
        _values.add(value);
      }
    }
  }

  final _seen = <String>{};
  final _values = <String>[];

  List<String> toList() => _values;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
