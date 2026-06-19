import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/app_shell.dart';
import 'screens/auth_screen.dart';
import 'state/app_state.dart';
import 'ui/app_theme.dart';

import 'services/mcp_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => McpService()),
        ChangeNotifierProxyProvider<McpService, AdoetzAppState>(
          create: (context) => AdoetzAppState(
            mcpService: context.read<McpService>(),
          )..initialize(),
          update: (_, mcp, appState) => appState!,
        ),
      ],
      child: const AdoetzGptApp(),
    ),
  );
}

class AdoetzGptApp extends StatelessWidget {
  const AdoetzGptApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AdoetzAppState>();
    final dark = app.theme == 'dark';
    final visualTheme = appVisualThemeFromKey(app.visualTheme);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AdoetzGPT',
      theme: buildTheme(false, visualTheme: visualTheme),
      darkTheme: buildTheme(true, visualTheme: visualTheme),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: app.initialized
          ? (app.currentUser == null ? const AuthScreen() : const AppShell())
          : const _LoadingScreen(),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.fromBrightness(
      Theme.of(context).brightness == Brightness.dark,
    );
    return Scaffold(
      backgroundColor: p.background,
      body: const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
