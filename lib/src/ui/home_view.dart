// Game Boost - home screen: status, quick actions, my games, detected apps
// and searchable built-in game library.

import 'package:flutter/material.dart';

import '../controller.dart';
import '../game_library.dart';
import '../models.dart';
import '../proc.dart';
import 'widgets.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.app, required this.controller});

  final AppState app;
  final GameBoostController controller;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String _searchQuery = '';

  AppState get app => widget.app;
  GameBoostController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _actionRow(),
      const SizedBox(height: 8),
      _statusCard(),
      const SizedBox(height: 8),
      _gamesSection(),
      const SizedBox(height: 8),
      _detectedSection(),
      const SizedBox(height: 8),
      _librarySection(),
      const SizedBox(height: 16),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: label('Game Boost v1.0 · Turbo Boost & Auto-Release'),
        ),
      ),
      const SizedBox(height: 24),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _actionRow() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.radar, size: 18),
              label: Text(app.scanning ? 'SCANNING...' : 'SCAN'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E3856),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: app.scanning ? null : controller.requestScan,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle, size: 18),
              label: const Text('ADD GAME'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => controller.openEdit(''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('SETTINGS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25293A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: controller.openSettings,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final hint = app.scanCount == 0
        ? 'Tap SCAN to look for games running on your device'
        : 'Scan #${app.scanCount} · ${app.processes.length} apps/processes detected';
    final lines = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(Icons.bolt, color: Colors.amber, size: 22),
                const SizedBox(width: 6),
                Text(
                  'TURBO AUTO-BOOST',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo[200],
                  ),
                ),
              ],
            ),
          ),
          toggleSwitch('MASTER', app.settings.masterAutoBoost,
              controller.toggleMasterBoost),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'RAM: ${formatKb(app.memory.freeKb)} free / ${formatKb(app.memory.totalKb)}',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
          ),
          if (app.running.values.any((v) => v))
            const Text(
              '⚡ ACTIVE',
              style: TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(memoryBar(app.memory),
          style: const TextStyle(fontSize: 13, fontFamily: '_monospace')),
      const SizedBox(height: 4),
      label(hint),
      if (app.status.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: app.status.contains('✅')
                  ? Colors.green.withOpacity(0.15)
                  : Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: app.status.contains('✅')
                    ? Colors.green.withOpacity(0.3)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.amber),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    app.status,
                    style: TextStyle(
                      fontSize: 12,
                      color: app.status.contains('blocked')
                          ? Colors.orange[400]
                          : Colors.grey[200],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
    return card(children: lines);
  }

  Widget _gamesSection() {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            sectionTitle('MY GAMES (${app.games.length})'),
            miniButton('＋ ADD GAME', () => controller.openEdit('')),
          ],
        ),
      ),
    ];
    if (app.games.isEmpty) {
      children.add(
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF191D2C),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            children: [
              const Icon(Icons.sports_esports, size: 36, color: Colors.indigoAccent),
              const SizedBox(height: 8),
              const Text(
                'No games in your list yet',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 4),
              label('Add custom game or choose from popular titles below:'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  actionButton('＋ ADD CUSTOM GAME', () => controller.openEdit('')),
                  actionButton('SCAN APPS', controller.requestScan),
                ],
              ),
            ],
          ),
        ),
      );
    }
    for (final game in app.games) {
      children.add(_gameCard(game));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _gameCard(GameProfile game) {
    final running = app.running[game.name] ?? false;
    final prio = priorityLabel(game.priority);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: running ? const Color(0xFF261D12) : const Color(0xFF191D2C),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: running ? Colors.orangeAccent : Colors.white10,
            width: running ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        Icons.sports_esports,
                        color: running ? Colors.orangeAccent : Colors.indigoAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          game.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: running ? Colors.orangeAccent : Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                tag(running ? '● BOOSTING' : 'idle', highlight: running),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'POWER $prio (${game.priority})',
                    style: const TextStyle(fontSize: 11, color: Colors.indigoAccent, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    game.patternsSummary(),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                miniButton('EDIT', () => controller.openEdit(game.name)),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: running ? Colors.orange[800] : Colors.green[700],
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () => controller.boostNow(game.name),
                  child: Text(running ? 'RE-BOOST' : 'BOOST NOW'),
                ),
                const SizedBox(width: 8),
                miniButton('REMOVE', () => controller.saveProfile(game, remove: true)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detectedSection() {
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: sectionTitle('DETECTED ON DEVICE - tap ＋ to add'),
      ),
    ];
    if (app.candidates.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: label('Scanning... tap SCAN NOW above or select from library below.'),
        ),
      );
    }
    var shown = 0;
    for (final proc in app.candidates) {
      if (shown >= 15) break;
      shown++;
      children.add(_candidateRow(proc));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _candidateRow(ProcessSummary proc) {
    final isAdded = app.games.any((g) => g.name.toLowerCase() == proc.name.toLowerCase());
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF161824),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                proc.name,
                style: TextStyle(fontSize: 13, color: isAdded ? Colors.grey[500] : Colors.grey[200]),
              ),
            ),
            if (isAdded)
              const Text('ADDED ✓', style: TextStyle(fontSize: 12, color: Colors.greenAccent))
            else
              miniButton('＋ ADD', () => controller.addDetected(proc)),
          ],
        ),
      ),
    );
  }

  Widget _librarySection() {
    final filteredGames = _searchQuery.isEmpty
        ? KNOWN_GAMES
        : KNOWN_GAMES.where((k) =>
            k.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            k.patterns.any((p) => p.toLowerCase().contains(_searchQuery.toLowerCase()))).toList();

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: sectionTitle('GAME LIBRARY (${KNOWN_GAMES.length} popular titles)'),
      ),
      label('Search any popular game and tap ＋ ADD to add it to your booster list:'),
      const SizedBox(height: 8),
      TextField(
        decoration: InputDecoration(
          hintText: 'Search games (e.g. Free Fire, BGMI, PUBG, Genshin)...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() => _searchQuery = ''),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: const Color(0xFF161824),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
      ),
      const SizedBox(height: 8),
    ];

    var count = 0;
    for (final known in filteredGames) {
      if (_searchQuery.isEmpty && count >= 20) break;
      count++;
      final isAdded = app.games.any((g) => g.name.toLowerCase() == known.name.toLowerCase());
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF161824),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  known.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: isAdded ? Colors.grey[500] : Colors.grey[300],
                    fontWeight: isAdded ? FontWeight.normal : FontWeight.w500,
                  ),
                ),
              ),
              if (isAdded)
                const Text('ADDED ✓', style: TextStyle(fontSize: 12, color: Colors.greenAccent))
              else
                miniButton('＋ ADD', () => controller.addKnownGame(known.name)),
            ],
          ),
        ),
      ));
    }

    if (_searchQuery.isEmpty && KNOWN_GAMES.length > 20) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Center(
            child: label('Type in search box above to find any of 50+ games'),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}