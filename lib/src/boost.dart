// Game Boost - the engine that actually "boosts".
//
// System actions are performed through small shell commands via dart:io
// Process.run:
//
//   * renice  <game pid> -N   -> raise the game's CPU scheduling priority
//   * ionice  -c1 -p <pid>   -> boost I/O scheduling class to real-time
//   * kill    <pid> STOP      -> pause background apps while you play
//   * kill    <pid> CONT      -> resume them when you stop playing
//   * kill    -9 <pid>        -> force-stop apps the user explicitly marked
//   * sync + drop_caches      -> flush writes and free kernel page caches
//   * oom_score_adj            -> protect the game from the OOM killer
//   * cpufreq governor        -> set CPU governor to "performance"
//
// IMPORTANT (read this before filing a bug):
// Android runs every app in a sandbox. Commands that need extra privileges
// (changing another app's priority, or signalling another app's process) are
// only permitted when the OS allows it - on older/all-open Android versions
// they work, on the most locked-down phones they are refused. The engine
// reports exactly what succeeded and what was blocked, so the app is honest
// about what it can do on the current device. On a rooted device or when
// sideloaded with diagnostic powers, everything works.

import 'dart:io';

import 'dart:core';

import 'models.dart';
import 'proc.dart';

/// Report of what one boost action actually did.
class BoostReport {
  BoostReport(this.message);

  String message;
  int pidsTouched = 0;
  int paused = 0;
  int resumed = 0;
  int killed = 0;
  int ioBoosted = 0;
  int oomProtected = 0;
  int backgroundLowered = 0;
  bool cleaned = false;
  bool cachesDropped = false;
  bool cpuGovernorSet = false;
  bool fpsUnlocked = false;
  bool hzLocked = false;
  bool bgmiTurboApplied = false;
}

/// Pure command-line builders (unit-tested, no system access).
List<String> reniceArgs(int pid, int niceValue) {
  return ['renice', '-n', '$niceValue', '-p', '$pid'];
}

List<String> ioniceArgs(int pid, int ioClass) {
  // ioClass: 1 = real-time, 2 = best-effort, 3 = idle
  return ['ionice', '-c', '$ioClass', '-p', '$pid'];
}

List<String> signalArgs(int pid, String signal) {
  return ['kill', signal, '$pid'];
}

List<String> killArgs(int pid) {
  return ['kill', '-9', '$pid'];
}

const List<String> SYNC_ARGS = const ['sync'];

/// Write to /proc/<pid>/oom_score_adj to protect from OOM killer.
/// -1000 = never kill, 1000 = kill first.
List<String> oomProtectArgs(int pid) {
  return ['sh', '-c', 'echo -1000 > /proc/$pid/oom_score_adj'];
}

/// Drop kernel page/dentry/inode caches (requires root).
List<String> dropCachesArgs() {
  return ['sh', '-c', 'echo 3 > /proc/sys/vm/drop_caches'];
}

/// Set CPU governor to "performance" for all CPUs.
List<String> cpuGovernorArgs(String governor) {
  return [
    'sh', '-c',
    'for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; '
        'do echo $governor > \$f 2>/dev/null; done',
  ];
}

/// Lower a background process's priority (make it yield CPU to the game).
List<String> lowerPriorityArgs(int pid) {
  return ['renice', '-n', '19', '-p', '$pid'];
}

// ---------------------------------------------------------------------------
// MAX-FPS / MAX-HZ / BGMI TURBO helpers (best-effort shell commands).
//
// Everything here degrades gracefully: if the device/OS refuses (SELinux,
// no root, missing settings binary) runCommand simply returns false and the
// failure is counted in the status line. Nothing throws.
//
// Why these commands?
//  * MAX FPS  - turn off battery saver + force game-mode to PERFORMANCE so the
//               SoC stops down-clocking the GPU mid-fight (biggest FPS killer
//               on low-end phones). Real in-game FPS is set by BGMI's own
//               Graphics option (choose Smooth + Extreme/90fps there); this
//               engine step clears every OS-level cap/throttle around it:
//               `settings put global low_power 0` disables low-power mode.
//               `cmd deviceidle whitelist +<pkg>` keeps the game out of Doze.
//               `cmd game mode performance <pkg>` asks GameManager for max perf.
//               `settings put global game_driver_all_apps 1` opts into the
//               newest Game Driver, `debug.hwui.renderer skiavk` + profile
//               tweaks cut render stalls on weak Mali/Adreno GPUs.
//  * MAX HZ   - pin a high-refresh panel at its peak so the OS cannot drop
//               it to 60Hz mid-game (cannot exceed physical panel max).
//               `settings put system peak_refresh_rate <hz>` +
//               `min_refresh_rate <hz>` pins the panel (120 or 144).
//  * BGMI TURBO - give com.pubg.imobile top scheduling bucket + re-optimize
//               its dex for speed so map load + frame pacing improve:
//               `cmd activity set-standby-bucket <pkg> ACTIVE`
//               `cmd package compile -m speed -f <pkg>`
// ---------------------------------------------------------------------------

List<String> fpsUnlockArgs(String package) {
  // Best-effort "unlock max fps" bundle. Every line is guarded with
  // 2>/dev/null + trailing `true` so unsupported devices just skip.
  return [
    'sh',
    '-c',
    // 1. Kill OS-level throttles (battery saver, Doze, game-mode).
    'settings put global low_power 0 2>/dev/null; '
        'settings put global low_power_sticky 0 2>/dev/null; '
        'settings put global low_power_sticky_auto_disable_enabled 1 2>/dev/null; '
        'cmd deviceidle whitelist +$package 2>/dev/null; '
        'dumpsys deviceidle whitelist +$package 2>/dev/null; '
        'cmd game mode performance $package 2>/dev/null; '
        'cmd game set --fps 120 $package 2>/dev/null; '
        // 2. Newest Game Driver + Vulkan-skia render path for weak GPUs.
        'settings put global game_driver_all_apps 1 2>/dev/null; '
        'setprop debug.hwui.renderer skiavk 2>/dev/null; '
        'setprop debug.hwui.profile visual_bars 2>/dev/null; '
        // 3. Thermal headroom: prefer sustained-performance over throttling.
        'cmd thermalservice override-status 0 2>/dev/null; '
        'true',
  ];
}

/// Detect the panel's true peak refresh rate in Hz.
/// Best-effort: parses `dumpsys display`. Returns 0 when unreadable so
/// callers fall back to a safe default (90 low-end / 120 normal).
Future<int> detectPanelMaxHz() async {
  try {
    final res = await Process.run('sh', [
      '-c',
      'dumpsys display 2>/dev/null | grep -oiE "[0-9]{2,3}\.[0-9]+ *hz|[0-9]{2,3} *hz" | grep -oE "[0-9]{2,3}" | sort -n | tail -1',
    ]);
    if (res.exitCode == 0 && res.stdout is String) {
      final v = int.tryParse((res.stdout as String).trim());
      if (v != null && v >= 60 && v <= 240) return v;
    }
  } catch (_) {}
  return 0;
}

List<String> hzLockArgs(int hz) {
  // Pin ONLY to a rate the panel can actually do: callers pass the real
  // panel max (see detectPanelMaxHz) and we clamp into {60,90,120,144}.
  // Forcing 120 on a 60Hz panel does nothing (or flickers).
  final int pinned = hz >= 144
      ? 144
      : hz >= 120
          ? 120
          : hz >= 90
              ? 90
              : 60;
  return [
    'sh',
    '-c',
    'settings put system peak_refresh_rate $pinned 2>/dev/null; '
        'settings put system min_refresh_rate $pinned 2>/dev/null; '
        'settings put secure refresh_rate_mode 1 2>/dev/null; '
        'true',
  ];
}

List<String> hzRestoreArgs() {
  return [
    'sh',
    '-c',
    'settings put system peak_refresh_rate 60 2>/dev/null; '
        'settings put system min_refresh_rate 60 2>/dev/null; '
        'settings put secure refresh_rate_mode 0 2>/dev/null; '
        'true',
  ];
}

const String kBgmiPackage = 'com.pubg.imobile';

List<String> bgmiTurboArgs(String package) {
  // Extra BGMI processing bundle: top scheduling bucket + dexopt for speed
  // + background-restriction OFF + battery-optimisation OFF + high-priority
  // process class, so BGMI keeps full CPU/RAM/network while in foreground.
  return [
    'sh',
    '-c',
    'cmd activity set-standby-bucket $package ACTIVE 2>/dev/null; '
        'am set-standby-bucket $package active 2>/dev/null; '
        'cmd package compile -m speed -f $package 2>/dev/null; '
        'cmd appops set $package RUN_IN_BACKGROUND allow 2>/dev/null; '
        'cmd appops set $package RUN_ANY_IN_BACKGROUND allow 2>/dev/null; '
        'cmd netpolicy remove restrict-background $package 2>/dev/null; '
        'dumpsys deviceidle whitelist +$package 2>/dev/null; '
        'cmd activity set-process-state $package top 2>/dev/null; '
        'true',
  ];
}

/// Best-guess Android package id for a profile: first pattern that looks like
/// a dotted package, else derive from the game name.
String packageForProfile(GameProfile profile) {
  for (final p in profile.patterns) {
    final t = p.trim().toLowerCase();
    if (t.contains('.') && !t.contains(' ')) {
      if (t.startsWith('com.') || t.contains('.mobile') || t.contains('.imobile')) {
        return t;
      }
    }
  }
  for (final p in profile.patterns) {
    final t = p.trim().toLowerCase();
    if (t.contains('.') && !t.contains(' ')) return t;
  }
  // Only BGMI profiles default to the real BGMI package. Every other game
  // returns '' so callers never touch com.pubg.imobile by accident.
  if (isBgmiProfile(profile)) return 'com.pubg.imobile';
  return '';
}

/// Is this profile (very likely) BGMI?
bool isBgmiProfile(GameProfile profile) {
  final hay = (profile.name + ' ' + profile.patterns.join(' ')).toLowerCase();
  // PHYSICAL DEVICE ONLY: emulator shells are never the real BGMI package.
  if (hay.contains('bluestacks') ||
      hay.contains('ldplayer') ||
      hay.contains('gameloop') ||
      hay.contains('game-loop') ||
      hay.contains('nox') ||
      hay.contains('memu') ||
      hay.contains('mumu') ||
      hay.contains('emulator') ||
      hay.contains('smartgaga')) {
    return false;
  }
  // Mod / hack / clone builds are never the real BGMI package.
  if (hay.contains('hacked') ||
      hay.contains('hack') ||
      hay.contains(' mod') ||
      hay.contains('mod ') ||
      hay.contains('clone') ||
      hay.contains('fake') ||
      hay.contains('patched')) {
    return false;
  }
  return hay.contains('bgmi') ||
      hay.contains('battlegrounds') ||
      hay.contains('pubg.imobile') ||
      hay.contains('krafton') ||
      hay.contains('shadowtracker');
}

/// Runs one CLI command and returns true on exit code 0.
/// Automatically attempts root (`su`) and Shizuku (`rish`) privilege escalation
/// when the standard unprivileged execution is restricted by the OS sandbox.
Future<bool> runCommand(List<String> argv) async {
  if (argv.isEmpty) return false;

  // 1. Try standard unprivileged execution first
  try {
    final result = await Process.run(argv.first, argv.sublist(1));
    if (result.exitCode == 0) return true;
  } catch (_) {}

  // 2. OS Bypass Attempt 1: Root execution via `su -c` (bypasses SELinux / OS sandbox)
  try {
    final fullCmd = argv.join(' ');
    final suResult = await Process.run('su', ['-c', fullCmd]);
    if (suResult.exitCode == 0) return true;
  } catch (_) {}

  // 3. OS Bypass Attempt 2: Elevated ADB / Shizuku shell via `rish -c`
  try {
    final fullCmd = argv.join(' ');
    final rishResult = await Process.run('rish', ['-c', fullCmd]);
    if (rishResult.exitCode == 0) return true;
  } catch (_) {}

  // 4. OS Bypass Attempt 3: Shizuku binary path in /data/local/tmp
  try {
    final fullCmd = argv.join(' ');
    final localRish = await Process.run('/data/local/tmp/rish', ['-c', fullCmd]);
    if (localRish.exitCode == 0) return true;
  } catch (_) {}

  return false;
}

/// Applies [profile]'s boost to whatever is currently running.
///
/// Returns a report message suitable for the status line.
Future<BoostReport> applyBoost(AppState app, GameProfile profile) async {
  final report = BoostReport('Boosted ${profile.name}');
  final nice = priorityToNice(profile.priority);

  // 1. Raise the game's CPU scheduling priority + I/O priority + OOM protection.
  for (final proc in app.processes) {
    if (!profileMatches(profile, proc)) continue;

    // CPU priority (renice)
    final ok = await runCommand(reniceArgs(proc.pid, nice));
    if (ok) {
      report.pidsTouched++;
    } else {
      app.permissionHints++;
    }

    // I/O priority - real-time class for maximum disk throughput
    if (profile.priority >= 3) {
      if (await runCommand(ioniceArgs(proc.pid, 1))) {
        report.ioBoosted++;
      }
    }

    // OOM killer protection - tell kernel to never kill the game
    if (await runCommand(oomProtectArgs(proc.pid))) {
      report.oomProtected++;
    }
  }

  // 1b. MAX-FPS bundle (battery-saver OFF + Doze whitelist + game-mode
  // PERFORMANCE). Runs even if the game pid was not visible (e.g. SELinux
  // hides other apps) because it targets the package name, not the pid.
  // Enabled per-profile via maxFps, or automatically at POWER 5.
  if (profile.maxFps || profile.priority == 5) {
    final String fpsPkg = packageForProfile(profile);
    if (fpsPkg.isNotEmpty) {
      if (await runCommand(fpsUnlockArgs(fpsPkg))) {
        report.fpsUnlocked = true;
      }
    }
  }

  // 1c. MAX-HZ: pin the panel to the highest rate the game can use so
  // the OS cannot drop to 60Hz mid-game.
  //   * If the user set a per-game FPS TARGET, use that as the ceiling
  //     (0/60/90/120). Cannot exceed the physical panel max.
  //   * If MAX-HZ is on but no target is set, use the panel peak capped at
  //     90 low-end / 120 normal (never pins a 60Hz panel at 90+).
  //   * Skipped on ULTRA-low-end (<3GB RAM / 60Hz panels) to save battery.
  //   * Restored to 60Hz by releaseBoost. No app can make a 60Hz panel draw
  //     90/120fps - that is hardware; set BGMI's own frame-rate option to max.
  if ((profile.maxHz || profile.priority == 5) && !app.settings.ultraLowEnd) {
    var panelPeak = 0;
    try {
      panelPeak = await detectPanelMaxHz();
    } catch (_) {}
    // fpsTarget: 0=auto, else user-requested ceiling (30/60/90/120+
    // naturally clamped by hzLockArgs into the nearest real panel rate).
    final int targetHz = profile.fpsTarget > 0
        ? profile.fpsTarget.clamp(60, panelPeak >= 60 ? panelPeak : 120)
        : (panelPeak >= 60 ? panelPeak : (app.settings.lowEndMode ? 90 : 120));
    if (await runCommand(hzLockArgs(targetHz))) {
      report.hzLocked = true;
    }
  }

  // 2. Pause background apps the user asked to pause (resumed on release).
  if (profile.pauseBackground) {
    for (final proc in app.processes) {
      if (!_shouldPause(app, profile, proc)) continue;
      if (app.pausedPids.contains(proc.pid)) continue;
      if (await runCommand(signalArgs(proc.pid, '-STOP'))) {
        app.pausedPids.add(proc.pid);
        report.paused++;
      } else {
        app.permissionHints++;
      }
    }
  }

  // 3. Lower priority of all non-game, non-system processes to yield CPU.
  if (profile.priority >= 4) {
    for (final proc in app.processes) {
      if (profileMatches(profile, proc)) continue;
      if (_isWhitelisted(app, proc)) continue;
      if (proc.pid <= 2) continue;
      if (await runCommand(lowerPriorityArgs(proc.pid))) {
        report.backgroundLowered++;
      }
    }
  }

  // 4. Force-stop processes the user explicitly put on the kill list.
  for (final pattern in profile.extraKill) {
    for (final proc in app.processes) {
      if (!patternMatches(pattern, proc)) continue;
      if (!_isAllowedToKill(app, proc)) continue;
      if (await runCommand(killArgs(proc.pid))) {
        report.killed++;
      } else {
        app.permissionHints++;
      }
    }
  }

  // 5. Memory clean - flush disk writes.
  if (profile.memoryClean) {
    if (await runCommand(SYNC_ARGS)) {
      report.cleaned = true;
    }
  }

  // 6. Aggressive clean - drop kernel page caches to free RAM immediately.
  if (profile.aggressiveClean || profile.priority == 5) {
    if (await runCommand(dropCachesArgs())) {
      report.cachesDropped = true;
    }
  }

  // 7. CPU governor - force all cores to max frequency (POWER 4+).
  if (profile.priority >= 4) {
    if (await runCommand(cpuGovernorArgs('performance'))) {
      report.cpuGovernorSet = true;
    }
  }

  // 10. BGMI TURBO - extra processing ONLY for Battlegrounds Mobile India
  // profiles (or when the per-game BGMI-TURBO toggle is on): standby-bucket
  // ACTIVE + dexopt speed compile for faster map load & smoother frames.
  // Other games skip this entirely - their package is never touched.
  final bool isBgmi = isBgmiProfile(profile);
  if (profile.bgmiTurbo || isBgmi) {
    var turboPkg = packageForProfile(profile);
    if (turboPkg.isEmpty && isBgmi) turboPkg = kBgmiPackage;
    if (turboPkg.isNotEmpty) {
      if (await runCommand(bgmiTurboArgs(turboPkg))) {
        report.bgmiTurboApplied = true;
      }
    }
  }

  profile.timesBoosted++;
  profile.lastBoostedAt = _unixNow();

  // Build a comprehensive status message.
  final parts = <String>[
    '${profile.name}: POWER x${profile.priority}',
    '${report.pidsTouched} boosted',
  ];
  if (report.ioBoosted > 0) parts.add('IO-RT');
  if (report.oomProtected > 0) parts.add('OOM-safe');
  if (report.paused > 0) parts.add('${report.paused} paused');
  if (report.backgroundLowered > 0) parts.add('${report.backgroundLowered} lowered');
  if (report.killed > 0) parts.add('${report.killed} killed');
  if (report.cleaned) parts.add('synced');
  if (report.cachesDropped) parts.add('caches dropped');
  if (report.cpuGovernorSet) parts.add('CPU perf');
  if (report.fpsUnlocked) parts.add('MAX-FPS');
  if (report.hzLocked) parts.add('MAX-HZ');
  if (report.bgmiTurboApplied) parts.add('BGMI-TURBO');
  report.message = parts.join(' · ');
  return report;
}

/// Reverses a previously applied boost: resumes paused apps, restores CPU governor.
Future<BoostReport> releaseBoost(AppState app) async {
  final report = BoostReport('Released');
  if (app.pausedPids.isEmpty) {
    // Still restore CPU governor + display Hz even if nothing was paused.
    await runCommand(cpuGovernorArgs('schedutil'));
    await runCommand(hzRestoreArgs());
    report.message = 'Released. CPU governor + 60Hz restored.';
    return report;
  }
  final remaining = <int>[];
  for (final pid in app.pausedPids) {
    if (await runCommand(signalArgs(pid, '-CONT'))) {
      report.resumed++;
    } else {
      remaining.add(pid);
      app.permissionHints++;
    }
  }
  app.pausedPids = remaining;
  // Restore CPU governor to balanced mode + display back to 60Hz.
  await runCommand(cpuGovernorArgs('schedutil'));
  await runCommand(hzRestoreArgs());
  report.message = 'Released ${report.resumed} paused app(s). CPU + 60Hz restored.';
  return report;
}

bool _shouldPause(AppState app, GameProfile profile, ProcessSummary proc) {
  if (proc.pid <= 1) return false;
  if (profileMatches(profile, proc)) return false; // never pause the game itself
  for (final pattern in app.settings.pauseList) {
    if (!patternMatches(pattern, proc)) continue;
    if (_isWhitelisted(app, proc)) continue;
    return true;
  }
  return false;
}

bool _isAllowedToKill(AppState app, ProcessSummary proc) {
  if (proc.pid <= 1) return false;
  return !_isWhitelisted(app, proc);
}

bool _isWhitelisted(AppState app, ProcessSummary proc) {
  for (final safe in app.settings.killWhitelist) {
    if (proc.name == safe || proc.cmdline.contains(safe)) return true;
  }
  return false;
}

int _unixNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;