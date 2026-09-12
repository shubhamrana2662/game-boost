# Game Boost

A **game booster app for Android**, written in Dart/Flutter.

It scans the apps running on your phone, detects your games, lets you build a
tailor-made profile for each one (POWER 1-5, auto-boost, pause background
apps, memory clean, extra processes to kill) and - while a game is running -
applies maximum processing to it, then releases everything automatically when
the game is closed.

---

## 📥 Download & Install

1. Go to the [**Releases page**](../../releases/latest)
2. Download **`game-boost.apk`**
3. Transfer it to your Android phone
4. On your phone: **Settings → Security** → enable **Install from unknown sources**
5. Open the `.apk` file → tap **Install** → **Open**

> The APK is automatically built by GitHub Actions on every push. Always grab
> the latest release for the newest features.

---

## What it does

| Feature | Details |
| --- | --- |
| Scan games | Reads `/proc` and lists every running app with its RAM use. |
| Detect & add | One tap turns any detected app into a boosted game profile. |
| Built-in library | ~50 popular mobile games with their process-name patterns. |
| Per-game profiles | Auto-boost on/off, POWER 1-5, pause background apps, memory clean, extra kill list. |
| Auto-boost watcher | While a game profile is active and its process is alive, the app re-applies the boost and shows the game as **BOOSTING**. |
| Auto-release | The moment the game process exits, paused background apps are resumed and the system is released. |
| Memory dashboard | Live RAM totals plus a text bar, refreshed on every scan. |
| Fully customizable | Master switch, scan interval (2-15 s), pause list, whitelist, reset - all persisted on-device. |

## ⚡ Maximum Performance Boost Actions

For each BOOST action, the app runs a series of system commands to squeeze
every drop of performance for your game:

| # | Action | Command | Effect |
|---|--------|---------|--------|
| 1 | **CPU Priority** | `renice -n <N> -p <pid>` | Raises the game's CPU scheduling priority (POWER 5 = `-20` = highest) |
| 2 | **I/O Priority** | `ionice -c1 -p <pid>` | Sets real-time I/O class for maximum disk throughput |
| 3 | **OOM Protection** | `echo -1000 > /proc/<pid>/oom_score_adj` | Tells kernel to never kill the game, even under memory pressure |
| 4 | **Background Lowering** | `renice -n 19 -p <bg_pid>` | De-prioritizes every non-game process (POWER 4+) |
| 5 | **Background Freeze** | `kill -STOP <pid>` | Pauses the background apps you selected (resumed on release) |
| 6 | **Force Kill** | `kill -9 <pid>` | Force-stops processes you explicitly put on the kill list |
| 7 | **Memory Flush** | `sync` | Flushes all pending disk writes |
| 8 | **Cache Drop** | `echo 3 > /proc/sys/vm/drop_caches` | Frees kernel page/dentry/inode caches (POWER 5 or aggressive clean) |
| 9 | **CPU Governor** | `echo performance > scaling_governor` | Forces all CPU cores to maximum frequency (POWER 4+) |
| 10 | **MAX-FPS unlock** | `settings put global low_power 0` + Doze whitelist + `game_mode PERFORMANCE` | Disables battery-saver throttling, keeps the game out of Doze, puts the SoC in game-performance mode (POWER 5 or MAX-FPS toggle) |
| 11 | **MAX-HZ display** | `settings put system peak_refresh_rate 90/120/144` + `min_refresh_rate 90/120` | Pins the panel to its peak Hz (auto-detected 60/90/120/144; 90 on Low-End mode) so BGMI can render 90/120fps; restored to 60Hz on release |
| 12 | **BGMI TURBO** | `am set-standby-bucket com.pubg.imobile ACTIVE` + `cmd package compile -m speed` | Gives BGMI max background processing + speed-compiled code for faster map loads and smoother frame pacing |

### 🚀 BOOST BGMI MAX button (one tap)

The big green button on the home screen calls `boostBgmiMax()`: it finds (or
creates) the BGMI profile, forces **POWER 5 + MAX-FPS + MAX-HZ + BGMI-TURBO**
on, then boosts immediately. Per-game toggles for the same three features live
in the game editor, and POWER 5 auto-enables FPS+Hz even if the toggles are
off. One tap = maximum processing for BGMI on a low-end phone.

When you stop playing, the app automatically:
- Resumes all paused apps (`kill -CONT`)
- Restores the CPU governor to balanced mode (`schedutil`)

## Permissions - please read

Android sandboxes every app. Some actions are only allowed when the OS grants
them, which depends on the device and Android version:

- **Always works**: scanning `/proc`, reading memory, saving profiles,
  watching games.
- **Works on most devices**: pausing/killing only affects processes the OS
  lets the app touch.
- **Works on older/rooted/all-open Android, or when sideloaded with
  diagnostic powers**: changing another app's priority, I/O class, OOM score,
  CPU governor, and signalling other apps' processes.

The app is honest: every blocked action is counted and shown in the status
line ("N action(s) blocked by the OS"). Nothing is silent or fake. On
locked-down phones you get a great game tracker + memory cleaner + launcher;
on more open devices you get the full booster.

## Build the APK yourself

You need the Dart-based Flutter SDK (>= 3.3):

```console
$ flutter create . --platforms=android --org com.gameboost
$ flutter pub get
$ flutter test          # runs the unit tests
$ flutter build apk --release
```

The `.apk` lands under `build/app/outputs/flutter-apk/`. Install it on the
phone by enabling **Developer options**, then use `flutter run` (phone plugged
in via USB), `flutter install --device <device>`, or copy the `.apk` to the
phone and open it (confirm the "install from unknown sources" prompt).

### No local SDK? Use GitHub Actions

Push this folder to any GitHub repository and the included workflow
`.github/workflows/build-apk.yml` builds the APK and creates a downloadable
**GitHub Release** automatically. Download it from the repo's **Releases** page.

## Customize it

- **Add a game**: SCAN NOW, then tap the `+` next to any detected app, or add
  one from the library.
- **Tune a game**: EDIT any card - set POWER, toggle AUTO-BOOST / PAUSE /
  CLEAN, tick the process names that should match the game, and choose extra
  kill targets.
- **Data file**: everything is stored in `game_boost_data.json` in the app
  data directory - back it up or edit patterns manually.

### POWER levels

| Level | Name | Nice | IO | Governor | Background | Cache |
|-------|------|------|----|----------|------------|-------|
| 1 | Gentle | 0 | — | — | — | — |
| 2 | Light | -5 | — | — | — | — |
| 3 | Sport | -10 | RT | — | — | — |
| 4 | Turbo | -15 | RT | performance | lowered | — |
| 5 | MAX | -20 | RT | performance | lowered | dropped |

## Project layout

```
lib/main.dart                  entry point (runApp)
lib/src/game_boost.dart        app root + auto-boost watch loop
lib/src/controller.dart        controller interface used by the views
lib/src/models.dart            GameProfile, Settings, AppState
lib/src/proc.dart              /proc scanner + pattern matching + priority map
lib/src/boost.dart             boost engine (renice/ionice/oom/kill/governor)
lib/src/store.dart             tiny JSON encoder/decoder + persistence
lib/src/game_library.dart      built-in game name/pattern library
lib/src/ui/*                   home / editor / settings screens + widgets

test/game_boost_test.dart      unit tests (pure Dart, no /proc, no services)
```

## Notes for developers

- Zero third-party packages - only the Flutter SDK (`flutter/widgets.dart`,
  `flutter/material.dart`, `dart:async`, `dart:io`, `dart:core`).
- The widget API targets current Dart-based Flutter (3.4x / 3.47). Material
  widgets come from the SDK; if a future release moves them to an opt-in
  package, add that package to `pubspec.yaml` and update the
  `package:flutter/material.dart` imports.
- `flutter analyze` may warn about process handles that are not disposed
  before the process exits - intentional, the handles are short lived.

Enjoy boosting. Game on! 🎮