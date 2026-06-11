import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _advanced = false;
  bool _loading = false;
  String _error = '';

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    final db = app.syncSettings.database;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      color: p.isDark
                          ? const Color(0xff121212)
                          : Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: p.outline.withValues(alpha: 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.onSurface.withValues(alpha: 0.10),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: const Center(child: SparkleMark(size: 48)),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Adoetz Chat Console',
                    style: TextStyle(
                      fontSize: 10,
                      color: p.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _signup ? 'Create Account' : 'Welcome Back',
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w300,
                      color: p.onSurface,
                    ),
                  ),
                  const SizedBox(height: 28),
                  GlassPanel(
                    padding: const EdgeInsets.all(24),
                    radius: 32,
                    backgroundColor: p.isDark
                        ? const Color(0xbf121212)
                        : Colors.white.withValues(alpha: 0.82),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label('Username', p),
                        _field(
                          controller: _username,
                          icon: LucideIcons.user,
                          hint: 'Enter username',
                        ),
                        const SizedBox(height: 16),
                        _label('Password', p),
                        _field(
                          controller: _password,
                          icon: LucideIcons.lock,
                          hint: 'Enter password',
                          obscure: true,
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () =>
                              setState(() => _advanced = !_advanced),
                          style: TextButton.styleFrom(
                            backgroundColor: p.surfaceDim,
                            foregroundColor: p.onSurfaceVariant,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(color: p.outline),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(LucideIcons.settings, size: 16),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Text(
                                  'Advanced Settings',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: _advanced ? 0.5 : 0,
                                duration: const Duration(milliseconds: 180),
                                child: const Icon(
                                  LucideIcons.chevronDown,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedCrossFade(
                          firstChild: const SizedBox.shrink(),
                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 18),
                            child: _AdvancedDbSettings(db: db),
                          ),
                          crossFadeState: _advanced
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          duration: const Duration(milliseconds: 220),
                        ),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: p.error.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: p.error.withValues(alpha: 0.28),
                              ),
                            ),
                            child: Text(
                              _error,
                              style: TextStyle(
                                color: p.error,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _canSubmit(app) && !_loading
                              ? () => _submit(app)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: p.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          child: Text(
                            _loading
                                ? 'CONNECTING...'
                                : (_signup ? 'CREATE ACCOUNT' : 'LOG IN'),
                          ),
                        ),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _signup = !_signup),
                          child: Text(
                            _signup
                                ? 'Already have an account? Log in'
                                : 'Need an account? Sign up',
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(child: Divider(color: p.outline)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: p.onSurfaceVariant,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: p.outline)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => app.continueAsGuest(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: p.onSurface,
                            side: BorderSide(
                              color: p.outline.withValues(alpha: 0.20),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.8,
                            ),
                          ),
                          child: const Text('CONTINUE AS GUEST'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, AppPalette p) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          color: p.onSurface.withValues(alpha: 0.86),
          fontWeight: FontWeight.w900,
          letterSpacing: 1.8,
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      textInputAction: obscure ? TextInputAction.done : TextInputAction.next,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 16),
        hintText: hint,
      ),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) {
        final app = context.read<AdoetzAppState>();
        if (_canSubmit(app)) _submit(app);
      },
    );
  }

  bool _canSubmit(AdoetzAppState app) {
    final db = app.syncSettings.database;
    return _username.text.trim().isNotEmpty &&
        _password.text.isNotEmpty &&
        db.databaseUrl.trim().isNotEmpty &&
        db.database.trim().isNotEmpty &&
        db.user.trim().isNotEmpty;
  }

  Future<void> _submit(AdoetzAppState app) async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      await app.authenticate(_username.text, _password.text, signUp: _signup);
    } catch (error) {
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _AdvancedDbSettings extends StatelessWidget {
  const _AdvancedDbSettings({required this.db});

  final DatabaseSettings db;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kIsWeb) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: p.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: p.primary.withValues(alpha: 0.24)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.globe, size: 15, color: p.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Chrome login uses the HTTP sync API. Direct PostgreSQL sockets are only available on Android/desktop.',
                    style: TextStyle(
                      color: p.onSurfaceVariant,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        _smallField(
          context,
          label: 'Sync API URL',
          icon: LucideIcons.server,
          value: app.syncSettings.apiBaseUrl,
          onChanged: (value) => app.updateSyncSettings(
            app.syncSettings.copyWith(apiBaseUrl: value),
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surfaceDim,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: p.outline),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'DATABASE SYNC SETTINGS',
                      style: TextStyle(
                        fontSize: 11,
                        color: p.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _smallField(
                context,
                label: 'Database URL',
                icon: LucideIcons.server,
                value: db.databaseUrl,
                onChanged: (value) =>
                    _updateDb(context, db.copyWith(databaseUrl: value)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _smallField(
                      context,
                      label: 'Database',
                      icon: LucideIcons.database,
                      value: db.database,
                      onChanged: (value) =>
                          _updateDb(context, db.copyWith(database: value)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _smallField(
                      context,
                      label: 'Schema',
                      value: db.schemaName,
                      onChanged: (value) => _updateDb(
                        context,
                        db.copyWith(
                          schemaName: value.isEmpty ? 'adoetzgpt' : value,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _smallField(
                      context,
                      label: 'DB User',
                      value: db.user,
                      onChanged: (value) =>
                          _updateDb(context, db.copyWith(user: value)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _smallField(
                      context,
                      label: 'DB Password',
                      icon: LucideIcons.keyRound,
                      value: db.password,
                      obscure: true,
                      onChanged: (value) =>
                          _updateDb(context, db.copyWith(password: value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _smallField(
                context,
                label: 'Custom Port',
                value: db.port,
                onChanged: (value) =>
                    _updateDb(context, db.copyWith(port: value)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _smallField(
    BuildContext context, {
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    IconData? icon,
    bool obscure = false,
  }) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            color: p.onSurfaceVariant,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            prefixIcon: icon == null ? null : Icon(icon, size: 14),
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _updateDb(BuildContext context, DatabaseSettings next) {
    final app = context.read<AdoetzAppState>();
    app.updateSyncSettings(app.syncSettings.copyWith(database: next));
  }
}
