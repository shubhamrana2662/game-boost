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
    if (app.editingName != null && app.editingName!.isNotEmpty) {
      for (final g in app.games) {
        if (g.name == app.editingName) {
          existing = g;
          break;
        }
      }
    }
    final profile = existing == null
        ? GameProfile(name: '', priority: 4,
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

  late final TextEditingController _nameController;
  late final TextEditingController _patternController;

  GameBoostController get controller => widget.controller;
  AppState get app => widget.app;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: isEdit ? draft.name : '');
    _patternController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = app.running[draft.name] ?? false;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          isEdit ? 'Edit Game Profile' : 'Add New Game',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      TextField(
        controller: _nameController,
        decoration: InputDecoration(
          labelText: 'Game Name',
          hintText: 'e.g. Free Fire, BGMI, PUBG, Genshin',
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.videogame_asset),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
        ),
        onChanged: (v) {
          draft.name = v.trim();
        },
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: label('BOOST POWER: ${draft.priority} ($prio)')),
          miniButton('−', () => setState(() {
            if (draft.priority > 1) draft.priority--;
          })),
          const SizedBox(width: 8),
          miniButton('＋', () => setState(() {
            if (draft.priority < 5) draft.priority++;
          })),
        ],
      ),
      const SizedBox(height: 8),
      toggleSwitch('AUTO-BOOST when game launches', draft.autoBoost, () {
        setState(() { draft.autoBoost = !draft.autoBoost; });
      }),
      const SizedBox(height: 6),
      toggleSwitch('PAUSE background apps', draft.pauseBackground, () {
        setState(() { draft.pauseBackground = !draft.pauseBackground; });
      }),
      const SizedBox(height: 6),
      toggleSwitch('MEMORY CLEAN & cache drop on start', draft.memoryClean, () {
        setState(() { draft.memoryClean = !draft.memoryClean; });
      }),
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: sectionTitle('PROCESS / PACKAGE PATTERNS'),
      ),
      label('Matches running game executable or Android package name.'),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _patternController,
              decoration: InputDecoration(
                labelText: 'Add pattern keyword',
                hintText: 'e.g. freefire, pubg, codm',
                border: const OutlineInputBorder(),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
              ),
              onSubmitted: (_) => _addPattern(),
            ),
          ),
          const SizedBox(width: 8),
          actionButton('＋ ADD', _addPattern),
        ],
      ),
      const SizedBox(height: 8),
      if (draft.patterns.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: label('(auto-matches game name if empty)'),
        )
      else
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: draft.patterns.map((p) => Chip(
            label: Text(p),
            deleteIcon: const Icon(Icons.close, size: 16),
            onDeleted: () {
              setState(() {
                draft.patterns.remove(p);
              });
            },
          )).toList(),
        ),
      if (app.processes.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: sectionTitle('QUICK PICK FROM RUNNING APPS'),
        ),
        _pickerRows(draft.patterns, true),
      ],
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: actionButton(isEdit ? 'SAVE CHANGES' : 'ADD GAME', () {
              final name = _nameController.text.trim();
              if (name.isEmpty) {
                controller.toast('Please enter a game name');
                return;
              }
              draft.name = name;
              if (draft.patterns.isEmpty) {
                draft.patterns.add(name.toLowerCase().replaceAll(RegExp(r'\s+'), ''));
              }
              controller.saveProfile(draft);
            }),
          ),
          if (isEdit) ...[
            const SizedBox(width: 8),
            actionButton('REMOVE', () => controller.saveProfile(draft, remove: true)),
          ],
          const SizedBox(width: 8),
          actionButton('CANCEL', controller.openHome),
        ],
      ),
      const SizedBox(height: 16),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  void _addPattern() {
    final text = _patternController.text.trim().toLowerCase();
    if (text.isNotEmpty && !draft.patterns.contains(text)) {
      setState(() {
        draft.patterns.add(text);
        _patternController.clear();
      });
    }
  }

  String get prio => priorityLabel(draft.priority);

  Widget _pickerRows(List<String> target, bool isPattern) {
    final uniques = <String>[];
    for (final proc in app.processes) {
      if (!uniques.contains(proc.name)) uniques.add(proc.name);
      if (uniques.length >= 20) break;
    }
    if (uniques.isEmpty) return const SizedBox.shrink();
    final rows = <Widget>[];
    if (isPattern && uniques.contains(draft.name)) {
      uniques.remove(draft.name);
    }
    for (final name in uniques) {
      final on = target.contains(name);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: Colors.grey[300]))),
            miniButton(on ? 'ADDED' : '＋ ADD', () {
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}