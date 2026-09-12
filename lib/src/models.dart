// Game Boost - data models shared across the app.

/// A user profile for one game.
///
/// [patterns] are case-insensitive substrings matched against the running
/// process name (the executable part of `/proc/<pid>/cmdline`) and full
/// command line. If any pattern matches, the game counts as "running".
class GameProfile {
  String name;
  List<String> patterns;
  int priority; // 1 = gentle ... 5 = maximum
  bool autoBoost;
  bool pauseBackground;
  bool memoryClean;
  List<String> extraKill;
  bool detected;
  bool aggressiveClean; // drop kernel page caches during boost cycles
  bool maxFps; // best-effort: disable battery-saver + game-mode performance
  bool maxHz; // best-effort: lock display to peak refresh rate (120/144Hz)
  bool bgmiTurbo; // extra BGMI processing: standby-bucket ACTIVE + dexopt speed
  int fpsTarget; // 0=auto, else requested FPS ceiling (30/60/90/120)
  int timesBoosted;
  int lastBoostedAt;

  GameProfile({
    required this.name,
    List<String>? patterns,
    int priority = 4,
    this.autoBoost = true,
    this.pauseBackground = true,
    this.memoryClean = true,
    List<String>? extraKill,
    this.detected = false,
    this.aggressiveClean = true,
    this.maxFps = false,
    this.maxHz = false,
    this.bgmiTurbo = false,
    this.fpsTarget = 0,
    this.timesBoosted = 0,
    this.lastBoostedAt = 0,
  })  : patterns = patterns != null ? List.of(patterns) : [],
        extraKill = extraKill != null ? List.of(extraKill) : [],
        priority = priority < 1 ? 1 : (priority > 5 ? 5 : priority),
        fpsTarget = _snapFps(fpsTarget);

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
      'maxFps': maxFps,
      'maxHz': maxHz,
      'bgmiTurbo': bgmiTurbo,
      'fpsTarget': fpsTarget,
      'timesBoosted': timesBoosted,
      'lastBoostedAt': lastBoostedAt,
    };
  }

  static GameProfile fromJson(Map<String, Object?> json) {
    return GameProfile(
      name: _str(json['name'], 'Unknown'),
      patterns: _strList(json['patterns']),
      priority: _int(json['priority'], 4),
      autoBoost: _bool(json['autoBoost'], true),
      pauseBackground: _bool(json['pauseBackground'], true),
      memoryClean: _bool(json['memoryClean'], true),
      extraKill: _strList(json['extraKill']),
      detected: _bool(json['detected'], false),
      aggressiveClean: _bool(json['aggressiveClean'], true),
      maxFps: _bool(json['maxFps'], false),
      maxHz: _bool(json['maxHz'], false),
      bgmiTurbo: _bool(json['bgmiTurbo'], false),
      fpsTarget: _int(json['fpsTarget'], 0),
      timesBoosted: _int(json['timesBoosted'], 0),
      lastBoostedAt: _int(json['lastBoostedAt'], 0),
    );
  }
}

/// Global application settings.
class Settings {
  bool masterAutoBoost = true;
  bool confirmKill = true;
  bool lowEndMode = true; // budget phone optimizations (see README)
  bool ultraLowEnd = false; // <3GB RAM: ultra-strict guard (see README)
  int scanIntervalSec = 3;
  List<String> pauseList = const [
    'instagram',
    'facebook',
    'chrome',
    'whatsapp',
    'youtube',
    'tiktok',
    'snapchat',
    'discord',
    'telegram',
  ];
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
      'ultraLowEnd': ultraLowEnd,
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
    s.ultraLowEnd = _bool(json['ultraLowEnd'], false);
    final interval = _int(json['scanIntervalSec'], 3);
    s.scanIntervalSec = interval < 2 ? 2 : (interval > 15 ? 15 : interval);
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
  if (v is String) return v;
  return fallback;
}

int _int(Object? v, int fallback) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(Object? v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  return fallback;
}

List<String> _strList(Object? v) {
  if (v is! List) return [];
  final out = <String>[];
  for (final item in v) {
    if (item is String && item.isNotEmpty && !out.contains(item)) out.add(item);
  }
  return out;
}

/// Snap an FPS target to a supported step (0=auto, else 30/60/90/120).
int _snapFps(int v) {
  if (v <= 0) return 0;
  const steps = [30, 60, 90, 120];
  var best = steps[0];
  for (final s in steps) {
    if ((v - s).abs() < (v - best).abs()) best = s;
  }
  return best;
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