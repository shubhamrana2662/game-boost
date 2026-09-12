// Game Boost - data models shared across the app.

/// A user profile for one game.
///
/// [patterns] are case-insensitive substrings matched against the running
/// process name (the executable part of `/proc/<pid>/cmdline`) and full
/// command line. If any pattern matches, the game counts as "running".
class GameProfile {
  GameProfile({
    required String name,
    List<String> patterns = const [],
    int priority = 3,
    bool autoBoost = false,
    bool pauseBackground = false,
    bool memoryClean = false,
    List<String> extraKill = const [],
    bool detected = false,
    bool aggressiveClean = false,
    int timesBoosted = 0,
    int lastBoostedAt = 0,
  }) {
    this.name = name;
    this.patterns = List.of(patterns);
    this.priority = priority < 1
        ? 1
        : (priority > 5 ? 5 : priority);
    this.autoBoost = autoBoost;
    this.pauseBackground = pauseBackground;
    this.memoryClean = memoryClean;
    this.extraKill = List.of(extraKill);
    this.detected = detected;
    this.aggressiveClean = aggressiveClean;
    this.timesBoosted = timesBoosted;
    this.lastBoostedAt = lastBoostedAt;
  }

  String name;
  List<String> patterns;
  int priority; // 1 = gentle ... 5 = maximum
  bool autoBoost;
  bool pauseBackground;
  bool memoryClean;
  List<String> extraKill;
  bool detected;
  bool aggressiveClean; // drop kernel page caches during boost cycles
  int timesBoosted;
  int lastBoostedAt;

  /// Human readable list of patterns for the editor screen.
  String patternsSummary() {
    if (patterns.isEmpty) return 'auto (detected)';
    return patterns.join(', ');
  }

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'patterns': patterns,
      'priority': priority,
      'autoBoost': autoBoost,
      'pauseBackground': pauseBackground,
      'memoryClean': memoryClean,
      'extraKill': extraKill,
      'detected': detected,
      'aggressiveClean': aggressiveClean,
      'timesBoosted': timesBoosted,
      'lastBoostedAt': lastBoostedAt,
    };
  }

  static GameProfile fromJson(Map<String, Object?> json) {
    return GameProfile(
      name: _str(json['name'], 'Unknown'),
      patterns: _strList(json['patterns']),
      priority: _int(json['priority'], 3),
      autoBoost: _bool(json['autoBoost'], false),
      pauseBackground: _bool(json['pauseBackground'], false),
      memoryClean: _bool(json['memoryClean'], false),
      extraKill: _strList(json['extraKill']),
      detected: _bool(json['detected'], false),
      aggressiveClean: _bool(json['aggressiveClean'], false),
      timesBoosted: _int(json['timesBoosted'], 0),
      lastBoostedAt: _int(json['lastBoostedAt'], 0),
    );
  }
}

/// Global application settings.
class Settings {
  bool masterAutoBoost = false;
  bool confirmKill = true;
  bool lowEndMode = true; // budget phone optimizations (see README)
  int scanIntervalSec = 5;
  List<String> pauseList = const []; // background app names to pause during a game
  List<String> killWhitelist = const [
    'game_boost',
    'systemd',
    'kernel',
    'init',
    '1',
  ];

  Map<String, Object?> toJson() {
    return {
      'masterAutoBoost': masterAutoBoost,
      'confirmKill': confirmKill,
      'lowEndMode': lowEndMode,
      'scanIntervalSec': scanIntervalSec,
      'pauseList': pauseList,
      'killWhitelist': killWhitelist,
    };
  }

  static Settings fromJson(Map<String, Object?> json) {
    final s = Settings();
    s.masterAutoBoost = _bool(json['masterAutoBoost'], false);
    s.confirmKill = _bool(json['confirmKill'], true);
    s.lowEndMode = _bool(json['lowEndMode'], true);
    s.scanIntervalSec = _int(json['scanIntervalSec'], 5).clamp(2, 15) as int;
    s.pauseList = List.of(_strList(json['pauseList']));
    final wl = _strList(json['killWhitelist']);
    if (wl.isNotEmpty) s.killWhitelist = wl;
    return s;
  }
}

/// One scanner result.
class ProcessSummary {
  ProcessSummary(this.pid, this.name, this.cmdline, this.rssKb);
  final int pid;
  final String name;
  final String cmdline;
  final int rssKb;
}

/// Parsed /proc/meminfo snapshot (values in kB).
class MemoryStats {
  MemoryStats(this.totalKb, this.freeKb);
  final int totalKb;
  final int freeKb;
  int usedKb() => totalKb - freeKb;
  double fraction() => totalKb <= 0 ? 0.0 : (totalKb - freeKb) / totalKb;
}

/// Everything the UI needs. Lives inside the app [State] object.
class AppState {
  String screen = 'home'; // 'home' | 'edit' | 'settings'
  String? editingName; // game being edited (null => new game)
  String status = 'Ready. Tap SCAN to look for running games.';
  List<GameProfile> games = [];
  List<ProcessSummary> processes = [];
  List<ProcessSummary> candidates = []; // detected apps that can be added
  Map<String, bool> running = {}; // game name -> currently running + boosted
  List<int> pausedPids = []; // pids we SIGSTOP'd (resumed on game exit)
  Settings settings = Settings();
  MemoryStats memory = MemoryStats(0, 0);
  bool scanning = false;
  bool boosting = false;
  int scanCount = 0;
  int permissionHints = 0; // number of actions blocked by OS permissions
  bool permissionWarned = false; // true once we inform about OS-blocked actions
  bool loadedFromDisk = false;
}

/// Shared JSON helpers (used by [GameProfile.toJson]/[fromJson]).
String _str(Object? v, String fallback) {
  if (v is String s) return s;
  return fallback;
}

int _int(Object? v, int fallback) {
  if (v is num n) return n.toInt();
  if (v is String s) return int.tryParse(s) ?? fallback;
  return fallback;
}

bool _bool(Object? v, bool fallback) {
  if (v is bool b) return b;
  if (v is num n) return n != 0;
  return fallback;
}

List<String> _strList(Object? v) {
  if (!(v is List)) return [];
  final out = <String>[];
  for (Object? item in (v as List)) {
    if (item is String s && s.isNotEmpty && !out.contains(s)) out.add(s);
  }
  return out;
}

/// Render a byte count as a friendly string ("1.2 GB").
String formatKb(int kb) {
  if (kb <= 0) return '0 B';
  final categories = [
    'B',
    'KB',
    'MB',
    'GB',
    'TB',
  ];
  var value = kb * 1024.0;
  var level = 0;
  while (value >= 1024 && level < categories.length - 1) {
    value /= 1024;
    level++;
  }
  final text = value.toStringAsFixed(1);
  return '${text} ${categories[level]}';
}