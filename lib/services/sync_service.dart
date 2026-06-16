import 'dart:async';
import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart' as pg;
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:uuid/uuid.dart';

import '../models.dart';

class AuthResult {
  const AuthResult({required this.user, required this.token, this.remoteState});

  final UserAccount user;
  final String token;
  final PersistedAppState? remoteState;
}

class SyncService {
  static const _uuid = Uuid();
  static const defaultWebApiBaseUrl = 'http://127.0.0.1:3000';

  supa.SupabaseClient? _realtimeClient;
  supa.RealtimeChannel? _realtimeChannel;
  String _realtimeKey = '';

  bool shouldUseDirectPostgres(SyncSettings settings) =>
      !kIsWeb && settings.apiBaseUrl.trim().isEmpty;

  supa.SupabaseClient _supabaseAuthClient(SyncSettings settings) {
    return supa.SupabaseClient(
      settings.supabaseUrl,
      settings.supabaseAnonKey,
      authOptions: const supa.FlutterAuthClientOptions(
        localStorage: supa.EmptyLocalStorage(),
        authFlowType: supa.AuthFlowType.implicit,
      ),
    );
  }

  supa.SupabaseClient _supabaseSessionClient(
    SyncSettings settings,
    String token,
  ) {
    return supa.SupabaseClient(
      settings.supabaseUrl,
      settings.supabaseAnonKey,
      headers: {'Authorization': 'Bearer $token'},
      accessToken: () async => token,
      authOptions: const supa.FlutterAuthClientOptions(
        localStorage: supa.EmptyLocalStorage(),
        authFlowType: supa.AuthFlowType.implicit,
      ),
    );
  }

  Future<AuthResult> signUp(
    String username,
    String password,
    SyncSettings settings,
  ) async {
    if (settings.useSupabase) {
      final client = _supabaseAuthClient(settings);
      final res = await client.auth.signUp(email: username, password: password);
      if (res.user == null || res.session == null) {
        throw Exception('Supabase signup failed. Please ensure you provide a valid email format.');
      }
      return AuthResult(
        user: UserAccount(
          id: res.user!.id,
          username: username,
          displayName: username.split('@').first,
        ),
        token: res.session!.accessToken,
      );
    }

    if (shouldUseDirectPostgres(settings)) {
      return _directSignUp(username, password, settings.database);
    }

    final response = await _postJson(settings, '/api/auth/signup', {
      'username': username,
      'password': password,
      'dbConfig': _databasePayload(settings.database),
    });
    final data = _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Unable to sign up.');
    }
    return AuthResult(
      user: UserAccount.fromJson(Map<String, dynamic>.from(data['user'])),
      token: stringValue(data['token']),
      remoteState: data['state'] is Map
          ? PersistedAppState.fromJson(Map<String, dynamic>.from(data['state']))
          : null,
    );
  }

  Future<AuthResult> login(
    String username,
    String password,
    SyncSettings settings,
  ) async {
    if (settings.useSupabase) {
      final client = _supabaseAuthClient(settings);
      final res = await client.auth.signInWithPassword(email: username, password: password);
      if (res.user == null || res.session == null) {
        throw Exception('Supabase login failed.');
      }
      
      PersistedAppState? remoteState;
      try {
        remoteState = await _supabasePullStateForUser(client, res.user!.id);
      } catch (e) {
        debugPrint('Failed to pull initial state from Supabase: $e');
      }

      return AuthResult(
        user: UserAccount(
          id: res.user!.id,
          username: username,
          displayName: username.split('@').first,
        ),
        token: res.session!.accessToken,
        remoteState: remoteState,
      );
    }

    if (shouldUseDirectPostgres(settings)) {
      return _directLogin(username, password, settings.database);
    }

    final response = await _postJson(settings, '/api/auth/login', {
      'username': username,
      'password': password,
      'dbConfig': _databasePayload(settings.database),
    });
    final data = _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Unable to log in.');
    }
    return AuthResult(
      user: UserAccount.fromJson(Map<String, dynamic>.from(data['user'])),
      token: stringValue(data['token']),
      remoteState: data['state'] is Map
          ? PersistedAppState.fromJson(Map<String, dynamic>.from(data['state']))
          : null,
    );
  }

  Future<PersistedAppState?> pullRemoteState(
    String token,
    SyncSettings settings,
  ) async {
    if (!settings.enabled || token.isEmpty) return null;
    
    if (settings.useSupabase) {
      if (token.startsWith('direct:')) {
        throw Exception('Your current session is from Postgres. Please log out and sign in to Supabase to sync.');
      }
      final client = _supabaseSessionClient(settings, token);
      final userId = _supabaseUserIdFromToken(token);
      return _supabasePullStateForUser(client, userId);
    }

    if (shouldUseDirectPostgres(settings)) {
      if (!token.startsWith('direct:')) {
        throw Exception('Your current session is from Supabase. Please log out and sign in to Postgres to sync.');
      }
      return _directPullState(token, settings);
    }

    final response = await _postJson(
      settings,
      '/api/sync/pull',
      {'dbConfig': _databasePayload(settings.database)},
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Unable to pull remote state.');
    }
    
    final combined = <String, dynamic>{};
    if (data['settings'] is Map) {
      combined.addAll(Map<String, dynamic>.from(data['settings']));
    }
    if (data['sessions'] is List) {
      combined['sessions'] = (data['sessions'] as List).map((s) => s['session']).toList();
    }
    return combined.isNotEmpty ? PersistedAppState.fromJson(combined) : null;
  }

  Future<void> subscribeToRemoteChanges(
    String token,
    SyncSettings settings, {
    required void Function(PersistedAppState state) onSettings,
    required void Function(Session session) onSession,
    void Function(Object error)? onError,
  }) async {
    if (!settings.enabled || !settings.useSupabase || token.isEmpty) {
      await unsubscribeRemoteChanges();
      return;
    }
    if (token.startsWith('direct:')) {
      await unsubscribeRemoteChanges();
      return;
    }

    final userId = _supabaseUserIdFromToken(token);
    if (userId.isEmpty) return;

    final key = '${settings.supabaseUrl}|$userId';
    if (_realtimeChannel != null && _realtimeKey == key) return;
    await unsubscribeRemoteChanges();

    final client = _supabaseSessionClient(settings, token);
    final channel = client
        .channel('adoetzgpt-sync-$userId')
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_settings',
          filter: supa.PostgresChangeFilter(
            type: supa.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            try {
              final row = payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord;
              final remote = _stateFromValue(
                row['state'],
                allowEmptySessions: true,
              );
              if (remote != null) onSettings(remote);
            } catch (error) {
              onError?.call(error);
            }
          },
        )
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_sessions',
          filter: supa.PostgresChangeFilter(
            type: supa.PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            try {
              final row = payload.newRecord.isNotEmpty
                  ? payload.newRecord
                  : payload.oldRecord;
              final sessionJson = _jsonMapFromValue(row['session']);
              if (sessionJson != null) {
                onSession(Session.fromJson(sessionJson));
              }
            } catch (error) {
              onError?.call(error);
            }
          },
        );

    channel.subscribe((status, error) {
      if (status == supa.RealtimeSubscribeStatus.channelError ||
          status == supa.RealtimeSubscribeStatus.timedOut) {
        onError?.call(error ?? 'Supabase realtime subscription failed.');
      }
    });

    _realtimeClient = client;
    _realtimeChannel = channel;
    _realtimeKey = key;
  }

  Future<void> unsubscribeRemoteChanges() async {
    final client = _realtimeClient;
    final channel = _realtimeChannel;
    _realtimeClient = null;
    _realtimeChannel = null;
    _realtimeKey = '';
    if (client == null || channel == null) return;
    try {
      await client.removeChannel(channel);
    } finally {
      await client.dispose();
    }
  }

  Future<void> pushRemoteState(
    PersistedAppState state,
    SyncSettings settings, {
    int? lastSyncAt,
    Iterable<String>? changedSessionIds,
    bool settingsChanged = true,
  }) async {
    if (!settings.enabled || state.authToken.isEmpty) return;
    final token = state.authToken;
    final changedIds = changedSessionIds
        ?.where((id) => id.trim().isNotEmpty)
        .toSet();
    if (!settingsChanged && changedIds != null && changedIds.isEmpty) return;
    
    final errors = <String>[];

    if (settings.useSupabase) {
      if (token.startsWith('direct:')) {
        throw Exception('Your current session is from Postgres. Please log out and sign in to Supabase to sync.');
      }
      final client = _supabaseSessionClient(settings, token);
      final userId = state.currentUser?.id;
      if (userId == null) return;
      
      try {
        if (settingsChanged) {
          final settingsJson = _remoteStateJson(state);
          settingsJson.remove('sessions');
          await client.from('user_settings').upsert({
            'user_id': userId,
            'state': settingsJson,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
        
        final sessionCountRes = await client
            .from('chat_sessions')
            .select('id')
            .eq('user_id', userId)
            .limit(1);
        final isNewDb = sessionCountRes.isEmpty;
        
        final sessionsToPush = isNewDb ? state.sessions : _sessionsForDelta(
          state,
          lastSyncAt: lastSyncAt,
          changedSessionIds: changedIds,
        );
            
        for (final s in sessionsToPush) {
          await client.from('chat_sessions').upsert({
            'id': s.id,
            'user_id': userId,
            'session': s.toJson(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
        }
      } catch (e) {
        errors.add('Supabase Primary Error: $e');
      }
    } else if (shouldUseDirectPostgres(settings)) {
      if (!token.startsWith('direct:')) {
        throw Exception('Your current session is from Supabase. Please log out and sign in to Postgres to sync.');
      }
      try {
        await _directPushState(
          token,
          state,
          settings.database,
          lastSyncAt: lastSyncAt,
          changedSessionIds: changedIds,
          settingsChanged: settingsChanged,
        );
      } catch (e) {
        errors.add('Postgres Primary Error: $e');
      }
    } else {
      try {
        final sessionsToPush = _sessionsForDelta(
          state,
          lastSyncAt: lastSyncAt,
          changedSessionIds: changedIds,
        );
        final response = await _postJson(
          settings,
          '/api/sync/push',
          {
            'settings': (() { 
              final s = _remoteStateJson(state); 
              s.remove('sessions'); 
              return s; 
            })(),
            'sessions': sessionsToPush
                .map((s) => {'id': s.id, 'session': s.toJson()})
                .toList(),
            'dbConfig': _databasePayload(settings.database),
          },
          headers: {'Authorization': 'Bearer $token'},
        );
        final data = _readJson(response);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(data['error'] ?? 'Unable to push remote state.');
        }
      } catch (e) {
        errors.add('API Primary Error: $e');
      }
    }

    if (settings.autoSyncBackups) {
      for (final db in settings.backupDatabases) {
        if (db.databaseUrl.trim().isEmpty || db.database.trim().isEmpty) continue;
        try {
          if (settings.useSupabase) {
            await _directPushStateWithClonedUser(
              token: token,
              state: state,
              backupDb: db,
              clonedUserId: state.currentUser!.id,
              clonedUsername: state.currentUser!.username,
              clonedPasswordHash: state.cachedPasswordHash != null && state.cachedPasswordHash!.isNotEmpty 
                  ? state.cachedPasswordHash! 
                  : r'$2a$10$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              lastSyncAt: lastSyncAt,
              changedSessionIds: changedIds,
              settingsChanged: settingsChanged,
            );
          } else if (shouldUseDirectPostgres(settings)) {
            String? userId;
            String? username;
            String? passwordHash;

            try {
              final primaryConn = await _open(settings.database);
              try {
                final userRow = await primaryConn.execute(
                  pg.Sql('SELECT id, username, password_hash FROM ${_quote(_schema(settings.database))}.users WHERE id = \$1'),
                  parameters: [state.currentUser?.id],
                ).then((r) => r.firstOrNull);
                
                if (userRow != null) {
                  userId = userRow[0] as String;
                  username = userRow[1] as String;
                  passwordHash = userRow[2] as String;
                }
              } finally {
                await primaryConn.close();
              }
            } catch (_) {
              // Primary is down, fallback to local cache
              userId = state.currentUser?.id;
              username = state.currentUser?.username;
              passwordHash = state.cachedPasswordHash;
            }

            if (userId == null || username == null) {
              throw Exception('Cannot clone to backup: user account not found in primary DB or local cache.');
            }
            
            await _directPushStateWithClonedUser(
              token: token,
              state: state,
              backupDb: db,
              clonedUserId: userId,
              clonedUsername: username,
              clonedPasswordHash: passwordHash != null && passwordHash.isNotEmpty
                  ? passwordHash
                  : r'$2a$10$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX',
              lastSyncAt: lastSyncAt,
              changedSessionIds: changedIds,
              settingsChanged: settingsChanged,
            );
          }
        } catch (e) {
          errors.add('Backup Error (${db.databaseUrl}): $e');
        }
      }
    }

    if (errors.isNotEmpty) {
      throw Exception('Partial Sync Failure:\n${errors.join('\n')}');
    }
  }

  Future<bool> healthCheck(SyncSettings settings) async {
    if (!kIsWeb && settings.apiBaseUrl.trim().isEmpty) return false;
    try {
      final response = await http
          .get(_apiUri(settings, '/api/health'))
          .timeout(const Duration(seconds: 4));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Uri _apiUri(SyncSettings settings, String path) {
    final base = _apiBaseUrl(settings).replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base$path');
  }

  String _apiBaseUrl(SyncSettings settings) {
    final configured = settings.apiBaseUrl.trim();
    if (configured.isNotEmpty) return configured;
    return kIsWeb ? defaultWebApiBaseUrl : '';
  }

  Future<http.Response> _postJson(
    SyncSettings settings,
    String path,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
  }) async {
    try {
      return await http
          .post(
            _apiUri(settings, path),
            headers: {'Content-Type': 'application/json', ...headers},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (error) {
      throw Exception(_syncApiNetworkMessage(settings, error));
    }
  }


  String _syncApiNetworkMessage(SyncSettings settings, Object error) {
    final apiBaseUrl = _apiBaseUrl(settings);
    if (kIsWeb && settings.apiBaseUrl.trim().isEmpty) {
      return 'Unable to reach the sync API at $apiBaseUrl. For Chrome login, start the original React/Node server with npm run dev, or enter a Sync API URL in Advanced Settings.';
    }
    return 'Unable to reach the sync API at $apiBaseUrl. ${error.toString().replaceFirst('Exception: ', '')}';
  }

  Map<String, dynamic> _readJson(http.Response response) {
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw Exception(
        response.body.contains('<html')
            ? 'Sync API URL points to the web app instead of the API server.'
            : 'Sync API did not return JSON.',
      );
    }
    return Map<String, dynamic>.from(
      jsonDecode(response.body.isEmpty ? '{}' : response.body),
    );
  }

  Future<PersistedAppState?> _supabasePullStateForUser(
    supa.SupabaseClient client,
    String userId,
  ) async {
    if (userId.isEmpty) return null;

    final settingsRes = await client
        .from('user_settings')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    final sessionsRes = await client
        .from('chat_sessions')
        .select()
        .eq('user_id', userId);

    final combined = <String, dynamic>{};
    if (settingsRes != null && settingsRes['state'] != null) {
      final settingsState = _jsonMapFromValue(settingsRes['state']);
      if (settingsState != null) combined.addAll(settingsState);
    }
    if (sessionsRes.isNotEmpty) {
      combined['sessions'] = sessionsRes
          .map((row) => _jsonMapFromValue(row['session']))
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return combined.isNotEmpty ? PersistedAppState.fromJson(combined) : null;
  }

  String _supabaseUserIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '';
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      return stringValue(jsonDecode(payload)['sub']);
    } catch (_) {
      return '';
    }
  }

  Map<String, dynamic> _databasePayload(DatabaseSettings db) => {
    'databaseUrl': db.databaseUrl.trim(),
    'database': db.database.trim(),
    'schemaName': db.schemaName.trim(),
    'user': db.user.trim(),
    'password': db.password,
    'port': db.port.trim(),
  };

  Map<String, dynamic> _remoteStateJson(PersistedAppState state) {
    final json = state.toJson(includeSecrets: true);
    json['authToken'] = '';
    json.remove('lastSyncAt');
    final sync = Map<String, dynamic>.from(json['syncSettings']);
    final db = Map<String, dynamic>.from(sync['database']);
    db['password'] = '';
    sync['database'] = db;
    json['syncSettings'] = sync;
    json.remove('cachedPasswordHash');
    return json;
  }

  List<Session> _sessionsForDelta(
    PersistedAppState state, {
    int? lastSyncAt,
    Set<String>? changedSessionIds,
  }) {
    if (changedSessionIds != null) {
      if (changedSessionIds.isEmpty) return const [];
      return state.sessions
          .where((session) => changedSessionIds.contains(session.id))
          .toList();
    }
    if (lastSyncAt != null) {
      return state.sessions
          .where((session) => session.updatedAt > lastSyncAt)
          .toList();
    }
    return state.sessions;
  }

  Future<AuthResult> _directSignUp(
    String usernameRaw,
    String password,
    DatabaseSettings db,
  ) async {
    final username = usernameRaw.trim().toLowerCase();
    if (!username.contains('@') || !username.contains('.')) {
      throw Exception('Please provide a valid email address.');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }

    final conn = await _open(db);
    try {
      final schema = _schema(db);
      await _ensurePostgres(conn, schema);
      final id = _uuid.v4();
      final hash = BCrypt.hashpw(
        password,
        BCrypt.gensalt(logRounds: 12, prefix: r'$2a'),
      );
      final result = await conn.execute(
        pg.Sql(
          'INSERT INTO ${_quote(schema)}.users (id, username, display_name, password_hash) VALUES (\$1, \$2, \$3, \$4) RETURNING id, username, email, display_name',
        ),
        parameters: [id, username, username, hash],
      );
      await conn.execute(
        pg.Sql(
          'INSERT INTO ${_quote(schema)}.user_settings (user_id, state) VALUES (\$1, \'{}\'::jsonb)',
        ),
        parameters: [id],
      );
      final user = _publicUser(result.first.toColumnMap());
      return AuthResult(user: user, token: _directToken(user.id));
    } catch (error) {
      final message =
          error.toString().contains('duplicate') ||
              error.toString().contains('23505')
          ? 'Username is already registered.'
          : error.toString();
      throw Exception(message.replaceFirst('Exception: ', ''));
    } finally {
      await conn.close();
    }
  }

  Future<AuthResult> _directLogin(
    String usernameRaw,
    String password,
    DatabaseSettings db,
  ) async {
    final username = usernameRaw.trim().toLowerCase();
    final conn = await _open(db);
    try {
      final schema = _schema(db);
      await _ensurePostgres(conn, schema);
      final result = await conn.execute(
        pg.Sql('SELECT * FROM ${_quote(schema)}.users WHERE username = \$1'),
        parameters: [username],
      );
      if (result.isEmpty) throw Exception('Invalid username or password.');
      final row = result.first.toColumnMap();
      if (!BCrypt.checkpw(password, stringValue(row['password_hash']))) {
        throw Exception('Invalid username or password.');
      }
      final user = _publicUser(row);
      final remote = await _directPullState(_directToken(user.id), SyncSettings(database: db));
      return AuthResult(
        user: user,
        token: _directToken(user.id),
        remoteState: remote,
      );
    } finally {
      await conn.close();
    }
  }

  Future<PersistedAppState?> _directPullState(
    String token,
    SyncSettings settings,
  ) async {
    final userId = _directUserId(token);
    if (userId.isEmpty) throw Exception('Invalid direct Postgres auth token.');
    
    final databases = [settings.database, ...settings.backupDatabases];
    final errors = <String>[];

    for (final db in databases) {
      if (db.databaseUrl.trim().isEmpty) continue;
      try {
        final conn = await _open(db);
        try {
          final schema = _schema(db);
          await _ensurePostgres(conn, schema);
          final settingsResult = await conn.execute(
            pg.Sql('SELECT state FROM ${_quote(schema)}.user_settings WHERE user_id = \$1'),
            parameters: [userId],
          );
          final sessionsResult = await conn.execute(
            pg.Sql('SELECT id, session FROM ${_quote(schema)}.chat_sessions WHERE user_id = \$1'),
            parameters: [userId],
          );
          
          final combined = <String, dynamic>{};
          if (settingsResult.isNotEmpty && settingsResult.first[0] != null) {
            final settingsState = _jsonMapFromValue(settingsResult.first[0]);
            if (settingsState != null) combined.addAll(settingsState);
          }
          if (sessionsResult.isNotEmpty) {
            combined['sessions'] = sessionsResult
                .map((row) => _jsonMapFromValue(row[1]))
                .whereType<Map<String, dynamic>>()
                .toList();
          }
          return combined.isNotEmpty ? PersistedAppState.fromJson(combined) : null;
        } finally {
          await conn.close();
        }
      } catch (e) {
        errors.add('Failed to pull from ${db.databaseUrl}: $e');
      }
    }

    if (errors.isNotEmpty) {
      debugPrint('Pull State Failover Errors:\n${errors.join('\n')}');
      throw Exception('Failed to connect to all databases (Primary + Backups).');
    }
    return null;
  }

  Future<void> _directPushStateWithClonedUser({
    required String token,
    required PersistedAppState state,
    required DatabaseSettings backupDb,
    required String clonedUserId,
    required String clonedUsername,
    required String clonedPasswordHash,
    int? lastSyncAt,
    Set<String>? changedSessionIds,
    bool settingsChanged = true,
  }) async {
    final conn = await _open(backupDb);
    try {
      final schema = _schema(backupDb);
      await _ensurePostgres(conn, schema);

      final userResult = await conn.execute(
        pg.Sql.named(
          'INSERT INTO ${_quote(schema)}."users" (id, username, password_hash, display_name) '
          'VALUES (@id, @username, @passwordHash, @username) '
          'ON CONFLICT (username) DO UPDATE SET password_hash = @passwordHash, updated_at = CURRENT_TIMESTAMP '
          'RETURNING id',
        ),
        parameters: {
          'id': clonedUserId,
          'username': clonedUsername,
          'passwordHash': clonedPasswordHash,
        },
      );

      final targetUserId = userResult.first[0] as String;
      
      await conn.execute('BEGIN');
      if (settingsChanged) {
        final settingsJson = state.toJson(includeSecrets: true);
        settingsJson
          ..remove('sessions')
          ..remove('lastSyncAt');
        await conn.execute(
          pg.Sql.named(
            'INSERT INTO ${_quote(schema)}."user_settings" (user_id, state) '
            'VALUES (@id, @state::jsonb) '
            'ON CONFLICT (user_id) DO UPDATE SET state = @state::jsonb, updated_at = CURRENT_TIMESTAMP',
          ),
          parameters: {
            'id': targetUserId,
            'state': jsonEncode(settingsJson),
          },
        );
      }
      
      final sessionCountResult = await conn.execute(
        pg.Sql('SELECT COUNT(*) FROM ${_quote(schema)}."chat_sessions" WHERE user_id = \$1'),
        parameters: [targetUserId],
      );
      final isNewDb = (sessionCountResult.first[0] as int) == 0;
      
      final sessionsToPush = isNewDb ? state.sessions : _sessionsForDelta(
        state,
        lastSyncAt: lastSyncAt,
        changedSessionIds: changedSessionIds,
      );
      for (final s in sessionsToPush) {
        await conn.execute(
          pg.Sql.named(
            'INSERT INTO ${_quote(schema)}."chat_sessions" (id, user_id, session) '
            'VALUES (@sid, @uid, @session::jsonb) '
            'ON CONFLICT (id) DO UPDATE SET session = @session::jsonb, updated_at = CURRENT_TIMESTAMP',
          ),
          parameters: {
            'sid': s.id,
            'uid': targetUserId,
            'session': jsonEncode(s.toJson()),
          },
        );
      }
      await conn.execute('COMMIT');
    } finally {
      await conn.close();
    }
  }

  Future<void> _directPushState(
    String token,
    PersistedAppState state,
    DatabaseSettings db,
    {
    int? lastSyncAt,
    Set<String>? changedSessionIds,
    bool settingsChanged = true,
  }
  ) async {
    final userId = _directUserId(token);
    if (userId.isEmpty) throw Exception('Invalid direct Postgres auth token.');

    final conn = await _open(db);
    try {
      final schema = _schema(db);
      await _ensurePostgres(conn, schema);

      await conn.execute('BEGIN');
      if (settingsChanged) {
        final stateJson = _remoteStateJson(state);
        stateJson.remove('sessions');
        await conn.execute(
          pg.Sql(
            'INSERT INTO ${_quote(schema)}.user_settings (user_id, state, updated_at) VALUES (\$1, \$2::jsonb, NOW()) '
            'ON CONFLICT (user_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()',
          ),
          parameters: [userId, jsonEncode(stateJson)],
        );
      }

      final sessionCountResult = await conn.execute(
        pg.Sql('SELECT COUNT(*) FROM ${_quote(schema)}."chat_sessions" WHERE user_id = \$1'),
        parameters: [userId],
      );
      final isNewDb = (sessionCountResult.first[0] as int) == 0;
      
      final sessionsToPush = isNewDb ? state.sessions : _sessionsForDelta(
        state,
        lastSyncAt: lastSyncAt,
        changedSessionIds: changedSessionIds,
      );
          
      for (final s in sessionsToPush) {
        await conn.execute(
          pg.Sql(
            'INSERT INTO ${_quote(schema)}.chat_sessions (id, user_id, session, updated_at) VALUES (\$1, \$2, \$3::jsonb, NOW()) '
            'ON CONFLICT (id) DO UPDATE SET session = EXCLUDED.session, updated_at = NOW()',
          ),
          parameters: [s.id, userId, jsonEncode(s.toJson())],
        );
      }
      await conn.execute('COMMIT');
    } finally {
      await conn.close();
    }
  }

  Future<pg.Connection> _open(DatabaseSettings db) async {
    if (db.databaseUrl.trim().isEmpty ||
        db.database.trim().isEmpty ||
        db.user.trim().isEmpty) {
      throw Exception('Postgres settings are required.');
    }
    final needsSsl = db.databaseUrl.contains('supabase') ||
        db.databaseUrl.contains('neon.tech') ||
        db.databaseUrl.contains('render.com') ||
        db.databaseUrl.contains('sslmode=require');

    final port = int.tryParse(db.port.trim()) ?? 5432;
    final host = db.databaseUrl.trim();
    if (host.startsWith('postgres://') || host.startsWith('postgresql://')) {
      return pg.Connection.openFromUrl(_postgresUrlWithOverrides(host, db));
    }
    return await pg.Connection.open(
      pg.Endpoint(
        host: host,
        database: db.database.trim(),
        username: db.user.trim(),
        password: db.password,
        port: port,
      ),
      settings: pg.ConnectionSettings(
        sslMode: needsSsl ? pg.SslMode.require : pg.SslMode.disable,
      ),
    );
  }

  String _postgresUrlWithOverrides(String value, DatabaseSettings db) {
    final uri = Uri.parse(value);
    final scheme = uri.scheme == 'postgres' ? 'postgresql' : uri.scheme;
    final host = uri.host;
    final port = db.port.trim().isNotEmpty
        ? ':${db.port.trim()}'
        : (uri.hasPort ? ':${uri.port}' : '');
    final database = db.database.trim().isNotEmpty
        ? db.database.trim()
        : (uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'postgres');
    final userInfo = db.user.trim().isNotEmpty
        ? '${Uri.encodeComponent(db.user.trim())}:${Uri.encodeComponent(db.password)}@'
        : (uri.userInfo.isNotEmpty ? '${uri.userInfo}@' : '');
    final query = uri.query.isEmpty ? '?sslmode=disable' : '?${uri.query}';
    return '$scheme://$userInfo$host$port/$database$query';
  }

  String _schema(DatabaseSettings db) {
    final schema = db.schemaName.trim().isEmpty
        ? 'adoetzgpt'
        : db.schemaName.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,62}$').hasMatch(schema)) {
      throw Exception('Invalid Postgres schema name.');
    }
    return schema;
  }

  String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';

  Future<void> _ensurePostgres(pg.Connection conn, String schema) async {
    final q = _quote(schema);
    await conn.execute('CREATE SCHEMA IF NOT EXISTS $q');
    await conn.execute('''
CREATE TABLE IF NOT EXISTS $q.users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  email TEXT UNIQUE,
  display_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)''');
    await conn.execute('''
CREATE TABLE IF NOT EXISTS $q.user_settings (
  user_id TEXT PRIMARY KEY REFERENCES $q.users(id) ON DELETE CASCADE,
  state JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)''');
    await conn.execute('''
CREATE TABLE IF NOT EXISTS $q.chat_sessions (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES $q.users(id) ON DELETE CASCADE,
  session JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)''');
  }

  UserAccount _publicUser(Map<String, dynamic> row) {
    final username = stringValue(
      row['username'],
      stringValue(row['email'], 'user'),
    );
    return UserAccount(
      id: stringValue(row['id']),
      username: username,
      email: row['email'] == null ? null : stringValue(row['email']),
      displayName: stringValue(row['display_name'], username),
    );
  }

  PersistedAppState? _stateFromValue(
    Object? value, {
    bool allowEmptySessions = false,
  }) {
    final map = _jsonMapFromValue(value);
    return map == null
        ? null
        : PersistedAppState.fromJson(
            map,
            allowEmptySessions: allowEmptySessions,
          );
  }

  Map<String, dynamic>? _jsonMapFromValue(Object? value) {
    if (value == null) return null;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  String _directToken(String userId) =>
      'direct:${base64Url.encode(utf8.encode(userId))}';

  String _directUserId(String token) {
    if (!token.startsWith('direct:')) return '';
    try {
      return utf8.decode(base64Url.decode(token.substring(7)));
    } catch (_) {
      return '';
    }
  }
}
