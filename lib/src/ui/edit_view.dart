// Game Boost - per-game editor: tweak priority, toggles and which processes
// should be matched/paused/killed while the game runs.

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import '../proc.dart';
import 'widgets.dart';

class EditView extends StatefulWidget {
  const EditView({super.key, required this.app, required this.controller});

  final AppState app;
  final GameBoostController controller;

  @override
  State<EditView> createState() {
    GameProfile? existing;
    if (app.editingName != null) {
      for (final g in app.games) {
        if (g.name == app.editingName) {
          existing = g;
          break;
        }
      }
    }
    final profile = existing == null
        ? GameProfile(name: 'New Game', priority: 3,
            autoBoost: true, pauseBackground: true, memoryClean: true)
        : _copy(existing);
    return _EditState(profile, existing != null);
  }

  static GameProfile _copy(GameProfile src) {
    return GameProfile(
      name: src.name,
      patterns: List.of(src.patterns),
      priority: src.priority,
      autoBoost: src.autoBoost,
      pauseBackground: src.pauseBackground,
      memoryClean: src.memoryClean,
      extraKill: List.of(src.extraKill),
      detected: src.detected,
      timesBoosted: src.timesBoosted,
      lastBoostedAt: src.lastBoostedAt,
    );
  }
}

class _EditState extends State<EditView> {
  _EditState(this.draft, this.isEdit);

  final GameProfile draft;
  final bool isEdit;

  GameBoostController get controller => widget.controller;
  AppState get app => widget.app;

  @override
  Widget build(BuildContext context) {
    final running = app.running[draft.name] ?? false;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(draft.name,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                color: running ? Colors.orange[500] : Colors.white)),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: label('POWER  ${draft.priority}  ($prio)')),
          miniButton('−', () => setState(() {
            if (draft.priority > 1) draft.priority--;
          })),
          miniButton('＋', () => setState(() {
            if (draft.priority < 5) draft.priority++;
          })),
        ],
      ),
      SizedBox(height: 8),
      toggleSwitch('AUTO-BOOST while running', draft.autoBoost, () {
        setState(() { draft.autoBoost = !draft.autoBoost; });
      }),
      toggleSwitch('PAUSE background apps', draft.pauseBackground, () {
        setState(() { draft.pauseBackground = !draft.pauseBackground; });
      }),
      toggleSwitch('MEMORY CLEAN on start', draft.memoryClean, () {
        setState(() { draft.memoryClean = !draft.memoryClean; });
      }),
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('MATCH (process names)')),
      label('The game is "running" when any of these match. '
          'Included: ${draft.patternsSummary()}'),
      _pickerRows(draft.patterns, true),
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('EXTRA PROCESSES TO KILL')),
      _pickerRows(draft.extraKill, false),
      SizedBox(height: 8),
      actionButton(isEdit ? 'SAVE CHANGES' : 'ADD GAME',
          () => controller.saveProfile(draft)),
      actionButton('REMOVE GAME', () => controller.saveProfile(draft, remove: true)),
      actionButton('BACK', widget.controller.openHome),
    ];
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }

  String get prio => priorityLabel(draft.priority);

  Widget _pickerRows(List<String> target, bool isPattern) {
    final uniques = <String>[];
    for (final proc in app.processes) {
      if (!uniques.contains(proc.name)) uniques.add(proc.name);
      if (uniques.length >= 24) break;
    }
    if (uniques.isEmpty) return label('(run SCAN from home first)');
    final rows = <Widget>[];
    if (isPattern && uniques.contains(draft.name)) {
      uniques.remove(draft.name); // never match the game against itself
    }
    for (final name in uniques) {
      final on = target.contains(name);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(name,
                style: TextStyle(fontSize: 12, color: Colors.grey[300]))),
            miniButton(on ? 'ON' : 'OFF', () {
              setState(() {
                if (on) {
                  target.remove(name);
                } else {
                  target.add(name);
                }
              });
            }),
          ],
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}