// Game Boost - low-level readers for Android's /proc filesystem.
//
// On Android these give us: the list of running process ids, each process'
// executable name + full command line (cmdline), its resident memory (status)
// and the global memory snapshot (meminfo).
//
// Everything is defensive: if /proc is restricted or hidden (some Android
// versions hide other apps' processes), the scanners degrade gracefully and
// the UI shows a hint instead of crashing.

import 'dart:io';

import 'game_library.dart';
import 'models.dart';

const String _PROC = '/proc';

/// Full scan of running processes and installed apps:
/// 1. Tries /proc direct listing (works on rooted devices and Linux)
/// 2. Falls back to shell `ps -A` (works on non-rooted Android)
/// 3. Detects installed user packages via `pm list packages -3`
Future<List<ProcessSummary>> scanProcesses() async {
  final result = <ProcessSummary>[];
  final seenNames = <String>{};

  // 1. Direct /proc traversal (fast, works if root or older OS)
  try {
    await for (final entity in Directory(_PROC).list()) {
      if (entity is! Directory) continue;
      final basename = entity.path.split('/').last;
      final pid = int.tryParse(basename);
      if (pid == null || pid <= 0) continue;
      final summary = await _readProcess(pid, '$_PROC/$basename');
      if (summary != null && !seenNames.contains(summary.name)) {
        seenNames.add(summary.name);
        result.add(summary);
      }
    }
  } catch (_) {
    // /proc listing is restricted by SELinux on non-root Android
  }

  // 2. Shell ps fallback (works across Android versions)
  if (result.isEmpty) {
    try {
      final psRes = await Process.run('sh', ['-c', 'ps -A || ps -ef || ps']);
      if (psRes.exitCode == 0 && psRes.stdout is String) {
        final lines = (psRes.stdout as String).split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('USER') || trimmed.startsWith('PID')) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            int? pid;
            for (final part in parts) {
              final parsed = int.tryParse(part);
              if (parsed != null && parsed > 0) {
                pid = parsed;
                break;
              }
            }
            final rawName = parts.last;
            if (pid != null && rawName.isNotEmpty && !rawName.startsWith('[') && rawName != 'ps') {
              final clean = processNameFromCmdline(rawName);
              if (clean != 'unknown' && !seenNames.contains(clean)) {
                seenNames.add(clean);
                result.add(ProcessSummary(pid, clean, rawName, 0));
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  // 3. Android Package Manager scan (lists installed 3rd-party games/apps)
  try {
    final pmRes = await Process.run('sh', ['-c', 'pm list packages -3 || cmd package list packages -3']);
    if (pmRes.exitCode == 0 && pmRes.stdout is String) {
      final lines = (pmRes.stdout as String).split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('package:')) continue;
        final pkg = trimmed.substring('package:'.length).trim();
        if (pkg.isEmpty) continue;
        final cleanName = _cleanPackageName(pkg);
        if (!seenNames.contains(cleanName)) {
          seenNames.add(cleanName);
          result.add(ProcessSummary(0, cleanName, pkg, 0));
        }
      }
    }
  } catch (_) {}

  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
}

String _cleanPackageName(String pkg) {
  for (final known in KNOWN_GAMES) {
    for (final pattern in known.patterns) {
      if (pkg.toLowerCase().contains(pattern.toLowerCase())) {
        return known.name;
      }
    }
  }
  final parts = pkg.split('.');
  if (parts.length > 1) {
    final last = parts.last;
    if (last.length > 2) return last;
  }
  return pkg;
}

/// Reads /proc/<pid>/meminfo in kB.
Future<MemoryStats> readMemory() async {
  var total = 0;
  var free = 0;
  try {
    final content = await File('${_PROC}/meminfo').readAsString();
    for (final line in content.split('\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final key = line.substring(0, colon).trim();
      final valueKb = int.tryParse(_firstToken(line.substring(colon + 1))) ?? 0;
      switch (key) {
        case 'MemTotal':
          total = valueKb;
          break;
        case 'MemAvailable':
          free = valueKb;
          break;
        case 'MemFree':
          if (free == 0) free = valueKb;
          break;
      }
    }
  } catch (e) {
    // /proc unavailable; caller shows 0 B.
  }
  return MemoryStats(total, free);
}

Future<ProcessSummary?> _readProcess(int pid, String dir) async {
  // cmdline is NUL separated, e.g. "/opt/games/MLBB/game\0--flag\0".
  var cmdline = '';
  try {
    cmdline = await File('${dir}/cmdline').readAsString();
  } catch (e) {
    return null;
  }
  final name = processNameFromCmdline(cmdline);
  if (name == 'unknown') return null;
  var rssKb = 0;
  try {
    final status = await File('${dir}/status').readAsString();
    rssKb = _rssKbFromStatus(status);
  } catch (e) {
    // RSS optional.
  }
  return ProcessSummary(pid, name, cmdline, rssKb);
}

/// Extracts a stable display name from a raw cmdline string (may contain NULs).
String processNameFromCmdline(String raw) {
  final parts = raw.split('\u0000');
  if (parts.isEmpty || parts.first.isEmpty) return 'unknown';
  final first = parts.first;
  final slash = _lastSlash(first);
  var name = slash >= 0 ? first.substring(slash + 1) : first;
  name = name.trim().toLowerCase();
  if (name.isEmpty) return 'unknown';
  if (name.endsWith('.exe')) name = name.substring(0, name.length - 4);
  if (name.endsWith('.app')) name = name.substring(0, name.length - 4);
  return name;
}

int _lastSlash(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
    if (s.codeUnitAt(i) == 0x2F) return i;
  }
  return -1;
}

String _firstToken(String s) {
  final t = s.trim();
  final space = t.indexOf(' ');
  return space < 0 ? t : t.substring(0, space);
}

int _rssKbFromStatus(String status) {
  for (final line in status.split('\n')) {
    if (!line.startsWith('VmRSS:')) continue;
    return int.tryParse(_firstToken(line.substring(6))) ?? 0;
  }
  return 0;
}

/// Case-insensitive substring match: is [pattern] present anywhere in the
/// process name or full command line?
bool patternMatches(String pattern, ProcessSummary process) {
  if (pattern.isEmpty) return false;
  final p = pattern.toLowerCase();
  return process.name.toLowerCase().contains(p) ||
      process.cmdline.toLowerCase().contains(p);
}

/// Is [profile] matched by [process]?
bool profileMatches(GameProfile profile, ProcessSummary process) {
  for (final pattern in profile.patterns) {
    if (patternMatches(pattern, process)) return true;
  }
  return false;
}

/// Priority level (1..5) -> Linux niceness value (-20 most favorable).
int priorityToNice(int priority) {
  switch (priority) {
    case 5:
      return -20;
    case 4:
      return -15;
    case 3:
      return -10;
    case 2:
      return -5;
    default:
      return 0;
  }
}

/// User-facing label for a priority level.
String priorityLabel(int priority) {
  switch (priority) {
    case 1:
      return 'Gentle';
    case 2:
      return 'Light';
    case 3:
      return 'Sport';
    case 4:
      return 'Turbo';
    case 5:
      return 'MAX';
  }
  return 'Sport';
}