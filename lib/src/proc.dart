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

import 'models.dart';

const String _PROC = '/proc';

/// Full scan of /proc: returns every readable process.
Future<List<ProcessSummary>> scanProcesses() async {
  final result = <ProcessSummary>[];
  try {
    await for (final entity in Directory(_PROC).list()) {
      if (!(entity is Directory)) continue;
      final basename = entity.path.split('/').last;
      final pid = int.tryParse(basename);
      if (pid == null || pid <= 0) continue;
      final summary = await _readProcess(pid, '${_PROC}/$basename');
      if (summary != null) result.add(summary);
    }
  } catch (e) {
    // /proc is not accessible (e.g. sandboxed) - callers surface a hint.
  }
  result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return result;
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
  return process.name.contains(p) || process.cmdline.toLowerCase().contains(p);
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