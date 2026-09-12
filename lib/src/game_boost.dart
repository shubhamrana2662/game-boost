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

  Future<void> _watchTick() async {
    if (!app.settings.masterAutoBoost) return;
    final snapshot = await scanProcesses();
    var changed = false;
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
        if (app.pausedPids.isNotEmpty) {
          unawaited(_releaseAsync());
        }
      }
    }
    if (changed) setState(() {});
    if (_watching && !_scanning) _watchLoop();
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