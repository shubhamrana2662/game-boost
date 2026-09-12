// Game Boost - the application core.
//
// A single StatefulWidget owns all mutable state (AppState) and the background
// watch loop; every mutation funnels through setState() so the whole UI
// re-renders (exactly the pattern recommended by the Flutter docs).

import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:core';

import 'boost.dart';
import 'controller.dart';
import 'game_library.dart';
import 'models.dart';
import 'proc.dart';
import 'store.dart';
import 'ui/edit_view.dart';
import 'ui/home_view.dart';
import 'ui/settings_view.dart';

/// App root. Kept const-constructible so the entry point can use
/// `runApp(const GameBoostApp())`.
class GameBoostApp extends StatefulWidget {
  const GameBoostApp({super.key});

  @override
  State<GameBoostApp> createState() => _GameBoostState();
}

class _GameBoostState extends State<GameBoostApp> implements GameBoostController {
  final AppState app = AppState();
  bool _watching = false;
  bool _scanning = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(initAsync());
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Boost',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F111A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF181B28),
          elevation: 0,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Game Boost', style: TextStyle(fontWeight: FontWeight.bold))),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    switch (app.screen) {
      case 'edit':
        return EditView(app: app, controller: this);
      case 'settings':
        return SettingsView(app: app, controller: this);
      default:
        return HomeView(app: app, controller: this);
    }
  }

  // ------------------------------------------------------- initial loading
  Future<void> initAsync() async {
    _loaded = true;
    final saved = await loadJson();
    final gamesValue = saved['games'];
    if (gamesValue is List) {
      for (final entry in gamesValue) {
        if (entry is! Map) continue;
        app.games.add(GameProfile.fromJson(entry as Map<String, Object?>));
      }
    }
    final settingsValue = saved['settings'];
    if (settingsValue is Map) {
      app.settings = Settings.fromJson(settingsValue as Map<String, Object?>);
    }
    if (app.games.isEmpty) {
      // Default: Pre-configure Battlegrounds Mobile India (BGMI) with MAX POWER (5)
      app.games.add(GameProfile(
        name: 'Battlegrounds Mobile India (BGMI)',
        patterns: [
          'pubg.imobile',
          'com.pubg.imobile',
          'bgmi',
          'battlegrounds',
          'shadowtracker',
          'tencent.ig',
        ],
        priority: 5, // MAX POWER (niceness -20, real-time I/O, OOM killer protection)
        autoBoost: true,
        pauseBackground: true,
        memoryClean: true,
        aggressiveClean: true,
        maxFps: true, // disable battery-saver + game-mode PERFORMANCE
        maxHz: true, // pin display to peak Hz (90 low-end / 120 normal)
        bgmiTurbo: true, // standby-bucket ACTIVE + dexopt speed for BGMI,
      ));
      unawaited(saveData());
    }
    app.loadedFromDisk = true;
    setState(() {});
    unawaited(doScan());
    unawaited(_ensureWatcher());
  }

  Future<void> saveData() async {
    final payload = <String, Object?>{
      'games': app.games.map((g) => g.toJson()).toList(),
      'settings': app.settings.toJson(),
    };
    await saveJson(payload);
  }

  // ------------------------------------------------------------------ scan
  @override
  void requestScan() {
    unawaited(doScan());
  }

  Future<void> doScan() async {
    if (_scanning) return;
    _scanning = true;
    app.scanning = true;
    setState(() {});
    app.processes = await scanProcesses();
    app.memory = await readMemory();
    app.scanCount++;
    _scanning = false;
    app.scanning = false;
    _refreshCandidates();
    setState(() {});
  }

  void _refreshCandidates() {
    final seen = <String>{};
    app.candidates = <ProcessSummary>[];
    for (final proc in app.processes) {
      if (seen.contains(proc.name)) continue;
      if (_isKnownProcess(proc)) continue; // already tracked / system
      seen.add(proc.name);
      app.candidates.add(proc);
      if (app.candidates.length >= 60) break;
    }
    // Fallback: If no processes were readable, suggest popular games from KNOWN_GAMES
    if (app.candidates.isEmpty) {
      for (final known in KNOWN_GAMES) {
        if (_findGame(known.name) != null) continue;
        app.candidates.add(ProcessSummary(0, known.name, known.patterns.first, 0));
        if (app.candidates.length >= 15) break;
      }
    }
  }

  bool _isKnownProcess(ProcessSummary proc) {
    for (final game in app.games) {
      if (profileMatches(game, proc)) return true;
    }
    if (proc.name == 'game_boost' || proc.pid <= 2) return true;
    return false;
  }

  // ------------------------------------------------------ auto-boost watch
  Future<void> _ensureWatcher() async {
    if (_watching) return;
    _watching = true;
    _watchLoop();
  }

  void _watchLoop() {
    final interval = Duration(seconds: app.settings.scanIntervalSec);
    // The timer is discarded on purpose: each tick schedules the next one,
    // so the loop keeps running until the app shuts down.
    Timer(interval, () {
      unawaited(_watchTick());
    });
  }

  int _slowTicks = 0; // consecutive slow scans (self-throttle counter)
  int _tickCount = 0; // every 2nd tick re-applies RAM clean on low-end

  Future<void> _watchTick() async {
    if (!app.settings.masterAutoBoost) {
      _watchLoop();
      return;
    }
    final stopwatch = Stopwatch()..start();
    final snapshot = await scanProcesses();
    // Keep the memory bar honest on every tick (cheap: one file read).
    try {
      app.memory = await readMemory();
    } catch (_) {}
    _tickCount++;
    var changed = false;
    var anyBoosting = false;
    for (final game in app.games) {
      if (!game.autoBoost) continue;
      final runningNow = _anyMatch(game, snapshot);
      final wasRunning = app.running[game.name] ?? false;
      if (runningNow && !wasRunning) {
        app.running[game.name] = true;
        changed = true;
        unawaited(_boostAsync(game));
      } else if (!runningNow && wasRunning) {
        app.running[game.name] = false;
        changed = true;
        unawaited(_releaseAsync());
      } else if (runningNow && wasRunning) {
        anyBoosting = true;
        // LOW-END: game still open -> re-apply the cheap RAM clean every
        // other tick so free RAM stays high during long BGMI sessions.
        // (renice/governor/fps/hz are sticky; sync+drop_caches are not.)
        if (app.settings.lowEndMode && _tickCount.isEven) {
          unawaited(_reboostAsync(game));
        }
      }
    }
    // Self-throttle: slow scans mean a weak CPU -> back the interval off
    // (max 15s) so the booster itself never lags the game.
    stopwatch.stop();
    if (stopwatch.elapsedMilliseconds > 1500) {
      _slowTicks++;
      if (_slowTicks >= 2 && app.settings.scanIntervalSec < 15) {
        app.settings.scanIntervalSec++;
        _slowTicks = 0;
        unawaited(saveData());
      }
    } else if (_slowTicks > 0) {
      _slowTicks--;
    }
    if (changed || anyBoosting) setState(() {});
    _watchLoop();
  }

  bool _anyMatch(GameProfile game, List<ProcessSummary> snapshot) {
    for (final proc in snapshot) {
      if (profileMatches(game, proc)) return true;
    }
    return false;
  }

  // ------------------------------------------------------------------ boost
  @override
  void boostNow(String gameName) {
    final game = _findGame(gameName);
    if (game == null) return;
    app.running[game.name] = true;
    unawaited(_boostAsync(game));
  }

  /// One-tap BGMI MAX: finds (or creates) the BGMI profile, forces POWER 5 +
  /// MAX-FPS + MAX-HZ + BGMI-TURBO on, then boosts immediately.
  @override
  void boostBgmiMax() {
    var bgmi = _findBgmi();
    if (bgmi == null) {
      bgmi = GameProfile(
        name: 'Battlegrounds Mobile India (BGMI)',
        patterns: [
          'pubg.imobile',
          'com.pubg.imobile',
          'bgmi',
          'battlegrounds',
          'shadowtracker',
          'tencent.ig',
        ],
        priority: 5,
        autoBoost: true,
        pauseBackground: true,
        memoryClean: true,
        aggressiveClean: true,
        maxFps: true,
        maxHz: true,
        bgmiTurbo: true,
      );
      app.games.add(bgmi);
    } else {
      bgmi.priority = 5;
      bgmi.autoBoost = true;
      bgmi.pauseBackground = true;
      bgmi.memoryClean = true;
      bgmi.aggressiveClean = true;
      bgmi.maxFps = true;
      bgmi.maxHz = true;
      bgmi.bgmiTurbo = true;
    }
    unawaited(saveData());
    app.running[bgmi.name] = true;
    unawaited(_boostAsync(bgmi));
  }

  GameProfile? _findBgmi() {
    for (final g in app.games) {
      final n = g.name.toLowerCase();
      if (n.contains('bgmi') || n.contains('battlegrounds')) return g;
    }
    return null;
  }

  Future<void> _boostAsync(GameProfile game) async {
    final report = await applyBoost(app, game);
    app.status = report.message;
    final hints = app.permissionHints;
    if (hints > 0) {
      app.status += ' (${hints} action(s) blocked by the OS - see README)';
    }
    unawaited(saveData());
    setState(() {});
  }

  /// Cheap keep-alive while a game session continues: flush writes +
  /// drop kernel caches (the two RAM actions that decay over time).
  /// Silent: only refreshes the memory bar + status line when it frees RAM.
  Future<void> _reboostAsync(GameProfile game) async {
    if (!game.memoryClean && !game.aggressiveClean) return;
    var freed = false;
    if (game.memoryClean) {
      freed = await runCommand(SYNC_ARGS) || freed;
    }
    if (game.aggressiveClean || game.priority == 5) {
      freed = await runCommand(dropCachesArgs()) || freed;
    }
    try {
      app.memory = await readMemory();
    } catch (_) {}
    if (freed) {
      app.status = '${game.name}: RAM refreshed - free ${formatKb(app.memory.freeKb)}';
      setState(() {});
    }
  }

  @override
  void maxBoostNow(String gameName) {
    var game = _findGame(gameName);
    game ??= app.games.isNotEmpty ? app.games.first : null;
    if (game == null) {
      toast('Add BGMI first, then tap MAX BOOST.');
      return;
    }
    // One tap = everything to MAX: POWER 5 + FPS + HZ + BGMI turbo.
    game.priority = 5;
    game.autoBoost = true;
    game.pauseBackground = true;
    game.memoryClean = true;
    game.aggressiveClean = true;
    game.maxFps = true;
    game.maxHz = true;
    game.bgmiTurbo = true;
    app.running[game.name] = true;
    unawaited(saveData());
    unawaited(_boostAsync(game));
  }

  @override
  void toggleMaxFps(String gameName) {
    final game = _findGame(gameName);
    if (game == null) return;
    game.maxFps = !game.maxFps;
    unawaited(saveData());
    if (game.maxFps) {
      app.running[game.name] = true;
      unawaited(_boostAsync(game));
    } else {
      toast('${game.name}: MAX-FPS OFF.');
    }
  }

  @override
  void toggleMaxHz(String gameName) {
    final game = _findGame(gameName);
    if (game == null) return;
    game.maxHz = !game.maxHz;
    unawaited(saveData());
    if (game.maxHz) {
      app.running[game.name] = true;
      unawaited(_boostAsync(game));
    } else {
      unawaited(_releaseAsync());
      toast('${game.name}: display back to 60Hz.');
    }
  }

  @override
  void toggleBgmiTurbo(String gameName) {
    final game = _findGame(gameName);
    if (game == null) return;
    game.bgmiTurbo = !game.bgmiTurbo;
    unawaited(saveData());
    if (game.bgmiTurbo) {
      app.running[game.name] = true;
      unawaited(_boostAsync(game));
    } else {
      toast('${game.name}: BGMI-TURBO OFF.');
    }
  }

  @override
  void cycleFpsTarget(String gameName) {
    final game = _findGame(gameName);
    if (game == null) return;
    const steps = [0, 60, 90, 120];
    final idx = steps.indexOf(game.fpsTarget);
    game.fpsTarget = steps[(idx + 1) % steps.length];
    game.maxFps = true;
    // A steady 60fps still benefits from the panel pinned at its peak (60Hz
    // panels stay at 60, 90Hz panels drop to 90, etc.). Only turn MAX-HZ off
    // when the user explicitly chooses AUTO (fpsTarget == 0).
    game.maxHz = game.fpsTarget > 0;
    unawaited(saveData());
    app.running[game.name] = true;
    unawaited(_boostAsync(game));
    toast('${game.name}: FPS target ${game.fpsTarget == 0 ? "AUTO" : "${game.fpsTarget} FPS"} - panel ${game.maxHz ? "pinned" : "default 60"}');
  }

  @override
  void toggleLowEndMode() {
    app.settings.lowEndMode = !app.settings.lowEndMode;
    unawaited(saveData());
    setState(() {});
  }

  @override
  void toggleUltraLowEnd() {
    app.settings.ultraLowEnd = !app.settings.ultraLowEnd;
    unawaited(saveData());
    setState(() {});
  }

  @override
  void releaseAll() {
    for (final name in app.running.keys.toList()) {
      app.running[name] = false;
    }
    unawaited(_releaseAsync());
  }

  Future<void> _releaseAsync() async {
    final report = await releaseBoost(app);
    if (report.resumed > 0) app.status = report.message;
    unawaited(saveData());
    setState(() {});
  }

  // -------------------------------------------------------------- toggles
  @override
  void toggleMasterBoost() {
    app.settings.masterAutoBoost = !app.settings.masterAutoBoost;
    if (app.settings.masterAutoBoost) {
      unawaited(_ensureWatcher());
    }
    unawaited(saveData());
    setState(() {});
  }

  // ------------------------------------------------------------- navigation
  @override
  void openHome() {
    app.screen = 'home';
    app.editingName = null;
    setState(() {});
  }

  @override
  void openEdit(String gameName) {
    app.editingName = gameName.isEmpty ? null : gameName;
    app.screen = 'edit';
    setState(() {});
  }

  @override
  void openSettings() {
    app.screen = 'settings';
    setState(() {});
  }

  @override
  void refresh() => setState(() {});

  @override
  void toast(String message) {
    app.status = message;
    setState(() {});
  }

  // --------------------------------------------------------------- discovery
  @override
  void addDetected(ProcessSummary proc) {
    if (_findGame(proc.name) != null) {
      toast('Already added: ${proc.name}');
      return;
    }
    var patterns = [proc.name];
    for (final known in KNOWN_GAMES) {
      if (known.name.toLowerCase() == proc.name.toLowerCase() ||
          known.patterns.any((p) => proc.cmdline.toLowerCase().contains(p))) {
        patterns = List.of(known.patterns);
        break;
      }
    }
    app.games.add(GameProfile(
      name: proc.name,
      patterns: patterns,
      priority: 4,
      autoBoost: true,
      detected: true,
    ));
    unawaited(saveData());
    toast('✅ Added ${proc.name} to My Games!');
    setState(() {});
  }

  @override
  void addKnownGame(String name) {
    if (_findGame(name) != null) {
      toast('Already in your list: $name');
      return;
    }
    for (final known in KNOWN_GAMES) {
      if (known.name != name) continue;
      app.games.add(GameProfile(
        name: known.name,
        patterns: List.of(known.patterns),
        priority: 4,
        autoBoost: true,
      ));
      unawaited(saveData());
      toast('✅ Added ${known.name} to My Games!');
      setState(() {});
      return;
    }
  }

  // -------------------------------------------------------------- profile I/O
  @override
  void saveProfile(GameProfile profile, {bool remove = false}) {
    if (remove) {
      final existing = _findGame(profile.name);
      if (existing != null) {
        app.games.remove(existing);
        app.running.remove(profile.name);
      }
      toast('Removed ${profile.name}.');
    } else {
      final existingIndex = _indexOf(profile.name);
      if (existingIndex >= 0) {
        app.games[existingIndex] = profile;
        toast('Saved ${profile.name}.');
      } else {
        app.games.add(profile);
        toast('Added ${profile.name}.');
      }
    }
    unawaited(saveData());
    app.screen = 'home';
    app.editingName = null;
    setState(() {});
  }

  // -------------------------------------------------------------- settings
  @override
  void changeScanInterval(int delta) {
    var next = app.settings.scanIntervalSec + delta;
    if (next < 2) next = 2;
    if (next > 15) next = 15;
    app.settings.scanIntervalSec = next;
    unawaited(saveData());
    setState(() {});
  }

  @override
  void togglePauseTarget(ProcessSummary proc) {
    final list = List.of(app.settings.pauseList);
    final name = proc.name;
    if (list.contains(name)) {
      list.remove(name);
      toast('Will no longer pause $name.');
    } else {
      list.add(name);
      toast('$name will be paused during boosted games.');
    }
    app.settings.pauseList = list;
    unawaited(saveData());
    setState(() {});
  }

  @override
  void resetAllData() {
    app.games = <GameProfile>[];
    app.running = <String, bool>{};
    app.settings = Settings();
    app.pausedPids = <int>[];
    app.status = 'Data reset to defaults.';
    unawaited(saveData());
    setState(() {});
  }

  // ------------------------------------------------------------------ utils
  GameProfile? _findGame(String name) {
    for (final game in app.games) {
      if (game.name == name) return game;
    }
    return null;
  }

  int _indexOf(String name) {
    for (var i = 0; i < app.games.length; i++) {
      if (app.games[i].name == name) return i;
    }
    return -1;
  }
}