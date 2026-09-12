// Game Boost - entry point.
//
// The Flutter tool builds/installs this package by resolving `lib/main.dart`
// and calling `main()` (the "static main" convention).
//
// Building an APK for Android:
//   flutter pub get
//   flutter test
//   flutter build apk --release
//
// Installing on a connected phone:
//   flutter run
//   (or "flutter install" / "flutter build apk" then side-load the .apk)

import 'package:flutter/material.dart';

import 'src/game_boost.dart';

void main() => runApp(const GameBoostApp());