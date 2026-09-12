// Game Boost - settings screen: master switch, scan interval, per-process
// pause list, whitelist and data management.

import 'package:flutter/material.dart';

import '../controller.dart';
import '../models.dart';
import 'widgets.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.app, required this.controller});

  final AppState app;
  final GameBoostController controller;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: sectionTitle('AUTO-BOOST MASTER')),
          toggleSwitch('MASTER', app.settings.masterAutoBoost,
              controller.toggleMasterBoost),
        ],
      ),
      label('While ON, running games with “AUTO-BOOST” enabled are '
          'boosted automatically, and released when they close.'),
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('LOW-END PHONE MODE')),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: label('Budget phone: cap display pin at 90Hz, '
              'lighter scans, stronger RAM clean.')),
          toggleSwitch('LOW-END', app.settings.lowEndMode,
              controller.toggleLowEndMode),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: label('ULTRA (<3GB RAM / 60Hz screen): skip Hz '
              'lock, max RAM guard. Enable this on very weak phones.')),
          toggleSwitch('ULTRA', app.settings.ultraLowEnd,
              controller.toggleUltraLowEnd),
        ],
      ),
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('SCAN EVERY')),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child:
              Text('${app.settings.scanIntervalSec} seconds',
                  style: TextStyle(fontSize: 14, color: Colors.grey[200]))),
          miniButton('−', () => controller.changeScanInterval(-1)),
          miniButton('＋', () => controller.changeScanInterval(1)),
        ],
      ),
      _pauseSection(),
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('WHITELIST (never touched)')),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(app.settings.killWhitelist.join(', ')),
          label('These processes are protected from pausing/killing even if '
              'they match the lists above.'),
        ],
      ),
      Padding(padding: const EdgeInsets.only(top: 16),
          child: sectionTitle('DATA')),
      actionButton('RESET ALL DATA', controller.resetAllData),
      actionButton('BACK', controller.openHome),
      Padding(padding: const EdgeInsets.only(top: 8), child:
          label('Tip: if Android blocks priority/kill actions, check the '
              'README section “Permissions”.')),
    ];
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: children),
    );
  }

  Widget _pauseSection() {
    final rows = <Widget>[
      Padding(padding: const EdgeInsets.only(top: 12),
          child: sectionTitle('PAUSE THESE APPS DURING GAMES')),
      label('Paused apps are resumed automatically when you stop boosting.'),
    ];
    final uniques = <String>[];
    for (final proc in app.processes) {
      if (!uniques.contains(proc.name)) uniques.add(proc.name);
      if (uniques.length >= 24) break;
    }
    if (uniques.isEmpty) {
      rows.add(label('(run SCAN from home first)'));
    }
    for (final name in uniques) {
      if (app.settings.killWhitelist.contains(name)) continue;
      final on = app.settings.pauseList.contains(name);
      final proc = ProcessSummary(0, name, '', 0);
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(name,
                style: TextStyle(fontSize: 12, color: Colors.grey[300]))),
            miniButton(on ? 'PAUSE' : 'RESUME',
                () => controller.togglePauseTarget(proc)),
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