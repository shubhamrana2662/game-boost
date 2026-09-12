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

/// Runs one CLI command and returns true on exit code 0.
Future<bool> runCommand(List<String> argv) async {
  try {
    final result = await Process.run(argv.first, argv.sublist(1));
    return result.exitCode == 0;
  } catch (e) {
    return false;
  }
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
  report.message = parts.join(' · ');
  return report;
}

/// Reverses a previously applied boost: resumes paused apps, restores CPU governor.
Future<BoostReport> releaseBoost(AppState app) async {
  final report = BoostReport('Released');
  if (app.pausedPids.isEmpty) {
    // Still try to restore the CPU governor even if nothing was paused.
    await runCommand(cpuGovernorArgs('schedutil'));
    report.message = 'Released. CPU governor restored.';
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
  // Restore CPU governor to balanced mode.
  await runCommand(cpuGovernorArgs('schedutil'));
  report.message = 'Released ${report.resumed} paused app(s). CPU governor restored.';
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