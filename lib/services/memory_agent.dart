import '../models.dart';

class MemoryAgentAction {
  const MemoryAgentAction({
    required this.action,
    required this.type,
    required this.key,
    required this.value,
    required this.scope,
    required this.confidence,
    required this.sensitivity,
    required this.reason,
  });

  final String action;
  final String type;
  final String key;
  final String value;
  final String scope;
  final double confidence;
  final String sensitivity;
  final String reason;

  bool get applies =>
      action != 'ignore' &&
      key.isNotEmpty &&
      key != 'none' &&
      confidence >= 0.7 &&
      sensitivity != 'high';

  Map<String, dynamic> toJson() => {
    'action': action,
    'type': type,
    'key': key,
    'value': value,
    'scope': scope,
    'confidence': confidence,
    'sensitivity': sensitivity,
    'reason': reason,
  };
}

class MemoryAgent {
  const MemoryAgent();

  List<MemoryAgentAction> analyze({
    required String message,
    required List<Memory> existingMemories,
  }) {
    final clean = _clean(message);
    if (clean.isEmpty) return [_ignore('The message is empty.')];

    final lower = clean.toLowerCase();
    final normalized = _normalize(clean);
    if (_containsSecret(clean) || _containsHighSensitivity(lower)) {
      return [_ignore('The message contains sensitive information.')];
    }

    final delete = _deleteAction(clean, normalized, existingMemories);
    if (delete != null) return [delete];

    final actions = <MemoryAgentAction>[
      ..._personalActions(clean, normalized, existingMemories),
      ..._preferenceActions(clean, lower, normalized, existingMemories),
      ..._projectActions(clean, lower, normalized, existingMemories),
      ..._rememberActions(clean, lower, normalized, existingMemories),
    ];

    final unique = <String, MemoryAgentAction>{};
    for (final action in actions.where((item) => item.applies)) {
      unique[action.key] = action;
    }
    if (unique.isEmpty) {
      return [_ignore('No clearly useful cross-session memory was found.')];
    }
    return unique.values.toList();
  }

  List<MemoryAgentAction> _personalActions(
    String clean,
    String normalized,
    List<Memory> existing,
  ) {
    final actions = <MemoryAgentAction>[];

    final name = _firstMatch(clean, [
      RegExp(
        r"\bmy name is\s+([A-Za-z][A-Za-z0-9 _-]{1,40})",
        caseSensitive: false,
      ),
      RegExp(r"\bi am\s+([A-Za-z][A-Za-z0-9 _-]{1,40})", caseSensitive: false),
      RegExp(r"\bi'm\s+([A-Za-z][A-Za-z0-9 _-]{1,40})", caseSensitive: false),
    ]);
    if (name != null && !_looksLikeActivity(name)) {
      final pretty = _titleName(name);
      actions.add(
        _upsert(
          key: 'user_name',
          type: 'personal_fact',
          value: "User's name is $pretty.",
          scope: 'global',
          confidence: 1.0,
          existing: existing,
          reason: 'The user explicitly stated their name.',
        ),
      );
    }

    final nickname = _firstMatch(clean, [
      RegExp(
        r"\bcall me\s+([A-Za-z][A-Za-z0-9 _-]{1,40})",
        caseSensitive: false,
      ),
      RegExp(
        r"\byou can call me\s+([A-Za-z][A-Za-z0-9 _-]{1,40})",
        caseSensitive: false,
      ),
    ]);
    if (nickname != null && !_looksLikeActivity(nickname)) {
      actions.add(
        _upsert(
          key: 'nickname',
          type: 'personal_fact',
          value: 'User likes to be called ${_titleName(nickname)}.',
          scope: 'global',
          confidence: 1.0,
          existing: existing,
          reason: 'The user explicitly gave a preferred name.',
        ),
      );
    }

    final pet = RegExp(
      r"\b(?:actually\s+)?i\s+(?:have|own)\s+([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten)\s+(dog|dogs|cat|cats|bird|birds|fish|pets)\b",
      caseSensitive: false,
    ).firstMatch(clean);
    if (pet != null && !_temporaryAnimalMention(normalized)) {
      final count = _numberWordToDigit(pet.group(1)!);
      final animal = _pluralizePet(pet.group(2)!, count);
      actions.add(
        _upsert(
          key: 'pets',
          type: 'personal_fact',
          value: 'User has $count $animal.',
          scope: 'global',
          confidence: 1.0,
          existing: existing,
          reason: 'The user explicitly stated a stable pet fact.',
        ),
      );
    }

    return actions;
  }

  List<MemoryAgentAction> _preferenceActions(
    String clean,
    String lower,
    String normalized,
    List<Memory> existing,
  ) {
    final actions = <MemoryAgentAction>[];

    if (RegExp(
      r'\b(?:prefer|usually want|want|use)\s+(?:casual\s+)?(?:bahasa\s+)?indonesian\b',
      caseSensitive: false,
    ).hasMatch(clean)) {
      actions.add(
        _upsert(
          key: 'preferred_language',
          type: 'communication_style',
          value: 'User prefers Indonesian when appropriate.',
          scope: 'global',
          confidence: 0.9,
          existing: existing,
          reason: 'The user clearly stated a language preference.',
        ),
      );
    }

    if (lower.contains('hate verbose') ||
        lower.contains('not verbose') ||
        lower.contains('less verbose') ||
        lower.contains('concise answer') ||
        lower.contains('keep it concise') ||
        lower.contains('short answer')) {
      actions.add(
        _upsert(
          key: 'preferred_tone',
          type: 'communication_style',
          value:
              'User prefers concise answers and dislikes unnecessary verbosity.',
          scope: 'global',
          confidence: 0.9,
          existing: existing,
          reason: 'The user clearly stated a response style preference.',
        ),
      );
    }

    if (lower.contains('casual indonesian') ||
        lower.contains('casual tone') ||
        lower.contains('informal tone')) {
      actions.add(
        _upsert(
          key: 'preferred_tone',
          type: 'communication_style',
          value: 'User prefers a casual tone when appropriate.',
          scope: 'global',
          confidence: 0.85,
          existing: existing,
          reason: 'The user clearly stated a tone preference.',
        ),
      );
    }

    final framework = RegExp(
      r'\bi\s+prefer\s+(flutter|react|vue|svelte|angular|kotlin|swift|dart)\b',
      caseSensitive: false,
    ).firstMatch(clean);
    if (framework != null) {
      final value = _titleName(framework.group(1)!);
      actions.add(
        _upsert(
          key: value.toLowerCase() == 'flutter'
              ? 'preferred_mobile_framework'
              : 'preferred_framework',
          type: 'preference',
          value: 'User prefers $value.',
          scope: 'global',
          confidence: 0.95,
          existing: existing,
          reason: 'The user clearly stated a framework preference.',
        ),
      );
    }

    if (lower.contains('lightweight ui') ||
        lower.contains('minimal ui') ||
        lower.contains('premium ui') ||
        lower.contains('same ui') ||
        lower.contains('preserve the ui')) {
      actions.add(
        _upsert(
          key: 'ui_preference',
          type: 'preference',
          value: _uiPreferenceValue(lower),
          scope: 'global',
          confidence: 0.8,
          existing: existing,
          reason: 'The user stated a durable UI preference.',
        ),
      );
    }

    return actions;
  }

  List<MemoryAgentAction> _projectActions(
    String clean,
    String lower,
    String normalized,
    List<Memory> existing,
  ) {
    final actions = <MemoryAgentAction>[];

    if (RegExp(
      r"\bi\s+am\s+building\s+(?:an?\s+)?(.{3,90})",
      caseSensitive: false,
    ).hasMatch(clean)) {
      final project = RegExp(
        r"\bi\s+am\s+building\s+(?:an?\s+)?(.{3,90})",
        caseSensitive: false,
      ).firstMatch(clean)!.group(1)!;
      final projKeyWords = _normalize(project).split(' ').where((w) => w.isNotEmpty).take(3).join('_');
      final projKey = projKeyWords.isEmpty ? 'current_project' : 'project_$projKeyWords';
      actions.add(
        _upsert(
          key: projKey,
          type: 'project_memory',
          value: 'User is building ${_trimClause(project)}.',
          scope: 'project',
          confidence: 0.9,
          existing: existing,
          reason: 'The user clearly stated their current project.',
        ),
      );
    }

    final projectRequirement = RegExp(
      r'\b(?:for this app|for this project|this app must|this app should|the app must|the app should)\b(.{4,220})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (projectRequirement != null) {
      final clause = _trimClause(projectRequirement.group(0)!);
      actions.add(
        _upsert(
          key: _projectRequirementKey(clause),
          type: 'project_memory',
          value: 'Project requirement: $clause.',
          scope: 'project',
          confidence: 0.85,
          existing: existing,
          reason: 'The user stated a stable project requirement.',
        ),
      );
    }

    if (lower.contains('openai-compatible endpoint') ||
        lower.contains('openai compatible endpoint')) {
      actions.add(
        _upsert(
          key: 'project_endpoint_requirement',
          type: 'project_memory',
          value: 'Project should support OpenAI-compatible endpoints.',
          scope: 'project',
          confidence: 0.9,
          existing: existing,
          reason: 'The user stated a stable app integration requirement.',
        ),
      );
    }

    return actions;
  }

  List<MemoryAgentAction> _rememberActions(
    String clean,
    String lower,
    String normalized,
    List<Memory> existing,
  ) {
    final remember = RegExp(
      r'\bremember(?: that)?\s+(.{3,220})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (remember == null) return const [];

    final content = _trimClause(remember.group(1)!);
    if (content.isEmpty ||
        _containsSecret(content) ||
        _containsHighSensitivity(content.toLowerCase())) {
      return const [];
    }

    final nested = [
      ..._personalActions(content, _normalize(content), existing),
      ..._preferenceActions(
        content,
        content.toLowerCase(),
        _normalize(content),
        existing,
      ),
      ..._projectActions(
        content,
        content.toLowerCase(),
        _normalize(content),
        existing,
      ),
    ].where((item) => item.applies).toList();
    if (nested.isNotEmpty) return nested;

    return [
      _upsert(
        key: _stableCustomKey(content),
        type:
            content.toLowerCase().contains('app') ||
                content.toLowerCase().contains('project')
            ? 'project_memory'
            : 'preference',
        value: _memorySentence(content),
        scope:
            content.toLowerCase().contains('app') ||
                content.toLowerCase().contains('project')
            ? 'project'
            : 'global',
        confidence: 0.9,
        existing: existing,
        reason: 'The user explicitly asked to remember this information.',
      ),
    ];
  }

  MemoryAgentAction? _deleteAction(
    String clean,
    String normalized,
    List<Memory> existing,
  ) {
    if (!RegExp(
      r"\b(forget|delete|remove|don't remember|do not remember)\b",
      caseSensitive: false,
    ).hasMatch(clean)) {
      return null;
    }

    final key = _deleteKey(normalized);
    return MemoryAgentAction(
      action: 'delete',
      type: _typeForKey(key),
      key: key,
      value: '',
      scope: key.startsWith('project') ? 'project' : 'global',
      confidence: key == 'none' ? 0.0 : 1.0,
      sensitivity: 'low',
      reason: key == 'none'
          ? 'The delete request did not identify a stored memory.'
          : 'The user explicitly asked to forget this memory.',
    );
  }

  String _deleteKey(String normalized) {
    if (RegExp(r'\b(dog|dogs|cat|cats|pet|pets)\b').hasMatch(normalized)) {
      return 'pets';
    }
    if (normalized.contains('name')) return 'user_name';
    if (normalized.contains('nickname') || normalized.contains('call me')) {
      return 'nickname';
    }
    if (normalized.contains('language') || normalized.contains('indonesian')) {
      return 'preferred_language';
    }
    if (normalized.contains('verbose') ||
        normalized.contains('tone') ||
        normalized.contains('style')) {
      return 'preferred_tone';
    }
    if (normalized.contains('framework') ||
        normalized.contains('flutter') ||
        normalized.contains('react')) {
      return 'preferred_framework';
    }
    if (normalized.contains('project') || normalized.contains('app')) {
      // It is safer to let the user delete specific projects via the UI 
      // rather than blindly deleting all project requirements.
      return 'none';
    }
    return 'none';
  }

  MemoryAgentAction _upsert({
    required String key,
    required String type,
    required String value,
    required String scope,
    required double confidence,
    required List<Memory> existing,
    required String reason,
  }) {
    final action = _hasExistingKey(existing, key) ? 'update' : 'save';
    return MemoryAgentAction(
      action: action,
      type: type,
      key: key,
      value: value,
      scope: scope,
      confidence: confidence,
      sensitivity: 'low',
      reason: reason,
    );
  }

  bool _hasExistingKey(List<Memory> existing, String key) {
    return existing.any((memory) => _memoryKey(memory) == key);
  }

  String _memoryKey(Memory memory) {
    return memory.key.isNotEmpty ? memory.key : Memory.inferKey(memory.content);
  }

  MemoryAgentAction _ignore(String reason) {
    return MemoryAgentAction(
      action: 'ignore',
      type: 'ignore',
      key: 'none',
      value: '',
      scope: 'chat',
      confidence: 0,
      sensitivity: 'low',
      reason: reason,
    );
  }

  bool _containsSecret(String value) {
    return RegExp(
      r'(api[_ -]?key\s*(?:is|=|:)|password\s*(?:is|=|:)|token\s*(?:is|=|:)|cookie\s*(?:is|=|:)|private[_ -]?key|bearer\s+[a-z0-9._-]{12,}|sk-[a-z0-9_-]{12,}|AIza[0-9A-Za-z_-]{20,})',
      caseSensitive: false,
    ).hasMatch(value);
  }

  bool _containsHighSensitivity(String lower) {
    return RegExp(
      r'\b(religion|political view|politics|diagnosed|diagnosis|disease|therapy|lawsuit|criminal|sexual|bank account|credit card|government id|passport|ssn|home address)\b',
    ).hasMatch(lower);
  }

  String? _firstMatch(String value, List<RegExp> patterns) {
    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final group = match?.group(1);
      if (group != null) return _trimClause(group);
    }
    return null;
  }

  String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _trimClause(String value) {
    return _clean(value)
        .replaceAll(RegExp(r'^[,.:;\s]+'), '')
        .replaceAll(RegExp(r'["“”]+'), '')
        .replaceAll(RegExp(r'[.!?]+$'), '')
        .trim();
  }

  String _titleName(String value) {
    return _trimClause(value)
        .split(RegExp(r'\s+'))
        .take(3)
        .map((part) {
          if (part.isEmpty) return part;
          return part.substring(0, 1).toUpperCase() +
              part.substring(1).toLowerCase();
        })
        .join(' ');
  }

  bool _looksLikeActivity(String value) {
    final first = _normalize(value).split(' ').firstOrNull ?? '';
    return {
      'building',
      'using',
      'trying',
      'working',
      'running',
      'facing',
      'asking',
      'looking',
      'testing',
      'not',
      'going',
      'doing',
      'writing',
      'fixing',
      'creating',
      'making',
      'interested',
      'glad',
      'happy',
      'sad',
      'sorry',
      'sure',
      'just',
      'really',
      'currently',
      'feeling',
    }.contains(first);
  }

  bool _temporaryAnimalMention(String normalized) {
    return normalized.contains('saw ') ||
        normalized.contains('today') ||
        normalized.contains('near my house') ||
        normalized.contains('passed by');
  }

  String _numberWordToDigit(String value) {
    final lower = value.toLowerCase();
    const words = {
      'one': '1',
      'two': '2',
      'three': '3',
      'four': '4',
      'five': '5',
      'six': '6',
      'seven': '7',
      'eight': '8',
      'nine': '9',
      'ten': '10',
    };
    return words[lower] ?? value;
  }

  String _pluralizePet(String animal, String count) {
    final singular = animal.toLowerCase().replaceAll(RegExp(r's$'), '');
    return count == '1' ? singular : '${singular}s';
  }

  String _uiPreferenceValue(String lower) {
    if (lower.contains('preserve') || lower.contains('same ui')) {
      return 'User prefers preserving existing UI identity instead of redesigning it.';
    }
    if (lower.contains('premium')) return 'User prefers premium UI design.';
    if (lower.contains('minimal')) return 'User prefers minimal UI design.';
    return 'User prefers lightweight UI design.';
  }

  String _projectRequirementKey(String value) {
    final normalized = _normalize(value);
    if (normalized.contains('endpoint')) return 'project_endpoint_requirement';
    if (normalized.contains('flutter')) return 'project_flutter_requirement';
    if (normalized.contains('android')) return 'project_android_requirement';
    if (normalized.contains('web')) return 'project_web_requirement';
    if (normalized.contains('voice') || normalized.contains('live')) {
      return 'project_live_voice_requirement';
    }
    return 'project_requirement';
  }

  String _stableCustomKey(String value) {
    final words = _normalize(
      value,
    ).split(' ').where((word) => word.length > 2).take(4).join('_');
    return words.isEmpty ? 'custom_memory_${DateTime.now().millisecondsSinceEpoch}' : words;
  }

  String _memorySentence(String content) {
    final trimmed = _trimClause(content);
    if (trimmed.toLowerCase().startsWith('user ')) return '$trimmed.';
    if (trimmed.toLowerCase().startsWith('i ')) {
      return 'User ${trimmed.substring(2)}.';
    }
    return trimmed.endsWith('.') ? trimmed : '$trimmed.';
  }

  String _typeForKey(String key) {
    if (key.startsWith('preferred')) return 'preference';
    if (key.startsWith('project')) return 'project_memory';
    if (key == 'nickname' || key == 'user_name' || key == 'pets') {
      return 'personal_fact';
    }
    return 'ignore';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
