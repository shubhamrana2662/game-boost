// Game Boost - small reusable UI building blocks.

import 'package:flutter/material.dart';

import '../models.dart';

/// Card container used all over the app.
Container card({required List<Widget> children, EdgeInsets? padding}) {
  return Container(
    padding: padding ?? const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

/// Section heading.
Widget sectionTitle(String text) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.indigo[300],
    ),
  );
}

/// Small secondary label.
Widget label(String text) {
  return Text(text, style: TextStyle(fontSize: 13, color: Colors.grey[600]));
}

/// Small pill text for tags.
Widget tag(String text, {bool highlight = false}) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 12,
      color: highlight ? Colors.orange[500] : Colors.blueGrey[400],
    ),
  );
}

/// The app's primary action button.
ElevatedButton actionButton(String label, void Function() onPressed) {
  return ElevatedButton(child: Text(label), onPressed: onPressed);
}

/// Wide "toggle" button showing the current ON/OFF state.
ElevatedButton toggleSwitch(String leading, bool active, void Function() onPressed) {
  return ElevatedButton(
    child: Text('${active ? 'ON  ' : 'OFF '}$leading'),
    onPressed: onPressed,
  );
}

/// Small square control button.
ElevatedButton miniButton(String label, void Function() onPressed) {
  return ElevatedButton(child: Text(label), onPressed: onPressed);
}

/// Simple textual memory bar, e.g. "██████░░░░░░" (18 cells).
String memoryBar(MemoryStats memory) {
  const int width = 18;
  var used = 0;
  if (memory.totalKb > 0) {
    used = (((memory.totalKb - memory.freeKb) * width) ~/ memory.totalKb)
        .clamp(0, width) as int;
  }
  final out = StringBuffer();
  for (var i = 0; i < used; i++) {
    out.writeCharCode(0x2588); // █
  }
  for (var i = used; i < width; i++) {
    out.writeCharCode(0x2591); // ░
  }
  return out.toString();
}
