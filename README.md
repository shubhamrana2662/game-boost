# Game Boost

A **game booster app for Android**, written in Dart/Flutter.

It scans the apps running on your phone, detects your games, lets you build a
tailor-made profile for each one (POWER 1-5, auto-boost, pause background
apps, memory clean, extra processes to kill) and - while a game is running -
applies maximum processing to it, then releases everything automatically when
the game is closed.

This repository is the source code. Building it produces one installable file:
**`game_boost.apk`** - that is the file you put on your Android phone.

---

## What it does

| Feature | Details |
| --- | --- |
| Scan games | Reads `/proc` and lists every running app with its RAM use. |
| Detect & add | One tap turns any detected app into a boosted game profile. |
| Built-in library | ~45 popular mobile games with their process-name patterns. |
| Per-game profiles | Auto-boost on/off, POWER 1-5, pause background apps, memory clean, extra kill list. |
| Auto-boost watcher | While a game profile is active and its process is alive, the app re-applies the boost and shows the game as **BOOSTING**. |
| Auto-release | The moment the game process exits, paused background apps are resumed and the system is released. |
| Memory dashboard | Live RAM totals plus a text bar, refreshed on every scan. |
| Fully customizable | Master switch, scan interval (2-15 s), pause list, whitelist, reset - all persisted on-device. |

## How the boost works

For each BOOST action the app runs a small system command
(`flutter:services process_start`):

1. `renice -n <nice> -p <game pid>` - raises the game's CPU scheduling
   priority (POWER 5 = `-20`, POWER 1 = `0`).
2. `kill -STOP <pid>` - pauses the background apps you selected in Settings
   (they are resumed with `kill -CONT` when boosting ends).
3. `kill -9 <pid>` - force-stops processes you explicitly added to the kill
   list.
4. `sync` - flushes disk writes (the classic "memory clean").

## Permissions - please read

Android sandboxes every app. Some actions are only allowed when the OS grants
them, which depends on the device and Android version:

- **Always works**: scanning `/proc`, reading memory, saving profiles,
  watching games.
- **Works on most devices**: pausing/killing only affects processes the OS
  lets the app touch.
- **Works on older/rooted/all-open Android, or when sideloaded with
  diagnostic powers**: changing another app's priority and signalling its
  processes.

The app is honest: every blocked action is counted and shown in the status
line ("N action(s) blocked by the OS"). Nothing is silent or fake. On
locked-down phones you get a great game tracker + memory cleaner + launcher;
on more open devices you get the full booster.

## Build the APK

You need the Dart-based Flutter SDK (>= 3.3):

```console
$ flutter pub get
$ flutter test          # runs the unit tests
$ flutter build apk --release
```

The `.apk` lands under `build/android/`. Install it on the phone by enabling
**Developer options**, then use `flutter run` (phone plugged in via USB),
`flutter install --device <device>`, or copy the `.apk` to the phone and open
it (confirm the "install from unknown sources" prompt).

### No local SDK? Use GitHub Actions

Push this folder to any GitHub repository and the included workflow
`.github/workflows/build-apk.yml` builds the APK for you. Download it from the
workflow run's **Artifacts** section.

> The workflow uses `flutter-actions/setup-flutter@v3` to install the SDK. If
> that action ever changes, swap it for any maintained Flutter setup action
> (for example `subosito/flutter-actions/setup-flutter@v2`).

## Customize it

- **Add a game**: SCAN NOW, then tap the `+` next to any detected app, or add
  one from the library.
- **Tune a game**: EDIT any card - set POWER, toggle AUTO-BOOST / PAUSE /
  CLEAN, tick the process names that should match the game, and choose extra
  kill targets.
- **Data file**: everything is stored in `game_boost_data.json` in the app
  data directory - back it up or edit patterns manually.

## Project layout

```
lib/main.dart                  entry point (runApp)
lib/src/game_boost.dart        app root + auto-boost watch loop
lib/src/controller.dart        controller interface used by the views
lib/src/models.dart            GameProfile, Settings, AppState
lib/src/proc.dart              /proc scanner + pattern matching + priority map
lib/src/boost.dart             shell actions (renice/kill/sync) + reports
lib/src/store.dart             tiny JSON encoder/decoder + persistence
lib/src/game_library.dart      built-in game name/pattern library
lib/src/ui/*                   home / editor / settings screens + widgets

test/game_boost_test.dart      unit tests (pure Dart, no /proc, no services)
```

## Notes for developers

- Zero third-party packages - only the Flutter SDK (`flutter/widgets.dart`,
  `flutter/services.dart`, `flutter/material.dart`, `dart:async`, `dart:io`,
  `dart:convert`, `dart:core`).
- The widget API targets current Dart-based Flutter (3.4x / 3.47). Material
  widgets come from the SDK; if a future release moves them to an opt-in
  package, add that package to `pubspec.yaml` and update the
  `package:flutter/material.dart` imports.
- `flutter analyze` may warn about process handles that are not disposed
  before the process exits - intentional, the handles are short lived.

Enjoy boosting. Game on!