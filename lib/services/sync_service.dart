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

  bool shouldUseDirectPostgres(SyncSettings settings) =>
      !kIsWeb && settings.apiBaseUrl.trim().isEmpty;

  Future<AuthResult> signUp(
    String username,
    String password,
    SyncSettings settings,
  ) async {
    if (settings.useSupabase) {
      final client = supa.SupabaseClient(
        settings.supabaseUrl, 
        settings.supabaseAnonKey,
        authOptions: const supa.FlutterAuthClientOptions(
          localStorage: supa.EmptyLocalStorage(),
          authFlowType: supa.AuthFlowType.implicit,
        ),
      );
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
      final client = supa.SupabaseClient(
        settings.supabaseUrl, 
        settings.supabaseAnonKey,
        authOptions: const supa.FlutterAuthClientOptions(
          localStorage: supa.EmptyLocalStorage(),
          authFlowType: supa.AuthFlowType.implicit,
        ),
      );
      final res = await client.auth.signInWithPassword(email: username, password: password);
      if (res.user == null || res.session == null) {
        throw Exception('Supabase login failed.');
      }
      
      PersistedAppState? remoteState;
      try {
        final stateRes = await client.from('app_states').select().eq('id', res.user!.id).maybeSingle();
        if (stateRes != null && stateRes['state'] != null) {
          remoteState = PersistedAppState.fromJson(Map<String, dynamic>.from(stateRes['state']));
        }
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
      final client = supa.SupabaseClient(
        settings.supabaseUrl, 
        settings.supabaseAnonKey,
        headers: {'Authorization': 'Bearer $token'},
        authOptions: const supa.FlutterAuthClientOptions(
          localStorage: supa.EmptyLocalStorage(),
          authFlowType: supa.AuthFlowType.implicit,
        ),
      );
      final res = await client.from('app_states').select();
      if (res.isNotEmpty && res.first['state'] != null) {
        return PersistedAppState.fromJson(Map<String, dynamic>.from(res.first['state']));
      }
      return null;
    }

    if (shouldUseDirectPostgres(settings)) {
      return _directPullState(token, settings.database);
    }

    final response = await _postJson(
      settings,
      '/api/sync/state/pull',
      {'dbConfig': _databasePayload(settings.database)},
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = _readJson(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(data['error'] ?? 'Unable to pull remote state.');
    }
    return data['state'] is Map
        ? PersistedAppState.fromJson(Map<String, dynamic>.from(data['state']))
        : null;
  }

  Future<void> pushRemoteState(PersistedAppState state, SyncSettings settings) async {
    if (!settings.enabled || state.authToken.isEmpty) return;
    final token = state.authToken;
    
    bool pushSuccess = false;

    if (settings.useSupabase) {
      final client = supa.SupabaseClient(
        settings.supabaseUrl, 
        settings.supabaseAnonKey, 
        headers: {'Authorization': 'Bearer $token'},
        authOptions: const supa.FlutterAuthClientOptions(
          localStorage: supa.EmptyLocalStorage(),
          authFlowType: supa.AuthFlowType.implicit,
        ),
      );
      final userId = state.currentUser?.id;
      if (userId == null) return;
      
      await client.from('app_states').upsert({
        'id': userId,
        'state': state.toJson(includeSecrets: true),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      pushSuccess = true;
    } else if (shouldUseDirectPostgres(settings)) {
      await _directPushState(token, state, settings.database);
      pushSuccess = true;
    } else {
      final response = await _postJson(
        settings,
        '/api/sync/state/push',
        {
          'state': _remoteStateJson(state),
          'dbConfig': _databasePayload(settings.database),
        },
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = _readJson(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['error'] ?? 'Unable to push remote state.');
      }
      pushSuccess = true;
    }

    if (pushSuccess && settings.autoSyncBackups) {
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
              clonedPasswordHash: r'$2a$10$XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX', // Dummy bcrypt hash
            );
          } else if (shouldUseDirectPostgres(settings)) {
            final primaryConn = await _open(settings.database);
            try {
              final userRow = await primaryConn.execute(
                pg.Sql('SELECT id, username, password_hash FROM ${_quote(_schema(settings.database))}.users WHERE id = \$1'),
                parameters: [state.currentUser?.id],
              ).then((r) => r.firstOrNull);
              
              if (userRow == null) return;
              
              await _directPushStateWithClonedUser(
                token: token,
                state: state,
                backupDb: db,
                clonedUserId: userRow[0] as String,
                clonedUsername: userRow[1] as String,
                clonedPasswordHash: userRow[2] as String,
              );
            } finally {
              await primaryConn.close();
            }
          }
        } catch (e) {
          debugPrint('Backup push failed for ${db.databaseUrl}: $e');
        }
      }
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
    final sync = Map<String, dynamic>.from(json['syncSettings']);
    final db = Map<String, dynamic>.from(sync['database']);
    db['password'] = '';
    sync['database'] = db;
    json['syncSettings'] = sync;
    return json;
  }

  Future<AuthResult> _directSignUp(
    String usernameRaw,
    String password,
    DatabaseSettings db,
  ) async {
    final username = usernameRaw.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9._-]{3,64}$').hasMatch(username)) {
      throw Exception(
        'Username must be 3-64 characters using letters, numbers, dot, dash, or underscore.',
      );
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
          'INSERT INTO ${_quote(schema)}.app_states (user_id, state) VALUES (\$1, \'{}\'::jsonb)',
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
      final stateResult = await conn.execute(
        pg.Sql(
          'SELECT state FROM ${_quote(schema)}.app_states WHERE user_id = \$1',
        ),
        parameters: [user.id],
      );
      final remote = stateResult.isEmpty
          ? null
          : _stateFromValue(stateResult.first.toColumnMap()['state']);
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
    DatabaseSettings db,
  ) async {
    final userId = _directUserId(token);
    if (userId.isEmpty) throw Exception('Invalid direct Postgres auth token.');
    final conn = await _open(db);
    try {
      final schema = _schema(db);
      await _ensurePostgres(conn, schema);
      final result = await conn.execute(
        pg.Sql(
          'SELECT state FROM ${_quote(schema)}.app_states WHERE user_id = \$1',
        ),
        parameters: [userId],
      );
      return result.isEmpty
          ? null
          : _stateFromValue(result.first.toColumnMap()['state']);
    } finally {
      await conn.close();
    }
  }

  Future<void> _directPushStateWithClonedUser({
    required String token,
    required PersistedAppState state,
    required DatabaseSettings backupDb,
    required String clonedUserId,
    required String clonedUsername,
    required String clonedPasswordHash,
  }) async {
    final conn = await _open(backupDb);
    try {
      final schema = _schema(backupDb);
      await _ensurePostgres(conn, schema);

      await conn.execute(
        pg.Sql.named(
          'INSERT INTO ${_quote(schema)}."users" (id, username, password_hash, display_name) '
          'VALUES (@id, @username, @passwordHash, @username) '
          'ON CONFLICT (id) DO UPDATE SET username = @username, updated_at = CURRENT_TIMESTAMP',
        ),
        parameters: {
          'id': clonedUserId,
          'username': clonedUsername,
          'passwordHash': clonedPasswordHash,
        },
      );

      final stateJson = jsonEncode(state.toJson(includeSecrets: true));
      await conn.execute(
        pg.Sql.named(
          'INSERT INTO ${_quote(schema)}."app_states" (user_id, state) '
          'VALUES (@id, @state::jsonb) '
          'ON CONFLICT (user_id) DO UPDATE SET state = @state::jsonb, updated_at = CURRENT_TIMESTAMP',
        ),
        parameters: {
          'id': clonedUserId,
          'state': stateJson,
        },
      );
    } finally {
      await conn.close();
    }
  }

  Future<void> _directPushState(
    String token,
    PersistedAppState state,
    DatabaseSettings db,
  ) async {
    final userId = _directUserId(token);
    if (userId.isEmpty) throw Exception('Invalid direct Postgres auth token.');

    final conn = await _open(db);
    try {
      final schema = _schema(db);
      await _ensurePostgres(conn, schema);
      
      await conn.execute(
        pg.Sql(
          'INSERT INTO ${_quote(schema)}.app_states (user_id, state, updated_at) VALUES (\$1, \$2::jsonb, NOW()) '
          'ON CONFLICT (user_id) DO UPDATE SET state = EXCLUDED.state, updated_at = NOW()',
        ),
        parameters: [userId, jsonEncode(_remoteStateJson(state))],
      );
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
CREATE TABLE IF NOT EXISTS $q.app_states (
  user_id TEXT PRIMARY KEY REFERENCES $q.users(id) ON DELETE CASCADE,
  state JSONB NOT NULL DEFAULT '{}'::jsonb,
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

  PersistedAppState? _stateFromValue(Object? value) {
    if (value == null) return null;
    if (value is Map) {
      return PersistedAppState.fromJson(Map<String, dynamic>.from(value));
    }
    if (value is String && value.isNotEmpty) {
      return PersistedAppState.fromJson(
        Map<String, dynamic>.from(jsonDecode(value)),
      );
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
