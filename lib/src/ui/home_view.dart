// Game Boost - home screen: status, quick actions, my games, detected apps
// and the built-in game library.

import 'package:flutter/material.dart';

import '../controller.dart';
import '../game_library.dart';
import '../models.dart';
import '../proc.dart';
import 'widgets.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key, required this.app, required this.controller});

  final AppState app;
  final GameBoostController controller;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      _actionRow(),
      _statusCard(),
      _gamesSection(),
      _detectedSection(),
      _librarySection(),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: label('Game Boost v1.0 · open source · see README for permission notes.'),
      ),
    ];
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _actionRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        actionButton('SCAN NOW', controller.requestScan),
        actionButton('SETTINGS', controller.openSettings),
        actionButton('RELEASE', controller.releaseAll),
      ],
    );
  }

  Widget _statusCard() {
    final hint = app.scanCount == 0
        ? 'No scan yet - tap SCAN NOW.'
        : 'Last scan #${app.scanCount} · ${app.processes.length} processes';
    final lines = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text('TURBO AUTO-BOOST',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                  color: Colors.indigo[300]))),
          toggleSwitch('MASTER', app.settings.masterAutoBoost,
              controller.toggleMasterBoost),
        ],
      ),
      Padding(padding: const EdgeInsets.only(top: 8), child:
          Text('RAM  ${formatKb(app.memory.freeKb)} free  /  ${formatKb(app.memory.totalKb)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]))),
      Text(memoryBar(app.memory),
          style: TextStyle(fontSize: 13, fontFamily: '_monospace')),
      label(hint),
      Padding(padding: const EdgeInsets.only(top: 8), child:
          Text(app.status,
              style: TextStyle(fontSize: 13,
                  color: app.status.contains('blocked')
                      ? Colors.orange[500]
                      : Colors.grey[600]))),
    ];
    return card(children: lines);
  }

  Widget _gamesSection() {
    final children = <Widget>[
      Padding(padding: const EdgeInsets.only(top: 16),
          child: sectionTitle('MY GAMES (${app.games.length})')),
    ];
    if (app.games.isEmpty) {
      children.add(label('Nothing yet. SCAN, tap a detected app below, '
          'or add one from the library.'));
    }
    for (final game in app.games) {
      children.add(_gameCard(game));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _gameCard(GameProfile game) {
    final running = app.running[game.name] ?? false;
    final prio = priorityLabel(game.priority);
    return card(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(game.name,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                  color: running ? Colors.orange[500] : Colors.white))),
          tag(running ? '● BOOSTING' : 'idle', highlight: running),
        ],
      ),
      label('POWER $prio · ${game.patternsSummary()}'),
      if (game.detected) label('detected on this device'),
      Padding(padding: const EdgeInsets.only(top: 8), child:
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            miniButton('EDIT', () => controller.openEdit(game.name)),
            miniButton('BOOST', () => controller.boostNow(game.name)),
            miniButton('REMOVE', () => controller.saveProfile(game, remove: true)),
          ])),
    ]);
  }

  Widget _detectedSection() {
    final children = <Widget>[
      Padding(padding: const EdgeInsets.only(top: 16),
          child: sectionTitle('DETECTED APPS - tap + to add')),
    ];
    if (app.candidates.isEmpty) {
      children.add(label('Nothing detected yet. Tap SCAN NOW.'));
    }
    var shown = 0;
    for (final proc in app.candidates) {
      if (shown >= 20) break;
      shown++;
      children.add(_candidateRow(proc));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _candidateRow(ProcessSummary proc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(proc.name,
              style: TextStyle(fontSize: 13, color: Colors.grey[200]))),
          miniButton('＋', () => controller.addDetected(proc)),
        ],
      ),
    );
  }

  Widget _librarySection() {
    final children = <Widget>[
      Padding(padding: const EdgeInsets.only(top: 16),
          child: sectionTitle('GAME LIBRARY - tap + to add')),
    ];
    for (final known in KNOWN_GAMES) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(known.name,
                style: TextStyle(fontSize: 13, color: Colors.grey[400]))),
            miniButton('＋', () => controller.addKnownGame(known.name)),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}