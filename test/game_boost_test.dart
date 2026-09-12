// Game Boost - unit tests for the pure logic (no /proc, no flutter:services).
//
// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';

import 'package:game_boost/src/boost.dart';
import 'package:game_boost/src/models.dart';
import 'package:game_boost/src/proc.dart';
import 'package:game_boost/src/store.dart';

void main() {
  test('processNameFromCmdline extracts argv0 basename', () {
    expect(processNameFromCmdline(
            '/opt/games/MLBB/game\u0000--fast\u0000--low\u0000'),
        equals('game'));
    expect(processNameFromCmdline('python3'), equals('python3'));
    expect(processNameFromCmdline(''), equals('unknown'));
    expect(processNameFromCmdline('   '), equals('unknown'));
  });

  test('processNameFromCmdline strips executable suffixes', () {
    expect(processNameFromCmdline('/opt/Games/Hunter.exe'), equals('hunter'));
    expect(processNameFromCmdline('/usr/bin/app.app'), equals('app'));
  });

  test('patternMatches is case-insensitive on name and cmdline', () {
    final proc = ProcessSummary(
        42, 'genshinimpact', '/opt/GenshinImpact/game --no-sandbox', 0);
    expect(patternMatches('Genshin', proc), isTrue);
    expect(patternMatches('genshin', proc), isTrue);
    expect(patternMatches('no-sandbox', proc), isTrue);
    expect(patternMatches('pubg', proc), isFalse);
    expect(patternMatches('', proc), isFalse);
  });

  test('profileMatches uses all patterns', () {
    final game = GameProfile(name: 'Test', patterns: ['alpha', 'beta']);
    final a = ProcessSummary(1, 'something', '', 0);
    final b = ProcessSummary(2, 'BETA', '', 0);
    final c = ProcessSummary(3, 'gamma', '', 0);
    expect(profileMatches(game, a), isTrue);
    expect(profileMatches(game, b), isTrue);
    expect(profileMatches(game, c), isFalse);
  });

  test('priorityToNice maps 1..5 to -20..0', () {
    expect(priorityToNice(1), equals(0));
    expect(priorityToNice(2), equals(-5));
    expect(priorityToNice(3), equals(-10));
    expect(priorityToNice(4), equals(-15));
    expect(priorityToNice(5), equals(-20));
  });

  test('command builders produce the expected argv', () {
    expect(reniceArgs(123, -10).join(' '), equals('renice -n -10 -p 123'));
    expect(ioniceArgs(42, 1).join(' '), equals('ionice -c 1 -p 42'));
    expect(signalArgs(7, '-STOP').join(' '), equals('kill -STOP 7'));
    expect(killArgs(9).join(' '), equals('kill -9 9'));
    expect(SYNC_ARGS.join(' '), equals('sync'));
    expect(lowerPriorityArgs(99).join(' '), equals('renice -n 19 -p 99'));
  });

  test('oom and governor builders produce shell commands', () {
    final oom = oomProtectArgs(42);
    expect(oom.first, equals('sh'));
    expect(oom.last.contains('oom_score_adj'), isTrue);
    final gov = cpuGovernorArgs('performance');
    expect(gov.first, equals('sh'));
    expect(gov.last.contains('performance'), isTrue);
    final drop = dropCachesArgs();
    expect(drop.first, equals('sh'));
    expect(drop.last.contains('drop_caches'), isTrue);
  });

  test('jsonEncode/jsonDecode round-trips complex data', () {
    final input = <String, Object?>{
      'name': 'Test "Game"',
      'num': 42,
      'pi': 3.5,
      'ok': true,
      'nothing': null,
      'tags': ['a', 'b', 'ünïcode'],
      'nested': {'deep': [1, 2, {'x': 'y'}]},
    };
    final encoded = jsonEncode(input);
    final decoded = jsonDecode(encoded);
    expect(decoded, isNotNull);
    final decodedMap = decoded as Map<String, Object?>;
    expect(decodedMap['name'], equals('Test "Game"'));
    expect(decodedMap['num'], equals(42));
    expect(decodedMap['pi'], equals(3.5));
    expect(decodedMap['ok'], equals(true));
    expect(decodedMap['nothing'], isNull);
    final tags = decodedMap['tags'] as List;
    expect(tags.length, equals(3));
    expect(tags[2], equals('ünïcode'));
    final nested = decodedMap['nested'] as Map<String, Object?>;
    final deep = nested['deep'] as List;
    expect(deep.length, equals(3));
    expect(encoded.startsWith('{'), isTrue);
  });

  test('jsonDecode returns null for malformed input', () {
    expect(jsonDecode('{"a": }'), isNull);
    expect(jsonDecode(''), isNull);
    expect(jsonDecode('{"a":1,}'), isNull); // trailing comma
    expect(jsonDecode('{"a": "unterminated'), isNull);
  });

  test('GameProfile toJson/fromJson round-trips every field', () {
    final profile = GameProfile(
      name: 'Genshin Impact',
      patterns: ['genshin'],
      priority: 5,
      autoBoost: true,
      pauseBackground: true,
      memoryClean: false,
      extraKill: ['gallery'],
      detected: true,
      timesBoosted: 3,
    );
    final restored = GameProfile.fromJson(profile.toJson());
    expect(restored.name, equals(profile.name));
    expect(restored.patterns.join(','), equals('genshin'));
    expect(restored.priority, equals(5));
    expect(restored.autoBoost, isTrue);
    expect(restored.pauseBackground, isTrue);
    expect(restored.memoryClean, isFalse);
    expect(restored.extraKill.join(','), equals('gallery'));
    expect(restored.detected, isTrue);
    expect(restored.timesBoosted, equals(3));
  });

  test('GameProfile clamps priority into 1..5', () {
    expect(GameProfile(name: 'A', priority: 0).priority, equals(1));
    expect(GameProfile(name: 'B', priority: 9).priority, equals(5));
    expect(GameProfile(name: 'C', priority: 3).priority, equals(3));
  });

  test('formatKb renders human friendly units', () {
    expect(formatKb(0), equals('0 B'));
    expect(formatKb(1), equals('1.0 KB'));
    expect(formatKb(1024 * 1024), equals('1.0 GB'));
  });

  test('memoryBar renders within bounds', () {
    expect(memoryBar(MemoryStats(1000, 1000)).length, equals(18));
    expect(memoryBar(MemoryStats(0, 0)).length, equals(18));
  });
}