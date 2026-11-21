# GEMINI.md - Project Specification: N_ap

## 1. Project Overview
- **App Display Name:** `N_ap` (Novel Audio Player)
- **Flutter Package / Project Name:** `n_ap`
- **Android Application ID:** `com.vyxion.n_ap`
- **Target Platform:** Android (Release APK build, optimized for Samsung Galaxy Z Fold series & standard Android phones)
- **Core Purpose:** A lightweight, zero-cache personal audiobook player designed for a novelist to listen to their own manuscripts directly from Google Drive while working, without interruption from screen lock or other media apps.

---

## 2. Non-Negotiable Core Constraints (OS & Audio Engine)
The agent MUST strictly adhere to these architectural rules. Do NOT substitute them with standard browser/system TTS wrappers that yield audio focus.

### 2.1. Absolute Audio Focus Bypass (Simultaneous Playback)
- The app MUST NOT pause, duck, or stop playback when other apps (YouTube, games, ads, internet broadcasts like SOOP, or system notifications) play audio.
- **Implementation Requirement:** Use `just_audio` for playback and explicitly disable audio focus and interruption handling upon initialization:

```dart
final AudioPlayer player = AudioPlayer(
  handleAudioFocus: false,
  handleInterruptions: false,
  androidApplyAudioAttributes: false,
);
```

### 2.2. Lock Screen & Background Persistence
- Playback MUST continue indefinitely when the screen is turned off or the device is locked.
- **Implementation Requirement:**
  - Wrap playback logic inside an `audio_service` (`BaseAudioHandler`) Foreground Service.
  - Configure `AndroidManifest.xml` with:
    - `android.permission.INTERNET`
    - `android.permission.WAKE_LOCK`
    - `android.permission.FOREGROUND_SERVICE`
    - `android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK`
  - Expose lock-screen media controls (Play/Pause, Previous Sentence, Next Sentence / Bookmark).

### 2.3. Zero-Cache In-Memory Streaming (No Disk Bloat)
- **NEVER save synthesized audio files (.mp3/.wav) to permanent device storage.** Long-form novels (500+ chapters) must not consume gigabytes of storage.
- **RAM Sliding Buffer:**
  - Parse the loaded episode into an ordered list of sentence chunks.
  - Maintain an in-memory buffer of the **current sentence + next 3 sentences** (`pre-fetch window = 3`).
  - Feed audio bytes directly to `just_audio` via a custom `StreamAudioSource` (in-memory `Uint8List`).
  - Discard audio bytes from RAM immediately after a sentence finishes playing.

---

## 3. TTS Engine & Novel Text Parsing

### 3.1. Primary Voice Engine: Edge Neural TTS
- Use Microsoft Edge Neural TTS WebSocket/HTTP streaming protocol (free, no API key required, high naturalness).
- Default Korean voices: `ko-KR-InJoonNeural` (Male, calm narration) and `ko-KR-SunHiNeural` (Female). Allow user selection of voice, playback speed (`0.8x` – `2.0x`), and base pitch.
- **Network Resilience:** Implement exponential backoff retry for temporary network drops. Optionally support `flutter_tts` only as a last-resort offline fallback toggle.

### 3.2. Single-Voice Nuance via Regex + SSML
Without using LLM APIs or multi-speaker casting, apply lightweight regex parsing to distinguish narrative styles using SSML prosody tags:
- **Narration (Default text):** Standard pitch (`+0Hz`), standard rate.
- **Dialogue (Wrapped in double quotes `"..."`):** Subtle pitch lift (`+2Hz`), slight pre/post pause (`150ms`) for clarity.
- **Inner Monologue (Wrapped in parentheses `(...)`):** Subtle pitch drop (`-3Hz`), slightly slower rate (`-5%`) for introspective tone.
- Strip Markdown formatting symbols (`#`, `*`, `---`, etc.) before sending text to TTS so symbols are never read aloud.

---

## 4. Google Drive Integration & Auto-Play

### 4.1. Authentication & Scopes
- Use `google_sign_in` + `googleapis` (`drive/v3.dart`).
- Required OAuth scopes:
  - `[https://www.googleapis.com/auth/drive.readonly](https://www.googleapis.com/auth/drive.readonly)` (for reading folders & manuscripts)
  - `[https://www.googleapis.com/auth/drive.file](https://www.googleapis.com/auth/drive.file)` (optional/preferred: for creating/appending revision bookmark memos in the user's folder).

### 4.2. Folder Registration & File Extraction
- Users can browse and register multiple Google Drive folders (e.g., per novel project).
- Supported file types inside registered folders:
  - Plain text (`.txt`) & Markdown (`.md`) → fetch via `files.get(downloadOptions: DownloadOptions.fullMedia)`.
  - Google Docs (`application/vnd.google-apps.document`) → extract plain text via `files.export(fileId, 'text/plain')`.
- **Natural Sorting:** Sort files within a folder using a Natural Sort comparator so numerical titles order properly (`1화`, `2화`, ..., `10화`, NOT `1화`, `10화`, `2화`).

### 4.3. Continuous Auto-Advance & Resume State
- **Seamless Next-Episode Transition:** When the final sentence of an episode plays, pre-fetch the text and first 3 sentences of the next episode in the folder. Pause `2 seconds`, announce the next episode title, and continue playback automatically—even while the screen is locked.
- **Lightweight State Persistence:** Store only lightweight JSON metadata via `shared_preferences` or `hive`:
  - List of registered Drive folder IDs & names
  - Per-folder playback progress (`lastFileId`, `lastFileName`, `sentenceIndex`)
  - User TTS preferences (voice, speed)

---

## 5. Writer Utility: One-Touch Revision Bookmark (퇴고 북마크)
- While listening during work, the user can tap a large dedicated **Bookmark** button (or trigger via lock-screen notification action) to flag awkward phrasing without reading the screen.
- **Action:** Captures `[Timestamp] | [Episode Title] | [Line #] | [Current Sentence Text]`.
- **Storage:** Appends the entry to a local log and (if `drive.file` permission is enabled) syncs/appends to `N_ap_퇴고메모.md` inside the corresponding Google Drive folder.

---

## 6. UI/UX Design Guidelines (Dark Luminous)
- **Visual Theme:** **Dark Luminous** aesthetic.
  - Deep matte charcoal/obsidian background (`#0E1014`, `#161920`).
  - Restrained luminous accents scaled by functional hierarchy (e.g., crisp cyan/amber glow exclusively for active playback state, highlighted active sentence, and primary CTA).
  - Hardware-inspired tactile keycap controls (subtle 1px top highlight border, depressed press state) for Play/Pause, Skip, Speed, and Revision Bookmark.
- **Adaptive Layout (Foldable & Standard Support):**
  - **Compact / Cover Screen (`width < 600dp`):** One-handed focused player with active sentence card, minimal progress bar, and oversized bottom keycap controls (`Play/Pause`, `Bookmark`, `Speed`).
  - **Expanded / Unfolded Screen (`width >= 600dp`):** 2-pane split layout — Left pane: Folder & episode playlist + Revision Log; Right pane: Auto-scrolling manuscript reader with live sentence highlighting + tactile media console.

---

## 7. Recommended Directory Structure

```text
lib/
├── main.dart
├── core/
│   ├── theme/dark_luminous_theme.dart
│   └── utils/
│       ├── natural_sort.dart
│       └── ssml_parser.dart
├── data/
│   ├── models/ (novel_folder.dart, episode_item.dart, revision_bookmark.dart)
│   └── services/
│       ├── drive_service.dart
│       ├── edge_tts_service.dart
│       └── storage_service.dart
├── audio/
│   ├── memory_audio_source.dart      # Custom StreamAudioSource for RAM bytes
│   ├── sliding_buffer_manager.dart   # Pre-fetch queue (current + next 3)
│   └── novel_audio_handler.dart      # audio_service + just_audio (No AudioFocus)
└── presentation/
    ├── screens/ (home_folders_screen.dart, player_screen.dart, bookmarks_screen.dart)
    └── widgets/ (keycap_button.dart, manuscript_viewer.dart, speed_selector.dart)
```

---

## 8. Agent Development Workflow Rules
1. **Verify `AndroidManifest.xml` & `build.gradle` first** before writing UI code, ensuring `minSdkVersion >= 23`, `compileSdkVersion >= 34`, and foreground service declarations are valid.
2. **Test Audio Engine Isolation Early:** Build and verify the `EdgeTTS -> RAM StreamAudioSource -> just_audio (handleAudioFocus: false) -> audio_service` pipeline before adding complex UI polish.
3. **Keep Dependencies Lean:** Prefer official/well-maintained packages (`just_audio`, `audio_service`, `google_sign_in`, `googleapis`, `http`, `shared_preferences`). Avoid bloated state management libraries; simple `ChangeNotifier` / `ValueNotifier` or `Provider` is sufficient.
4. **Error Handling:** Surface clear, non-intrusive toast/snackbar messages for Drive token expiration or Edge-TTS WebSocket disconnects with automatic reconnect attempts.