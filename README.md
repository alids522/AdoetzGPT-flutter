# AdoetzGPT Flutter

This is a Flutter rebuild of the existing React AdoetzGPT app. The original React project is left untouched; all Flutter code and copied assets live in this `flutter_project` directory.

## What Was Rebuilt

- Authentication screen with login, signup, guest mode, and advanced PostgreSQL settings.
- Main chat shell with responsive drawer, recents, pinned chats, memory list, profile menu, theme toggle, and model selector.
- Chat composer with attachments, camera/file picking, web-search toggle, voice overlay controls, message editing, regeneration, copy/share/delete, and Markdown rendering.
- Settings sections for profile/language, PostgreSQL sync, Gemini API key, OpenAI-compatible endpoints, voice/text personality, web search, and media model options.
- Token usage dashboard with filters, summary cards, charts, custom counters, and reset actions.
- Local persistence using SharedPreferences with the same app-state concepts as the React app.
- Optional server API sync plus direct PostgreSQL auth/state sync.
- Gemini REST and OpenAI-compatible chat/model calls, including streaming response handling.
- Original logo asset copied to `assets/app_logo.png`.

## Bug Fixes In The Flutter Version

- Editing a message now regenerates from the edited user message without appending a duplicate user message.
- Long saved chat state is compacted before persistence so local storage is less likely to fail on large histories.
- Remote sync strips local-only auth tokens and database passwords before pushing app state.

## Requirements

- Flutter SDK: `C:\Users\abdur\flutter`
- Google Chrome for web testing
- Android SDK with a valid installed NDK for APK/device builds
- An Android emulator or connected Android device for Android testing

## Setup

From this directory:

```powershell
cd "D:\Ai Project\1.4 flutter target\flutter_project"
C:\Users\abdur\flutter\bin\flutter.bat pub get
```

Run for reliable Chrome testing:

```powershell
.\scripts\run_web.ps1
```

Then open `http://127.0.0.1:5100` in Chrome. This uses Flutter's `web-server` device and avoids Chrome's DWDS debug socket. If `flutter run -d chrome` fails with a localhost websocket/firewall error, this is the preferred web workflow.

If port `5100` is already in use, the script automatically chooses the next free port and prints the URL.

Optional Chrome debug mode:

```powershell
.\scripts\run_chrome_debug.ps1
```

Use this only when Chrome debug attach works on the machine.

For login/signup in Chrome, also run the original React/Node API server from the parent project:

```powershell
cd "D:\Ai Project\1.4 flutter target"
npm run dev
```

The Flutter web app uses `http://127.0.0.1:3000` as the default Sync API URL. Browsers cannot connect directly to PostgreSQL sockets, so Chrome auth and endpoint proxy fallback must go through that HTTP API.

Run on Android:

```powershell
.\scripts\run_android.ps1
```

For direct PostgreSQL on Android, leave Sync API URL blank and fill the database host, database, user, password, schema, and port fields. If you intentionally want Android to use the HTTP sync/proxy server instead, set the Sync API URL to `http://10.0.2.2:3000` on an emulator or the computer's LAN IP address on a physical device, for example `http://192.168.1.20:3000`.

Build a debug APK:

```powershell
C:\Users\abdur\flutter\bin\flutter.bat build apk --debug
```

## Verification

The following checks were run successfully:

```powershell
C:\Users\abdur\flutter\bin\dart.bat format lib test
C:\Users\abdur\flutter\bin\flutter.bat analyze
C:\Users\abdur\flutter\bin\flutter.bat test
```

APK packaging is not required for Chrome testing. If Android packaging asks for NDK `28.2.13676358`, let Android Studio SDK Manager or Gradle reinstall that NDK version, then rerun:

```powershell
C:\Users\abdur\flutter\bin\flutter.bat build apk --debug
```

## Notes

- No React source files were modified.
- No existing user state or secrets from the React data files were copied into this project.
- iOS project files are generated for later support, but Android was prioritized.
