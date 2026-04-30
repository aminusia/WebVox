# WebReader

**Reader Mode + Text-to-Speech app for Android.**

WebReader strips the clutter from any web article and reads it aloud with word-by-word highlighting. Paste a URL or share one directly from your browser — WebReader handles the rest.

---

## Features

- **Reader mode** — strips ads, navigation, and sidebars; extracts title, author, and article text
- **Text-to-Speech** — uses Android's system TTS engine with word highlighting during playback
- **Lock-screen / notification controls** — media session with rewind/forward (±10 s) via headset buttons or notification
- **Background article caching** — pre-fetches upcoming articles so the next one is ready before you finish the current one
- **Bookmarks & reading history** — save articles and resume reading from where you left off
- **Prev/Next navigation** — auto-detects article series links; optional auto-advance with a countdown timer
- **Share integration** — share any URL from your browser directly into WebReader
- **Settings** — font size, TTS speed/pitch/voice/language, auto-play, auto-next, light/dark/system theme

---

## Requirements

- **Android** — the only supported platform
- **Flutter SDK** `>=3.7.0`
- An Android TTS engine installed on the device (Google TTS or similar)

---

## Setup

1. **Clone the repository**

   ```bash
   git clone <repo-url>
   cd WebReader
   ```

2. **Install dependencies**

   ```bash
   flutter pub get
   ```

3. **Run on a connected Android device or emulator**

   ```bash
   flutter run
   ```

4. **Build a release APK**

   ```bash
   flutter build apk --release
   ```

   The signed APK will be output to `build/app/outputs/flutter-apk/`.

5. **Build a release APK and prepare a GitHub release package**

   ```bash
   ./scripts/build-release.sh
   ```

   This bumps the build number in `pubspec.yaml`, builds the APK, and copies it to `dist/` as a versioned artifact plus `web_reader-latest.apk`.

> **App icon** — the launcher icon is generated from `assets/appicon.png` via `flutter_launcher_icons`. Run `dart run flutter_launcher_icons` to regenerate it after changing the source image.

---

## Architecture

| Layer | Location | Responsibility |
|---|---|---|
| Domain | `lib/domain/` | Entities and repository interfaces |
| Data | `lib/data/` | SQLite (sqflite), HTTP fetching, HTML parsing |
| Presentation | `lib/presentation/` | Screens, widgets, Riverpod notifiers |

State management is handled by **Riverpod** (`flutter_riverpod`). Background media playback and lock-screen controls use **audio_service**.

Key dependencies:

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `flutter_tts` | Android system TTS |
| `audio_service` | Lock-screen media session |
| `sqflite` | Local SQLite database |
| `http` | Article fetching |
| `html` | HTML parsing |
| `receive_sharing_intent` | Accept shared URLs from other apps |
| `share_plus` | Share article URLs out |

---

## Reporting Issues

When filing a bug report, please include:

- Android version and device model
- App version (visible in Settings)
- Steps to reproduce the issue
- The URL of the article that triggered the problem (if applicable)
- Any relevant logcat output

---

## Contributing

Contributions are welcome. Please:

1. Fork the repository and create a feature branch from `main`
2. Follow the existing code style (enforced by `flutter_lints`)
3. Keep changes focused — one feature or fix per pull request
4. Run `flutter analyze` and `flutter test` before submitting
5. Describe the motivation and approach clearly in the PR description

For significant changes, open an issue first to discuss the proposal before investing time in an implementation.

---

## License
This project is licensed under the MIT License.

---

## Trademark Notice
The name "WebReader" and the WebReader logo are trademarks of the author.
You may not use the name or branding for your own distributions without permission.

You are free to fork and modify the code, but must rename your version.