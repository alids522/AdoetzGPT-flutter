# Project Audit Report

**Project:** AdoetzGPT Flutter App
**Branch:** 1.3
**Date:** 2026-06-15
**SDK:** Dart ^3.12.1 / Flutter
**Lines of Code Analyzed:** ~12,000+ across 33 Dart files

---

## 1. Executive Summary

### Overall Project Health: **MODERATE — Functional but needs attention**

AdoetzGPT is an ambitious, feature-rich AI chat application rebuilt from a React codebase into Flutter. It supports regular chat with streaming responses, Gemini Live voice chat, video chat, multiple AI model providers, agent servers (OpenClaw, Hermes, OpenAI-compatible), Supabase and PostgreSQL sync with real-time subscriptions, backup databases, web search, artifact/preview mode, memory injection, token usage analytics, custom counters, six visual themes, and bilingual UI (English/Indonesian).

**What works:** The core chat flow with streaming responses, model switching, endpoint configuration, and the multi-theme UI are well-implemented. The app successfully handles sending messages, receiving streamed responses, and rendering markdown. The state management with Provider is reasonably organized.

**Main Risks:**
1. **Sync can silently lose data** — the merge strategy is timestamp-based with no conflict-resolution UI, and the "newer wins" approach can discard local changes if clocks drift.
3. **Several features are UI-connected but incomplete** — video model selection, captions button, and the "monitor up" button in voice overlay are dead controls.


## 2. What Looks Good

### Strong Architecture Choices
- **Clean model layer:** `models.dart` has well-structured immutable data classes with `copyWith`, `fromJson`, `toJson` — consistent serialization throughout.
- **Platform-adaptive design:** Good use of conditional exports (`live_socket.dart`, `live_camera_feed.dart`, `download_helper.dart`, `live_audio_player.dart`) for web vs. native separation.
- **Streaming text renderer:** `StreamingTextRenderer` (`lib/widgets/streaming_text_renderer.dart`) is sophisticated — it paces visual text reveal independently of network chunks, preventing UI jank on long responses. The adaptive word-per-tick and long-text truncation strategy is well thought out.
- **Visual theme system:** Six distinct themes (Classic, Liquid Glass, Aurora Neon, Modern Minimal, iOS 26 Vision, Midnight Bloom) implemented cleanly through `AppPalette` with glass morphism, backdrop blur, and animated gradients — this is polished.
- **Context window tracking:** The token count progress bar and context window editor (with custom overrides, verified API values, and estimated fallbacks) in `_InputPod` is a good UX touch.
- **Voice auto-save:** The 10-second periodic persist during live sessions (`_startLiveAutoSave`) protects against data loss from crashes.
- **Sync merge logic:** The session-level merge in `_mergeSession` and `_mergeSessionMessages` handles ID-based deduplication, text-length preferring, and divergent message handling — sophisticated for a client-side app.

### Good UI/UX Choices
- **Animated message bubbles:** User messages animate in with `easeOutBack` spring curves.
- **Scroll-to-bottom FAB:** Appears when scrolled up, with a generating indicator dot.
- **Thought block:** Collapsible thinking/reasoning display with auto-scroll during active streaming.
- **Search status pill:** Animated pulsing indicator during web search.
- **Code blocks:** macOS-style window chrome (traffic light dots), syntax highlighting, horizontal scroll, and copy button.
- **Attachment tray:** Horizontal scrolling image/file previews with remove buttons.
- **Voice overlay:** Beautiful animated capsule with audio level visualization, blue glow, and connection states.
- **BackdropFilter/glass morphism:** Consistent across all non-classic themes for depth.
- **Bilingual support:** English and Indonesian translations via `UiCopy` and `_translations` map.

### Working Flows
- Regular chat with Gemini and OpenAI-compatible endpoints
- Streaming response display
- Thinking mode (DeepSeek `<think>` tag support)
- Web search (Gemini Grounding, DuckDuckGo, Google Custom Search, Tavily, endpoint-based)
- File attachments (images, PDFs with text extraction, text files)
- Session management (create, rename, pin, delete, clear all, search)
- Model switching within session with handoff summaries
- Agent server configuration and testing
- Token usage analytics with charts (bar, line, pie)
- Multi-theme visual system
- Memory injection into chat context

---

## 3. Critical Issues

### 3.1 Sync Can Silently Discard Local Data

**File:** `lib/state/app_state.dart` — `_mergeRemote()` (lines 353-475), `_scheduleRemoteSync()` (lines 3170-3246)

**What is wrong:** The merge strategy uses `remote.savedAt >= local.savedAt` to decide which side "wins" for settings. If two devices are actively used and clock drift exists between them, the older-device's changes are silently discarded with no user notification. The merge uses "newer wins" for sessions too (`remote.updatedAt >= local.updatedAt` in `_mergeSession`, line 518), which can drop message edits made on the older device.

**Why it matters:** Users could lose settings changes, session edits, or newly created sessions without any indication. There is no conflict-resolution UI — the user never knows data was lost.

**How to verify:** Make changes on two devices simultaneously, trigger sync on both. The device with the slightly older clock will have its changes overwritten.

**Recommended fix:** Implement a last-writer-wins registry with conflict detection. When a conflict is detected (both sides modified the same session since last sync), surface a notification and keep both versions with a diff view. At minimum, log conflicts so users can manually recover.


### 3.3 `signOut()` Resets All Local Data Irreversibly

**File:** `lib/state/app_state.dart` — `signOut()` (lines 901-934)

**What is wrong:** Signing out destroys all local state:
```dart
sessions = [session];
currentSessionId = session.id;
memories = const [];
geminiApiKey = '';
endpoints = const [EndpointConfig(id: '1', ...)];
tokenUsageData = const [];
customCounters = const [];
agentConnectors = const [];
modelContextOverrides = const {};
```

**Why it matters:** If a user accidentally signs out, they lose ALL chat history, memories, token analytics, custom counters, endpoints, and agent connectors. There is no undo. For guest users especially, this is catastrophic since there is no cloud backup.

**How to verify:** Log in, create sessions with messages, sign out. All data is gone.

**Recommended fix:** Before clearing data on sign-out, persist a local backup (e.g., save to a different SharedPreferences key or export to a file). Show a confirmation dialog that explicitly warns "This will delete all local chat data." Offer a "keep local data" option for users who want to sign out but preserve their data.

### 3.5 Duplicate `_remoteSyncTimer?.cancel()` in `syncNow()`

**File:** `lib/state/app_state.dart` — `syncNow()` (lines 2423-2424)

**What is wrong:** The same timer is cancelled twice:
```dart
_remoteSyncTimer?.cancel();
_remoteSyncTimer?.cancel();
```
This is a copy-paste bug — the second line was likely intended to cancel `_remotePullTimer`.

**Why it matters:** The remote pull fallback timer is not properly cancelled during manual sync, meaning it can fire mid-sync and cause a race condition where two sync operations overlap — potentially corrupting the merged state.

**How to verify:** Trigger `syncNow()` while the 5-second pull timer is active. Two concurrent pull/push cycles may run.

**Recommended fix:** Change the second line to `_remotePullTimer?.cancel();`

### 3.6 Video Model Selector is a Dead Disabled Button

**File:** `lib/screens/settings_screen.dart` — `_MediaSection.build()` (lines 2282-2288)

**What is wrong:** The video model selector is rendered as a permanently disabled `OutlinedButton`:
```dart
OutlinedButton(
  onPressed: null,
  child: const Align(
    alignment: Alignment.centerLeft,
    child: Text('Google Veo (Latest)    Active'),
  ),
),
```

**Why it matters:** Users see a "video model" setting that appears functional but cannot be changed. This is confusing and appears broken. The `videoModel` field exists in `GenerationSettings` but is never actually used in chat requests — it's dead configuration.

**How to verify:** Navigate to Settings → Voice & Live → Media Generation. The video model button is permanently disabled.

**Recommended fix:** Either implement video generation support or remove/hide the video model UI until it is implemented.

### 3.7 Dead Buttons in Voice Overlay During Live Sessions

**File:** `lib/screens/chat_screen.dart` — `_VoiceOverlay.build()` (lines 2542-2549) and `_LiveVideoTopControls.build()` (lines 2727-2740)

**What is wrong:** Two buttons in the live voice/video overlay have empty `onPressed` handlers:
1. The "monitor up" button (`LucideIcons.monitorUp`) — `onPressed: () {}`
2. The "captions" button (`LucideIcons.captions`) — `onPressed: () {}`
3. The "more" button (`LucideIcons.moreHorizontal`) — `onPressed: () {}`

**Why it matters:** Users see UI controls that look interactive but do nothing when tapped. This is confusing and degrades trust in the application.

**How to verify:** Start a live voice session on a wide screen, tap the monitor-up, captions, or more buttons.

**Recommended fix:** Either implement the features or remove the buttons. If implementation is planned, show a "Coming soon" tooltip or snackbar.

---

## 4. Major Issues

### 4.1 `app_state.dart` is Monolithic (3,284 lines)

**File:** `lib/state/app_state.dart`

**Problem:** The file contains: state fields, initialization, authentication, session management, message sending, live voice/video control, streaming pipeline, sync orchestration, merge logic, model fetching, context window management, memory agent integration, persistence, and disposal — all in one class.

**Impact:** The file is extremely difficult to maintain, test, or extend. Any change risks unintended side effects. No unit testing is feasible for a 3,000+ line class.

**Recommended fix:** Split into focused classes:
- `ChatController` — message sending, streaming, stop/cancel
- `LiveSessionController` — voice/video lifecycle
- `SyncController` — remote state push/pull/merge
- `SessionManager` — CRUD operations on sessions
- `SettingsManager` — endpoints, connectors, generation settings
Keep `AdoetzAppState` as a thin coordinator delegating to these controllers.

### 4.2 No Test Coverage

**File:** `test/widget_test.dart`

**Problem:** The only test is the default Flutter `widget_test.dart` placeholder (taps the counter button, which doesn't exist in this app). There are zero unit tests, zero widget tests, and zero integration tests.

**Impact:** Refactoring is dangerous. Any change could break chat, sync, or voice functionality without detection. The app cannot be confidently shipped.

**Recommended fix:** Add at minimum:
- Unit tests for `models.dart` (JSON serialization round-trips, `copyWith`, edge cases)
- Unit tests for `AiService` token counting, model resolution, history construction
- Unit tests for merge logic (`_mergeSession`, `_mergeRemote`)
- Widget tests for `ChatScreen` message sending, streaming display
- Integration tests for the auth → chat → sync flow

### 4.3 Token Estimation is Crude

**File:** `lib/services/ai_service.dart` — `countTokens()` (line 1865)

**Problem:** Token counting uses `text.length / 4` which is a very rough heuristic:
```dart
int countTokens(String text) => max(1, (text.length / 4).ceil());
```
This does not account for different tokenizers (GPT vs Gemini vs Claude have different tokenization). The `tiktoken` package is listed in `pubspec.yaml` as a dependency but is never imported or used.

**Impact:** Context window tracking is inaccurate, especially for non-English text (e.g., Indonesian) where characters-to-tokens ratio differs significantly. Cost estimates in the token usage screen are wrong. Users may unknowingly exceed context limits.

**Recommended fix:** Use the `tiktoken` package (already a dependency) for OpenAI-compatible models. For Gemini, use the Gemini-specific token count API. Fall back to the character heuristic only when the proper tokenizer is unavailable.


### 4.5 No Permission Denial Recovery Flow

**File:** `lib/state/app_state.dart` — `startLiveConversation()` (lines 1870-1877)

**Problem:** When microphone permission is denied, the app shows a status message but offers no way to retry or navigate to settings:
```dart
if (micStatus != PermissionStatus.granted) {
  syncStatus = 'Microphone permission is required for Live Mode.';
  notifyListeners();
  return;
}
```
The user must manually go to system settings to grant permission, but the app gives no guidance.

**Impact:** Non-technical users will be stuck. On iOS, once a permission is denied, the system dialog never appears again — the user must go to Settings app, but the app doesn't tell them this.

**Recommended fix:** Use `openAppSettings()` from `permission_handler` to guide the user to system settings. Show a dialog explaining the steps.

### 4.6 `clearAllSessions()` Can Crash on Direct Index Access

**File:** `lib/state/app_state.dart` — `clearAllSessions()` (line 1585)

**Problem:** Uses `sessions.firstWhere(...)` without `orElse`, which throws `StateError` if no matching session exists:
```dart
} else if (sessions.firstWhere((s) => s.id == currentSessionId).deleted) {
```
If `currentSessionId` doesn't match any session (possible after remote sync manipulation), this crashes.

**Impact:** App crash when clearing all sessions after certain sync states.

**Recommended fix:** Use `.firstOrNull` pattern:
```dart
final current = sessions.where((s) => s.id == currentSessionId).firstOrNull;
if (current != null && current.deleted) { ... }
```

### 4.7 Missing `context.mounted` Check After Async Gap in `_ChatTargetDropdownState._selectTarget()`

**File:** `lib/screens/app_shell.dart` — `_selectTarget()` (lines 657-673)

**Problem:** After `await Future<void>.delayed(Duration.zero)` and before checking `rootContext.mounted`, the widget may have been disposed:
```dart
widget.onClose(); // modifies Overlay state
if (!app.requiresTargetSwitchConfirmation(target)) {
  app.applyChatTarget(target, insertDivider: false);
  return;
}
await Future<void>.delayed(Duration.zero);
if (!rootContext.mounted) return; // `this` context not checked
```
The `setState` could fire after `widget.onClose()` has removed the overlay, but the widget is still in the tree — `this.mounted` is not checked before the delayed gap.

**Impact:** Potential exception if the overlay is dismissed during the async gap.

**Recommended fix:** Check `mounted` (the State's mounted) before and after the await gap.

### 4.8 Memory Agent Runs Synchronously on UI Thread

**File:** `lib/state/app_state.dart` — `_maybeSaveUserMemory()` (lines 2864-2871)

**Problem:** The `MemoryAgent().analyze()` call is synchronous and runs on the UI isolate:
```dart
final actions = const MemoryAgent().analyze(
  message: text,
  existingMemories: memories,
);
```
The MemoryAgent uses regex matching across arrays of memories. While currently not computationally heavy, it blocks the UI thread during message sending.

**Impact:** Minor UI jank during message sending, especially as memory count grows. Not critical now but will degrade with scale.

**Recommended fix:** Run memory analysis in an isolate using `compute()` or `Isolate.run()`.

### 4.9 WebSocket Cleanup Race in `GeminiLiveService.dispose()`

**File:** `lib/services/gemini_live_service.dart` — `dispose()` (lines 195-198)

**Problem:** `dispose()` calls `stop()` which is async but the result is not awaited:
```dart
Future<void> dispose() async {
  await stop();
  await _recorder.dispose();
}
```
However, in `AdoetzAppState.dispose()`, the live service is disposed with `unawaited(live.dispose())`:
```dart
final live = _liveService;
if (live != null) unawaited(live.dispose());
```
This means the recorder and WebSocket may not be fully cleaned up before the app exits.

**Impact:** Potential resource leaks on app shutdown. The AudioRecorder may hold the microphone. On web, dangling WebSocket connections.

**Recommended fix:** In `AdoetzAppState.dispose()`, await the live service disposal:
```dart
if (live != null) await live.dispose();
```
Since `dispose()` cannot be async, use `WidgetsBinding.instance.addPostFrameCallback` or ensure cleanup happens in `stopLiveConversation()` before dispose.

---

## 5. Minor Issues

### 5.1 Inconsistent Extension Duplication

**Files:** Multiple files define identical `_FirstOrNull<T>` extensions:
- `lib/state/app_state.dart` (line 3265)
- `lib/services/ai_service.dart` (line 1923)
- `lib/services/gemini_live_service.dart` (line 528)
- `lib/services/memory_agent.dart` (line 631)
- `lib/screens/settings_screen.dart` (line 2488)

This extension is defined 5+ times across the codebase. It should be extracted to `models.dart` or a shared utility file.

### 5.2 `_ListFallback.ifEmpty()` Extension Never Used

**File:** `lib/models.dart` (line 1869)

The `_ListFallback<T>` extension and its `ifEmpty()` method are only used once (in `PersistedAppState.fromJson()` for `endpoints`). The extension is defined for general use but only serves one purpose. If it stays, move it out of the private scope and into a shared location.

### 5.3 Unused Import: `dart:convert` in `auth_screen.dart`

**File:** `lib/screens/auth_screen.dart`

`dart:convert` is imported but never used directly in this file (it's used indirectly through the state methods). The import should be removed.

### 5.4 Unused Import: `package:flutter/foundation.dart` in `settings_screen.dart`

**File:** `lib/screens/settings_screen.dart` (line 2)

`foundation.dart` is imported but only `kIsWeb` is used (which comes from `foundation.dart` so technically it IS used, but only for `kIsWeb` — the full import is heavier than needed).

### 5.5 `_ThemeRuntime` Static Mutable State is Risky

**File:** `lib/ui/app_theme.dart` (lines 92-94)

```dart
class _ThemeRuntime {
  static AppVisualTheme visualTheme = AppVisualTheme.classic;
}
```
This static mutable field is set in `buildTheme()` and read in `AppPalette.fromBrightness()`. If multiple widget trees exist (unlikely in this app but possible with nested `MaterialApp`), this could cause inconsistent theme state.

**Impact:** Low risk for current architecture. Could cause issues in tests or if the app ever uses multiple navigators.

### 5.6 `const lucidePlus` is Unused

**File:** `lib/ui/app_theme.dart` (line 966)

```dart
const lucidePlus = LucideIcons.plus;
```
This constant is never used anywhere in the codebase.

### 5.7 `LiveAudioPlayer` on Native is Stub Only

**File:** `lib/services/live_audio_player_mobile.dart`

The mobile implementation uses a `MethodChannel('adoetzgpt/live_audio')` but there is no corresponding native Android/iOS implementation visible in the codebase (the channel would need Kotlin/Java and Swift/ObjC code). The `MissingPluginException` is silently caught. This means **voice chat audio output does not work on mobile** — users get transcripts but no audio.

**Impact:** The primary feature of voice chat (hearing the AI speak) is broken on mobile. Only web has a working implementation via Web Audio API.

### 5.8 Duplicate `ConnectorStatusDot` Widgets

**File:** `lib/screens/app_shell.dart` — `_ConnectorDot` (lines 818-846)
**File:** `lib/screens/settings_screen.dart` — `_ConnectorStatusDot` (lines 1967-1995)

These two widgets implement identical logic with slightly different sizes (9px vs 11px). They should be a single shared widget.

### 5.10 Unused `dart:io` Import in `ai_service.dart`

**File:** `lib/services/ai_service.dart`

`dart:io` is not imported, but Platform checks exist in other files. This is not an issue in `ai_service.dart` specifically, but `Platform` is used in `app_state.dart` for Windows sound check — verify it's conditionally available for web compilation.

---

## 6. Unused Code and Dead Code

### 6.1 Definitely Unused

| Item | File | Notes |
|------|------|-------|
| `const lucidePlus` | `lib/ui/app_theme.dart:966` | Declared but never referenced |
| `_ListFallback<T>` extension (beyond single use) | `lib/models.dart:1869` | Only used once for endpoints fallback |
| `sendLiveVideoFrame()` in `GeminiLiveService` | `lib/services/gemini_live_service.dart:348` | Actually used by camera feeds, but the frame rate throttle (1 FPS) makes it nearly useless as "video" |
| "Captions" button | `lib/screens/chat_screen.dart:2728` | `onPressed: () {}` — dead |
| "Monitor up" button | `lib/screens/chat_screen.dart:2543-2548` | `onPressed: () {}` — dead |
| "More" button in video top controls | `lib/screens/chat_screen.dart:2734-2739` | `onPressed: () {}` — dead |

### 6.2 Suspected Unused

| Item | File | Notes |
|------|------|-------|
| `videoModel` field in `GenerationSettings` | `lib/models.dart:1013` | Defined, persisted, configurable in UI (dead button), never sent to API |
| `imageModel` field in `GenerationSettings` | `lib/models.dart:1012` | Settable via UI but never referenced in `AiService._sendGemini()` or `_sendEndpoint()` — image generation is not implemented |
| `toolEventIds` on `Message` | `lib/models.dart:224` | Persisted but never populated by tool-calling logic — tools support is declared in capabilities but not implemented in the chat flow |
| `_connectorAccordionTile` widget | `lib/screens/app_shell.dart:1723` | Fully implemented but the "View Logs" menu item duplicates the `_showConnectorLogs` dialog that also exists in settings |
| `LiveForegroundService` | `lib/services/live_foreground_service.dart` | Only functional on Android with native code — no Android native implementation is visible in the repo |

### 6.3 Old/Experimental Code Remnants

| Item | File | Notes |
|------|------|-------|
| `adoetz_backup_20260615_114947.dump` | Root directory | A 2.2 MB database dump file committed to the repo — should be in `.gitignore` |
| `diff.txt` | Root directory | 68KB diff file committed to repo |
| `flutter_web_server_*.log` | Root directory | Server logs committed to repo |
| `flutter_web_*.log` | Root directory | Web build logs committed to repo |
| `migrate.ts` | Root directory | TypeScript migration script — unrelated to Flutter project |

### 6.4 Duplicate Logic

| Item | Locations | Notes |
|------|-----------|-------|
| `_FirstOrNull<T>` extension | 5 files | Should be in `models.dart` or a `utils/extensions.dart` |
| `ConnectorStatusDot` / `_ConnectorDot` | `app_shell.dart` and `settings_screen.dart` | Identical purpose, different widget names |
| Visual theme normalization switch | `app_state.dart:958-968` and `models.dart:1856-1866` | Same logic in two places |
| `_showConnectorLogs` / `_showLogs` | `app_shell.dart:1792` and `settings_screen.dart:1944` | Same dialog, slightly different width |

---

## 7. Potential Bugs by Feature Area

### 7.1 Regular Chat

1. **Empty prompt with attachments:** `sendMessage()` checks `prompt.trim().isEmpty && attachments.isEmpty` before returning. But if only attachments are sent (no text), the `prompt` passed to Gemini is empty, which may cause API errors.

2. **Concurrent sends:** While `isSessionGenerating()` guards against double-send, there's no lock — if the UI rebuilds and the guard state is stale, two messages could be sent. The `generatingSessionIds` set is the correct guard, but it's cleared in the `finally` block — if the finally block throws, the session stays locked.

3. **Message deletion index calculation:** `deleteMessage()` at line 2061 assumes the message after a user message is always a bot message. If a system message (like a target switch divider) is between them, the wrong messages are deleted.

### 7.2 Streaming Response

1. **Stream flush race condition:** `_queueStreamText()` creates a Timer that fires after 80-160ms. If `stopGeneration()` is called during this window, the timer callback may still fire and update the bot message after stop. The `_sessionGenerationIds` and `_stopRequestedGenerations` checks in `_queueStreamText` and `_flushStreamText` mitigate this but don't prevent the Timer creation itself.

2. **`_pendingStreamTexts` memory leak:** If a generation is cancelled and `_cancelStreamFlush` is called with `resetText: true`, the pending text is removed. But if `resetText` is false (or not called), the map entries persist until overwritten by a new generation ID — minor leak.

3. **Long streaming text truncation:** `StreamingTextRenderer._displayText()` truncates text over 10,000 characters to head+tail with "..." in the middle. Users reading very long responses will see truncated content with no indication of how much was cut.

### 7.3 Model Switching

1. **Agent-to-agent switch with no current messages:** If the current session is empty and the user switches from one agent to another, `applyChatTarget()` at line 1033 skips the divider insertion. But the `startedWithTargetId` and `currentTargetId` are updated anyway — the session now "started" on the new target without any indication of the switch.

2. **Fork loses target switch events:** When forking (line 1047-1068), the forked session inherits messages but gets fresh `targetHistory` and empty `targetSwitchEvents`. The fork context says "Branch" but carries no record of which target it branched from.

### 7.4 Voice Chat

1. **Session displacement during live call:** If another device pushes a remote session change while live call is active, `_pullRemoteStateInForeground()` skips pulls during live (line 3019), but `_scheduleRemoteSync` does NOT check `isLiveActive`. A remote sync push could fire during a live call, modifying the session that voice transcripts are being appended to.

2. **Microphone not released on error:** If `_stopRecorder()` throws (line 329-331), the mic stream may continue. The error is caught but the recorder state may be inconsistent.

3. **Audio player start/stop during interrupt:** When interrupted (line 264-270), the player is stopped and immediately restarted. If `start()` takes time (Web Audio context creation), the next audio chunk may try to play before the player is ready — causing a gap in audio.

4. **Live session ID captured at start, not updated:** `_liveSessionId` is set once in `startLiveConversation()` (line 1882) and never changes. If the user switches to a different session during an active live call, transcripts continue writing to the OLD session. This is actually intentional based on the code comments, but there's no UI indication that transcripts are going to a different session.

### 7.5 Video Chat

1. **Camera not released when live call ends via external action:** The `LiveForegroundService.onAction = (action) { if (action == 'end_live') { stopLiveConversation(); } }` stops the live service but the camera feed widget (`LiveCameraFeed`) is dismantled via widget tree rebuild — if the rebuild doesn't happen synchronously, the camera may continue capturing.

2. **Web camera stream not stopped on page hide:** When the browser tab is hidden, the web camera stream is NOT paused. `_captureFrame()` still fires but `context.read<AdoetzAppState>()` may fail if the widget is not in the tree.

3. **Camera resolution preset is always `high`:** On native, `ResolutionPreset.high` is hardcoded (line 60 in `live_camera_feed_native.dart`). This may cause performance issues on low-end devices and uses more bandwidth for frame capture than necessary (frames are JPEG compressed anyway).

### 7.6 Database Sync

1. **Token-based session isolation is fragile:** The `direct:` token prefix scheme for distinguishing Postgres vs Supabase sessions is a convention, not enforced by cryptography. A malformed token could be interpreted incorrectly.

2. **Backup database errors halt primary sync:** In `pushRemoteState()` (lines 388-439), if backup database sync fails with an exception, it throws and the entire sync is marked as failed — even though the primary database was successfully synced. The success status is overwritten by the backup error.

3. **Supabase realtime subscription may miss events:** The channel subscribes to `PostgresChangeEvent.all` but only attaches callbacks after `channel.subscribe()`. Events between subscription and callback attachment could be missed.

4. **Schema creation is not transactional:** `_ensurePostgres()` creates tables with `IF NOT EXISTS` in separate statements. If only some tables are created before a crash, the schema is in an inconsistent state. This recovers on next attempt, but the app doesn't validate schema completeness.

### 7.7 Session and Title Generation

1. **Title generation uses wrong model after model switch:** `_generateSessionTitle()` at line 2768 uses `genSettings.titleModel` if enabled, otherwise the `model` parameter. The `model` parameter is passed from `sendMessage()` at line 1821 as `modelForRequest`, which is the target's model AT SEND TIME. If the user switches models after sending, the title uses the old model name.

2. **Title generation silently fails:** If `_generateSessionTitle()` throws, the catch block at line 2801 is empty — no fallback title, no logging:
```dart
} catch (_) {}
```

3. **Fallback title from first 4 words may be nonsense:** When `genSettings.titleModelEnabled` is false or title generation fails, the fallback is the first 4 words of the user's message. For messages like "Can you please help me with..." the title becomes "Can you please help" — not useful.

---

## 8. UI/UX Audit

### 8.1 UI Problems

1. **Settings screen is very long:** The scrollable list with 5 categories and inline editing makes navigation tedious. A user looking for "Web Search" settings has to scroll through General, AI & Generation, Voice & Live, then find Integrations. There's no quick-jump or sticky category header.

2. **No visual distinction for disabled endpoint:** In `_EndpointSection`, a disabled endpoint still shows all its fields — only a small Switch indicates it's off. Users may edit fields of a disabled endpoint thinking they're active.

3. **Attachment tray horizontal scroll has no scroll indicator:** The `_AttachmentTray` uses a horizontal `ListView` with no scrollbar. Users with many attachments won't know they can scroll.

4. **Token context bar is very small:** The context window progress bar in the input pod is ~70px wide with tiny 9px font. On mobile, it's 50px. The information is dense but the touch target is small.

5. **Empty state doesn't show model info:** The `_EmptyState` widget shows a greeting but doesn't tell the user which model is active or how to start. New users may not understand they can type or use voice.

### 8.2 UX Problems

1. **No undo for message deletion:** Deleting a message is immediate and irreversible. There's no "Undo" snackbar.

2. **No confirmation for clearing all sessions:** `_confirmClear()` in the drawer shows an AlertDialog titled "Delete all data?" but the confirmation button says "Yes, Clear Everything" — inconsistent terminology.

3. **Model picker doesn't show which model is currently active when opened:** The dropdown lists models and agent servers, but the user has to scroll to find the checked one. In a long list, this is frustrating.

4. **Voice chat activation is confusing:** The send button transforms to a mic icon when the text field is empty. Tapping it starts voice chat. This dual-purpose button (send vs. voice) is not obvious — users may accidentally start voice chat when they meant to send an empty message (which would be ignored anyway), or tap send expecting voice when they have text typed.

5. **Sign out deletes everything without clear warning:** The sign-out button shows "Are you sure you want to sign out?" but doesn't mention data loss.


### 8.3 Missing States

1. **No loading state for session history:** When switching to a session with many messages, the `ListView.builder` renders immediately. With hundreds of messages, this could cause a frame drop — there's no progressive loading or virtualization beyond what `ListView.builder` provides.

2. **No "no internet" state in chat:** If the network is unavailable, the send button still appears active. The error only appears after the API call fails.

3. **No "API key invalid" state differentiation:** When the Gemini API key is invalid, the error message is generic ("Gemini request failed"). The user doesn't know if it's a key issue, a network issue, or a model issue.

4. **No empty state for agent servers in sidebar:** When agent servers are collapsed, there's no indication of how many are configured. The user must expand the section to see.

### 8.4 Layout Risks



### 8.5 Responsiveness Issues


---

### 9.3 Async Performance

1. **`fetchModels()` fetches all endpoints sequentially:** In `AiService.fetchModels()`, endpoints are fetched in a `for` loop with `await` — no concurrency. With 5 endpoints each taking 12 seconds to timeout, this can take up to 60 seconds on failure.

2. **`_pullRemoteStateAfterStartup()` runs on the main isolate:** The initial remote state pull during `initialize()` is unawaited but runs on the main isolate, potentially blocking UI during the 8-second timeout.

### 9.6 Database Performance

1. **`_compactForStorage()` creates full copies:** In `StorageService`, the entire state is copied with message text truncated to 12,000 chars and attachments over 500KB cleared. This deep copy with string manipulation runs synchronously on `save()`.


## 10. Database and Sync Audit

### 10.1 Current Sync Flow

The sync system supports three modes:
1. **Supabase** (via `supabase_flutter` SDK) — direct PostgreSQL access with realtime subscriptions
2. **Direct PostgreSQL** (via `postgres` package) — native sockets, Android/desktop only
3. **HTTP Sync API** (via custom Node.js backend at `apiBaseUrl`) — web-compatible, proxy-based

**Push flow:** Changes are debounced (2-second timer), dirty session IDs and settings flag are tracked, then pushed via the active mode. Before pushing, the app pulls remote state to check for conflicts and merges if remote is newer.

**Pull flow:**
- Initial pull at startup (8-second timeout)
- Realtime subscription via Supabase channels (`user_settings` and `chat_sessions` tables)
- Polling fallback every 5 seconds if realtime fails

### 10.2 What is Complete

- Three sync modes with clean separation in `SyncService`
- Session delta tracking (only pushes changed sessions)
- Realtime subscription with Supabase PostgresChanges
- Backup database mirroring during push
- Schema auto-creation (`_ensurePostgres()`)
- Password hashing with bcrypt (12 rounds for signup)
- Token-based authentication (`direct:` prefix for Postgres, JWT for Supabase)

### 10.3 What is Incomplete

- **No offline queue:** If sync fails, dirty session IDs are re-added to the set and retried on the next schedule. But if the app is closed before retry, those changes are lost from the sync queue (they remain in local storage but won't be pushed on next launch unless the session `updatedAt` is newer than `lastSyncAt`).
- **No conflict resolution UI:** As noted in Critical Issues.
- **No backup restore UI:** The backup database configuration exists in settings, but there's no "Restore from Backup" button. Backups are push-only — data can be mirrored to backup databases but cannot be restored to the primary from within the app.
- **No migration validation:** `migrateToSupabase()` pushes local state to Supabase but doesn't verify the migration succeeded — no diff check after push.

### 10.4 Duplicate/Lost Data Risks

- **High risk of message duplication:** The merge logic in `_mergeSessionMessages` uses ID-based deduplication. If two devices generate messages with the same ID (possible with the UUID v4 generator, though extremely unlikely), or if a message ID collision occurs across different sessions, data could be merged incorrectly.
- **Medium risk of session duplication:** If two devices create sessions offline and sync later, both sessions are preserved (correct). But if they edit the same session offline, the newer timestamp wins and the older edits are lost (incorrect — should merge).
- **Low risk of memory duplication:** Memory merge uses ID-based dedup, but memory IDs are timestamp-based (`'$now-${next.length}'`). If two devices save a memory at the same millisecond, they get different IDs and the same memory is stored twice.

### 10.5 Migration and Backup/Restore Readiness

- **Backup push works** — data is mirrored to configured backup databases on sync
- **Restore is NOT implemented** — no UI or logic to pull from a backup database into the primary
- **Migration between Postgres and Supabase is partially supported** via `migrateToSupabase()` but:
  - Only one-way (Postgres → Supabase)
  - No Supabase → Postgres migration
  - Requires the user to enter Supabase credentials while logged into Postgres

---

## 11. Feature Completeness Matrix

| Feature | Status | Evidence | Risk | Recommendation |
|---------|--------|----------|------|----------------|
| Regular Chat | **Complete** | Full send/receive/display flow works | Low | Add undo delete, improve error differentiation |
| Streaming | **Complete** | SSE streaming with Gemini + OpenAI endpoints | Low | Optimize markdown re-render during streaming |
| Thinking Mode | **Complete** | `<think>` tag parsing, collapsible UI | Low | Add visual indication when thinking is active in header |
| Memory | **Complete** | Heuristic-based memory agent, manual CRUD, injection | Low | Move to isolate, add memory search |
| Web Search | **Complete** | 5 engines: Gemini, DuckDuckGo, Google CSE, Tavily, Endpoint | Low | Show search results to user before AI response |
| Attachments | **Mostly Complete** | Images, PDFs, text files, camera capture | Low | Video attachments not processed (base64 only) |
| Session Title Gen | **Complete** | AI-generated + fallback heuristics | Low | Fallback titles are weak |
| Model Switching | **Complete** | With confirmation, fork, handoff summaries | Low | Model picker UX could be improved |
| Voice Chat | **Partially Complete** | Gemini Live via WebSocket works on web; audio output broken on mobile | **High** | Implement native audio playback; add permission recovery |
| Video Chat | **Partially Complete** | Camera feed works; only sends 1 FPS still frames; dead buttons | **High** | Implement real video or rename to "Camera"; fix dead buttons |
| Supabase Sync | **Complete** | Auth, push, pull, realtime subscriptions | Medium | Remove hardcoded credentials |
| PostgreSQL Sync | **Complete** | Direct socket connection with schema migration | Medium | Add connection pooling for multiple rapid operations |
| HTTP API Sync | **Complete** | Proxy-based for web compatibility | Medium | Document the API server setup |
| Backup Databases | **Partially Complete** | Push to backup works; restore not implemented | **High** | Implement restore functionality |
| Settings | **Complete** | All settings persisted and applied | Low | Long scroll — add quick-nav or search |
| Token Usage | **Complete** | Charts, filters, custom counters, cost estimates | Medium | Use proper tokenizer instead of chars/4 heuristic |
| Visual Themes | **Complete** | 6 themes with distinct palettes | Low | Reduce continuous animation overhead |
| Agent Connectors | **Complete** | OpenClaw, Hermes, OpenAI-compatible | Low | Add connector health dashboard |
| Artifact Mode | **Partially Complete** | Parses file headers, previews HTML in WebView | Medium | Only HTML preview works; other file types show code only |
| Guest Mode | **Complete** | Local-only sessions with save-to-account option | Low | Add clear data-loss warning on sign-out |
| Dictation (STT) | **Complete** | Speech-to-text with hold-to-talk and continuous modes | Low | Restart recovery could cause audio gaps |
| Custom Counters | **Complete** | Create, rename, reset, delete with per-model breakdown | Low | Counter reset doesn't confirm with user |

---

## 12. Deep Analysis: Database & Sync — Message Disappearance Risks

This section traces every code path that could cause user messages or AI responses to vanish — either visibly from the UI or permanently from storage.

### 12.1 Scenario A: App Killed Mid-Generation (User Message Lost)

**Files:** `lib/state/app_state.dart` — `sendMessage()` lines 1674-1846
**Severity:** HIGH — guaranteed data loss on crash during generation

**Step-by-step trace:**

1. User taps send. `sendMessage()` begins.
2. Lines 1709-1728: `userMessage` and `botMessage` (empty placeholder) constructed in memory.
3. Lines 1733-1745: `nextSession` built with `[...session.messages, userMessage, botMessage]`.
4. Line 1746: `_replaceSession()` updates `sessions` **in RAM only**. No disk write.
5. Line 1752: `notifyListeners()` — UI shows user message + loading state.
6. Line 1758: `await _ai.sendMessage(...)` — the function **yields** to the event loop here.
7. If the app is killed during step 6 (swiped away, OS kill, battery, crash):
   - The user message lives **only in RAM**.
   - The last disk persist was some earlier action.
   - On restart, `StorageService.load()` reads state without the user message.
   - **Result: User message permanently lost.**

8. Even if streaming begins, `_updateBotMessage()` (line 2536) only modifies RAM. `_persistAndScheduleRemote()` runs exclusively in the `finally` block at line 1843 — **after** the full response. A crash mid-stream loses both the user message AND all partial AI output.

**How to verify:** Send a message, immediately force-kill the app. Reopen. The message is gone.

**Recommended fix:** Persist synchronously at line 1746 (right after `_replaceSession`, before the `await`). Add periodic streaming checkpoints (every ~5s, like `_startLiveAutoSave`).

---

### 12.2 Scenario B: Storage Compaction Permanently Truncates Message Text

**Files:** `lib/services/storage_service.dart` — `_compactForStorage()` lines 34-86, `_compactText()` lines 88-93
**Severity:** MEDIUM — progressive, irreversible data degradation

**Step-by-step:**

Every `save()` call runs `_compactForStorage()`:

```dart
final compactText = _compactText(message.text, 12000);
```

`_compactText()`:
```dart
String _compactText(String text, int limit) {
  if (text.length <= limit) return text;
  final head = (limit * 0.65).floor();  // 7,800 chars
  final tail = (limit * 0.35).floor();  // 4,200 chars
  return '${text.substring(0, head)}\n\n[Earlier saved content compacted]\n\n${text.substring(text.length - tail)}';
}
```

For messages over 12,000 characters (code generation, long explanations, artifact outputs):
- The middle portion is **irreversibly discarded**.
- Only the first ~7,800 and last ~4,200 characters survive.
- The marker `[Earlier saved content compacted]` is inserted — original text is gone forever.
- If sync hasn't happened yet, this **truncated version** is what gets pushed to the server.

Attachment data over 500KB is silently wiped:
```dart
data: attachment.data.length <= 500000 ? attachment.data : '',
```

**How to verify:** Generate a 15,000+ character response. Save settings. Reload. Message shows truncation marker.

**Recommended fix:** Store large message text in files (via `path_provider`), not `SharedPreferences`. Keep only metadata in SharedPreferences; full text in local SQLite or flat files.

---

### 12.3 Scenario C: `selectSession()` With Invalid ID — Silent Fallback to Wrong Session

**Files:** `lib/state/app_state.dart` — `selectSession()` lines 1488-1503, `currentSession` getter lines 133-140
**Severity:** MEDIUM — causes wrong session to display; user confused about which session is active

**Step-by-step:**

1. `selectSession(id)` at line 1489: `currentSessionId = id` — **set unconditionally**, even if `id` doesn't match any session.
2. `notifyListeners()` triggers UI rebuild.
3. `currentSession` getter (lines 133-140):
   ```dart
   Session get currentSession {
     return activeSessions
             .where((session) => session.id == currentSessionId)
             .firstOrNull ??         // ← null (no match)
         (activeSessions.isNotEmpty
             ? activeSessions.first  // ← falls back silently!
             : Session.empty(...));
   }
   ```
4. **UI shows a different session than what the user tapped.**
5. Line 1502: `_persist(touchSavedAt: false)` saves the invalid `currentSessionId`.

This triggers when:
- A remote sync deletes the session between sidebar rendering and user tap.
- `currentSessionId` is corrupted in storage.
- A soft-deleted session's ID was stored.

**How to verify:** Corrupt `currentSessionId` in SharedPreferences, restart app. Sidebar highlights one session, chat shows another.

**Recommended fix:** Guard `selectSession()`:
```dart
if (!activeSessions.any((s) => s.id == id)) return;
currentSessionId = id;
```

---

### 12.4 Scenario D: `currentSession` Getter Creates Ghost Sessions

**Files:** `lib/state/app_state.dart` — `currentSession` getter lines 133-140
**Severity:** LOW-MEDIUM — messages written to sessions that vanish on restart

When `activeSessions` is empty AND `currentSessionId` matches nothing, the getter creates a **transient** `Session.empty()`:

```dart
Session.empty(null, selectedTargetId)  // ← NOT added to sessions list
```

This object is returned for one frame. `sendMessage()` captures it at line 1678. `_replaceSession()` at line 1746 tries to find its ID in the real `sessions` list — fails silently (no match in `.map()`). `_updateBotMessage()` at line 2545 also fails to find it. **Messages are written to a ghost session that is never persisted.**

**How to verify:** Delete all sessions, set `currentSessionId` to a random value, send a message. It appears in UI but vanishes on restart.

**Recommended fix:** Never create transient sessions. If zero active sessions, create one AND add it to the sessions list before returning.

---

### 12.5 Scenario E: `deleteMessage()` Removes Wrong Pair With System Dividers Present

**Files:** `lib/state/app_state.dart` — `deleteMessage()` lines 2054-2077, `applyChatTarget()` lines 1079-1094
**Severity:** LOW — edge case but destructive

`deleteMessage()` assumes the message after a user message is always a bot:
```dart
if (messages[index].isUser &&
    index + 1 < messages.length &&
    !messages[index + 1].isUser) {
  messages.removeRange(index, index + 2); // removes user + assumed-bot
}
```

But `applyChatTarget()` inserts **system divider messages** between user and bot:
```
[user msg] → [system: "Switched from X to Y"] → [bot response]
```

Deleting the user message deletes user + system divider — but **leaves the bot response orphaned** without its prompt context.

**How to verify:** Send a message, switch models (inserts divider), delete the user message. Bot response remains.

**Recommended fix:** Walk forward from the deleted user message, removing all subsequent non-user messages until the next user message or end of list.

---

### 12.6 Scenario F: Remote Session Delete Propagates via Realtime — Active Session Vanishes

**Files:** `lib/state/app_state.dart` — `_applyRemoteSessionChange()` lines 3072-3119
**Severity:** MEDIUM — active session disappears while user is viewing it

**Step-by-step:**

1. User views Session X on Device A.
2. Session X deleted on Device B → pushed to server.
3. Supabase realtime fires `onSession` on Device A with `remoteSession.deleted = true`.
4. `_applyRemoteSessionChange()` at line 3092 merges remote (deleted) with local.
5. `_mergeSession()` line 518: remote has higher `updatedAt` → remote is primary. `primary.copyWith(...)` propagates `deleted = true` to merged result.
6. Line 3106-3111: since user is viewing the deleted session, app auto-switches to `activeSessions.first`.
7. **User sees their session suddenly disappear and switch to a different one with no warning.**

**How to verify:** Two devices, same account. Delete session on one device while other is viewing it.

**Recommended fix:** Show a snackbar before auto-switching: "Session 'X' was deleted on another device."

---

### 12.7 Scenario G: Token/Database Mode Mismatch — Local Changes Never Synced

**Files:** `lib/services/sync_service.dart` — `pushRemoteState()` lines 314-316, 347-349
**Severity:** MEDIUM — local data never reaches server; lost on device wipe

The `direct:` token prefix distinguishes Postgres from Supabase sessions. If a user logs in via Supabase, then toggles to direct Postgres in settings, the existing token is rejected:

```dart
if (token.startsWith('direct:')) {
  throw Exception('Your current session is from Postgres...');
}
```

Every push fails. The 10-second retry loop at line 3241-3243 keeps retrying — but **always fails** because the token type doesn't match. Dirty sessions are never synced. If the device is wiped, all unsent messages are permanently gone.

**How to verify:** Log in via Supabase. Toggle "Use Supabase" OFF in settings. Try to sync. It fails silently-retrying forever.

**Recommended fix:** Detect mismatch and show a clear warning. Offer migration or re-authentication. Don't silent-retry forever.

---

### 12.8 Scenario H: Backup Database Error Blocks Primary Sync Success

**Files:** `lib/services/sync_service.dart` — `pushRemoteState()` lines 388-439
**Severity:** MEDIUM — one bad backup DB config halts all sync

If backup database sync fails, the exception propagates and the entire sync is marked failed — even though the primary database sync already succeeded. The success status is replaced by the backup error.

```dart
if (pushSuccess && settings.autoSyncBackups) {
  for (final db in settings.backupDatabases) {
    ...
    } catch (e) {
      throw Exception('Backup Database Error (${db.databaseUrl}): $e');
    }
  }
}
```

**Recommended fix:** Wrap each backup push in try/catch. Log failures but don't let them fail the primary sync.

---

## 13. Deep Analysis: Session Switching — "Half New Half Previous" UI Bugs

### 13.1 Most Likely Cause: `selectSession()` + Invalid ID + Silent Fallback

This is the primary suspect for the "half new half previous" experience.

1. User taps "Session A" in sidebar.
2. `selectSession('session-a-id')` at line 1489 sets `currentSessionId = 'session-a-id'` unconditionally.
3. But Session A was soft-deleted by a remote sync between sidebar render and tap.
4. `currentSession` getter: session-a-id has `deleted = true` → filtered out by `activeSessions`. Fallback returns `activeSessions.first` (Session B).
5. **Sidebar highlights Session A (based on `currentSessionId`), chat area shows Session B (resolved by `currentSession` getter).**

The user sees two different sessions across the UI simultaneously — exactly what you described.

---

### 13.2 Secondary Cause: `_applyRemoteSyncState()` Replaces Sessions List Mid-Frame

**Files:** `lib/state/app_state.dart` — `_applyRemoteSyncState()` lines 3121-3143
**Severity:** LOW-MEDIUM — frame-level flicker

1. ChatScreen is rebuilding `_MessageList` with Session X's messages (10 items).
2. 5-second poll fires. `_pullRemoteStateInForeground()` runs.
3. At line 3016: `generatingSessionIds.isNotEmpty` — false (not generating). Pull proceeds.
4. `_applyRemoteSyncState()` at line 3128: `_applyState(state)` **replaces** `sessions` with merged state.
5. Line 3138: `notifyListeners()` — ChatScreen rebuilds again.
6. Session objects are **new instances** from the merge. Message list may have different item count or reordered messages.
7. `ListView.builder` gets new `itemCount` mid-render → visual flicker.

---

### 13.3 Tertiary Cause: `createSession()` Reuses Empty Sessions

**Files:** `lib/state/app_state.dart` — `createSession()` lines 1447-1468

When `currentSession.messages.isEmpty`, no new session is created — the current one is repurposed with a new `currentTargetId`. The `currentSessionId` stays the same. If the user expected a fresh session, they see the old session title/target appear to "stick" — it looks like the new session wasn't fully created.

---

### 13.4 Sorting Changes After Merge Displace Sidebar Items

**Files:** `lib/state/app_state.dart` — `_mergeRemote()` line 366

```dart
final mergedSessions = sessionMap.values.toList()
  ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
```

After every merge, sessions re-sort by `updatedAt`. A remote session modification bumps its `updatedAt`, moving it to the top of the sidebar. If the user was mid-tap, they hit the wrong session.

---

## 14. Deep Analysis: Two Devices, Same Account, Same Session — Concurrent Chat

### 14.1 The App Has Zero Multi-Device Concurrency Guards

Sync is designed for **sequential** multi-device usage: chat on phone, put it down, pick up laptop, sync pulls latest, continue. Simultaneous chat in the same session was never designed for. There are no locks, no optimistic concurrency, and no "another device is active" detection.

### 14.2 Full Trace: Two Devices Send Messages Concurrently

**T0:** Both Device A and Device B logged into same account. Both viewing Session X (same `session.id`, 10 existing messages).

**T1:** Device A sends "What is Flutter?"
- `sendMessage()` creates `userMessage` ID `msg-aaa`, empty `botMessage` ID `msg-bbb`.
- `messages: [...10 existing, msg-aaa, msg-bbb]` — 12 messages locally.
- `updatedAt = 1000`. `_replaceSession()` updates RAM. `notifyListeners()`.
- `await _ai.sendMessage(...)` begins — yields to event loop.

**T2 (1 second later):** Device B sends "What is Dart?"
- Same flow. `userMessage` ID `msg-ccc`, `botMessage` ID `msg-ddd`.
- `updatedAt = 1001`.
- API call begins on B.

**T3:** Device A's API returns Flutter explanation.
- `_updateBotMessage()` fills `msg-bbb` with Flutter response.
- `updatedAt` bumped to `2000`.
- `finally` block: `_persistAndScheduleRemote()` pushes to server.
- Server now has Version A: [1..10, msg-aaa, msg-bbb], updatedAt=2000.

**T4:** Device B's API returns Dart explanation.
- `_updateBotMessage()` fills `msg-ddd` with Dart response.
- `updatedAt` bumped to `2001`.
- Push to server. **Server overwritten with Version B**: [1..10, msg-ccc, msg-ddd], updatedAt=2001.
- **Version A (Flutter Q&A) is gone from the server** until A pushes again.

**T5 — Device A pulls:**
- Pulls Version B from server.
- `_mergeSession()`: `remote.updatedAt (2001) >= local.updatedAt (2000)` → **remote wins**, remote is primary.
- `_mergeSessionMessages(primary=B, secondary=A)`:
  - Primary (B) messages: [1..10, msg-ccc, msg-ddd] — added first.
  - Secondary (A) messages: [1..10, msg-aaa, msg-bbb] — 1..10 already exist (skipped). `msg-aaa`, `msg-bbb` are new IDs → **appended to end**.
- **Result on Device A:** [1..10, msg-ccc (Dart-Q), msg-ddd (Dart-A), msg-aaa (Flutter-Q), msg-bbb (Flutter-A)]

**T6:** Device A pushes merged version (all 14 messages). Server now has full set but misordered.

**T7:** Device B pulls. Similar merge in reverse. Final state on both: all 14 messages exist, but **conversation is semantically broken** — the Flutter answer appears after the Dart answer with no prompt in between.

### 14.3 Secondary Damage: AI Context Was Incomplete

At T3, Device A's AI responded using `_historyForRequest()` — only Device A's local history (no knowledge of B's Dart question). At T4, same on B (no knowledge of A's Flutter question). **Both AI responses were generated from degraded, incomplete context.**

### 14.4 Target Switch Leaks Between Devices

If Device A switches models mid-conversation, `applyChatTarget()` inserts a system divider "Switched from Gemini to GPT-4o" into Session X. This pushes to the server. Device B pulls and now has a system divider for a switch **it never made**. The `handoffSummary` also propagates to B and gets injected into B's prompts via `_promptWithTargetContext()` — **Device B's AI receives irrelevant handoff context from Device A's actions.**

### 14.5 Generation Guard Works (Partially)

The guard at `_pullRemoteStateInForeground()` line 3016 (`generatingSessionIds.isNotEmpty`) and `_applyRemoteSessionChange()` line 3076 both correctly block remote updates during active generation. So **streaming is protected** from mid-stream corruption. The guard only covers the pull side though — it doesn't prevent both devices from generating simultaneously, it just prevents each from pulling the other's changes while generating.

### 14.6 Summary: Two Devices, Same Session

| Aspect | Behavior | Severity |
|--------|----------|----------|
| Both send messages | All messages survive merge but become **misordered** — conversation garbled | **HIGH** |
| Both generate AI responses | Each AI sees only local history — incomplete context, degraded responses | **HIGH** |
| One switches model | Other device gets false system divider + wrong handoff context injected | **HIGH** |
| One stops generation | Stop is local only; other device continues | MEDIUM |
| Streaming collision | Generation guard protects in-progress streaming ✓ | SAFE |
| Data loss | No messages permanently lost — merge preserves all unique IDs | SAFE |
| Message duplication | Unlikely (UUID v4 per message) | SAFE |
| Both generate titles | One title silently discarded; wasted API call | LOW |

### 14.7 Verdict

**Yes, significant problems exist.** The app silently allows simultaneous multi-device chat but produces corrupted results — no error, just a conversation that becomes unreadable as messages from both devices interleave. The app was designed for single-device-at-a-time usage with sync to transfer state between sessions.

**Recommended fix (if concurrent chat is desired):**
- Add a `generationLock` field to the session, synced to server — check before sending.
- Use server timestamps for message ordering, not client-side `updatedAt`.
- Broadcast presence via Supabase realtime channel.
- Block sending if another device is detected as active in the same session.

**Simpler fix (recommended):** Prevent the scenario. When Device B opens a session active on Device A, show a banner: "This session is active on another device. Changes may conflict." Or auto-fork to a new session on the second device.

---

## 15. Consolidated Fix Priority for Database & Sync

### P0 — Must Fix

| # | Fix | File | Line |
|---|-----|------|------|
| 1 | Persist user message to disk BEFORE `await _ai.sendMessage()` | `app_state.dart` | After line 1752 |
| 2 | Add periodic streaming checkpoints (every ~5s) | `app_state.dart` | New method |
| 3 | Guard `selectSession()` against invalid/deleted IDs | `app_state.dart` | Line 1489 |
| 4 | Fix `currentSession` getter — never create ghost sessions | `app_state.dart` | Lines 133-140 |
| 5 | Fix duplicate timer cancel in `syncNow()` — cancel `_remotePullTimer` | `app_state.dart` | Line 2424 |

### P1 — Should Fix Soon

| # | Fix | File | Line |
|---|-----|------|------|
| 6 | Store large message text in files, not SharedPreferences | `storage_service.dart` | Full rewrite |
| 7 | Add generation-in-progress guard to `_applyRemoteSyncState` | `app_state.dart` | Line 3121 |
| 8 | Show snackbar when remote sync deletes currently-viewed session | `app_state.dart` | Line 3106 |
| 9 | Detect token/database mode mismatch — warn, don't silent-retry | `sync_service.dart` | Lines 314-316, 347-349 |
| 10 | Don't let backup DB errors fail primary sync | `sync_service.dart` | Lines 435-438 |
| 11 | Add multi-device detection — warn or auto-fork for concurrent same-session access | `app_state.dart` | `sendMessage()` |
