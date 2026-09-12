// Game Boost - controller interface shared by the views.
//
// Views never touch system APIs; they only talk to this controller and the
// AppState model it exposes.

import 'models.dart';
import 'proc.dart';

abstract class GameBoostController {
  AppState get app;

  /// Rebuild the whole UI from the current AppState.
  void refresh();

  // --- navigation ---
  void openHome();
  void openEdit(String gameName);
  void openSettings();

  // --- core actions ---
  void requestScan();
  void toggleMasterBoost();
  void boostNow(String gameName);
  void releaseAll();

  // --- profile editing ---
  void saveProfile(GameProfile profile, {bool remove = false});

  // --- discovery ---
  void addDetected(ProcessSummary proc);
  void addKnownGame(String name);

  // --- settings ---
  void changeScanInterval(int delta);
  void togglePauseTarget(ProcessSummary proc);
  void resetAllData();

  /// Show a transient status message.
  void toast(String message);
}