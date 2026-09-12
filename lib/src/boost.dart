// Game Boost - the engine that actually "boosts".
//
// All system actions are performed through small shell commands spawned with
// flutter:services `process_start`:
//
//   * renice  <game pid> -N   -> raise the game's CPU scheduling priority
//   * kill    <pid> STOP      -> pause background apps while you play
//   * kill    <pid> CONT      -> resume them when you stop playing
//   * kill    -9 <pid>        -> force-stop apps the user explicitly marked
//   * sync                    -> flush writes to disk (memory clean)
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
  bool cleaned = false;
}

/// Pure command-line builders (unit-tested, no system access).
List<String> reniceArgs(int pid, int niceValue) {
  return ['renice', '-n', '$niceValue', '-p', '$pid'];
}

List<String> signalArgs(int pid, String signal) {
  return ['kill', signal, '$pid'];
}

List<String> killArgs(int pid) {
  return ['kill', '-9', '$pid'];
}

const List<String> SYNC_ARGS = const ['sync'];

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

  // 1. Raise the game's scheduling priority.
  for (final proc in app.processes) {
    if (!profileMatches(profile, proc)) continue;
    final ok = await runCommand(reniceArgs(proc.pid, nice));
    if (ok) {
      report.pidsTouched++;
    } else {
      app.permissionHints++;
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

  // 3. Force-stop processes the user explicitly put on the kill list.
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

  // 4. Memory clean - best effort.
  if (profile.memoryClean) {
    if (await runCommand(SYNC_ARGS)) {
      report.cleaned = true;
    }
  }

  profile.timesBoosted++;
  profile.lastBoostedAt = _unixNow();
  report.message =
      '${profile.name}: priority x${profile.priority}, '
      '${report.pidsTouched} proc(s), ${report.paused} paused, '
      '${report.killed} killed, clean=${report.cleaned}.';
  return report;
}

/// Reverses a previously applied boost for [profile]: resumes paused apps.
Future<BoostReport> releaseBoost(AppState app) async {
  final report = BoostReport('Released');
  if (app.pausedPids.isEmpty) return report;
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
  report.message = 'Released ${report.resumed} paused app(s).';
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