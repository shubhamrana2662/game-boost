// Game Boost - tiny self-contained JSON encoder/decoder plus persistence.
//
// The app intentionally has zero pub.dev dependencies, so we ship a small,
// well-tested JSON implementation instead of pulling in a package.

import 'dart:io';

const String _DATA_FILE = 'game_boost_data.json';

/// ---------------------------------------------------------------- encode ---
String jsonEncode(Object? value) {
  final buffer = StringBuffer();
  _writeValue(buffer, value);
  return buffer.toString();
}

void _writeValue(StringBuffer out, Object? value) {
  if (value == null) {
    out.write('null');
  } else if (value is bool) {
    out.write(value ? 'true' : 'false');
  } else if (value is int) {
    out.write(value.toString());
  } else if (value is double) {
    out.write(value == value.truncate() ? '${value.truncate()}.0' : value.toString());
  } else if (value is String) {
    _writeString(out, value);
  } else if (value is List) {
    out.write('[');
    var first = true;
    for (final item in value) {
      if (!first) out.write(',');
      first = false;
      _writeValue(out, item);
    }
    out.write(']');
  } else if (value is Map) {
    out.write('{');
    var first = true;
    for (final entry in value.entries) {
      if (!first) out.write(',');
      first = false;
      _writeString(out, entry.key.toString());
      out.write(':');
      _writeValue(out, entry.value);
    }
    out.write('}');
  } else {
    _writeString(out, value.toString());
  }
}

void _writeString(StringBuffer out, String s) {
  out.write('"');
  for (var i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    switch (code) {
      case 0x22:
        out.write(r'\u0022');
        break;
      case 0x5C:
        out.write(r'\u005C');
        break;
      case 0x08:
        out.write(r'\b');
        break;
      case 0x0C:
        out.write(r'\f');
        break;
      case 0x0A:
        out.write(r'\n');
        break;
      case 0x0D:
        out.write(r'\r');
        break;
      case 0x09:
        out.write(r'\t');
        break;
      default:
        if (code < 0x20) {
          out.write(r'\u' + code.toRadixString(16).padLeft(4, '0'));
        } else {
          out.writeCharCode(code);
        }
    }
  }
  out.write('"');
}

/// ---------------------------------------------------------------- decode ---
/// Parses [text] into a JSON tree of Map<String, Object?>/List/Object?.
/// Returns null on malformed input.
Object? jsonDecode(String text) {
  final p = _JsonParser(text);
  final value = p.parseValue();
  p.skipWhitespace();
  if (!p.isAtEnd) return null;
  if (identical(value, _missing)) return null;
  return value;
}

/// Sentinel used internally to indicate missing/invalid tokens.
final Object _missing = Object();

class _JsonParser {
  _JsonParser(this._text);

  final String _text;
  int _pos = 0;

  bool get isAtEnd => _pos >= _text.length;

  void skipWhitespace() {
    while (!isAtEnd) {
      final c = _text.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
        _pos++;
      } else {
        break;
      }
    }
  }

  Object? parseValue() {
    skipWhitespace();
    if (isAtEnd) return _missing;
    final ch = _text.codeUnitAt(_pos);
    if (ch == 0x7B) return _parseObject(); // '{'
    if (ch == 0x5B) return _parseArray();  // '['
    if (ch == 0x22) return _parseString(); // '"'
    if (ch == 0x74) return _parseLiteral('true', true);   // 't'
    if (ch == 0x66) return _parseLiteral('false', false);  // 'f'
    if (ch == 0x6E) return _parseLiteral('null', null);    // 'n'
    return _parseNumber();
  }

  Map<String, Object?> _parseObject() {
    _pos++; // '{'
    final out = <String, Object?>{};
    skipWhitespace();
    if (!isAtEnd && _text.codeUnitAt(_pos) == 0x7D) {
      _pos++;
      return out;
    }
    while (!isAtEnd) {
      skipWhitespace();
      final keyValue = _parseString();
      if (identical(keyValue, _missing)) return out;
      final key = keyValue as String;
      skipWhitespace();
      if (!isAtEnd && _text.codeUnitAt(_pos) == 0x3A) {
        _pos++;
      } else {
        break;
      }
      final value = parseValue();
      if (identical(value, _missing)) break;
      out[key] = value;
      skipWhitespace();
      if (isAtEnd) break;
      final c = _text.codeUnitAt(_pos);
      _pos++;
      if (c == 0x7D) break; // '}'
      if (c != 0x2C) break; // ','
    }
    return out;
  }

  List<Object?> _parseArray() {
    _pos++; // '['
    final out = <Object?>[];
    skipWhitespace();
    if (!isAtEnd && _text.codeUnitAt(_pos) == 0x5D) {
      _pos++;
      return out;
    }
    while (!isAtEnd) {
      final value = parseValue();
      if (identical(value, _missing)) break;
      out.add(value);
      skipWhitespace();
      if (isAtEnd) break;
      final c = _text.codeUnitAt(_pos);
      _pos++;
      if (c == 0x5D) break; // ']'
      if (c != 0x2C) break; // ','
    }
    return out;
  }

  Object? _parseString() {
    _pos++; // '"'
    final buffer = StringBuffer();
    var closed = false;
    while (!isAtEnd) {
      final c = _text.codeUnitAt(_pos);
      _pos++;
      if (c == 0x22) { // '"'
        closed = true;
        break;
      }
      if (c != 0x5C) { // not '\'
        buffer.writeCharCode(c);
        continue;
      }
      if (isAtEnd) break;
      final esc = _text.codeUnitAt(_pos);
      _pos++;
      switch (esc) {
        case 0x22: // "
        case 0x5C: // \
        case 0x2F: // /
          buffer.writeCharCode(esc);
          break;
        case 0x62: // b
          buffer.write('\b');
          break;
        case 0x66: // f
          buffer.write('\f');
          break;
        case 0x6E: // n
          buffer.write('\n');
          break;
        case 0x72: // r
          buffer.write('\r');
          break;
        case 0x74: // t
          buffer.write('\t');
          break;
        case 0x75: // u
          if (_pos + 4 > _text.length) break;
          final hex = _text.substring(_pos, _pos + 4);
          _pos += 4;
          final code = int.parse(hex, radix: 16);
          buffer.writeCharCode(code);
          break;
        default:
          buffer.writeCharCode(esc);
      }
    }
    return closed ? buffer.toString() : _missing;
  }

  Object? _parseNumber() {
    final start = _pos;
    while (!isAtEnd) {
      final c = _text.codeUnitAt(_pos);
      if (c == 0x2D || c == 0x2B || c == 0x2E || c == 0x65 || c == 0x45 ||
          (c >= 0x30 && c <= 0x39)) {
        _pos++;
      } else {
        break;
      }
    }
    final token = _text.substring(start, _pos);
    if (token.isEmpty) return _missing;
    final asDouble = double.tryParse(token);
    if (asDouble == null) return _missing;
    if (!token.contains('.') && !token.contains('e') && !token.contains('E')) {
      return asDouble.truncate();
    }
    return asDouble;
  }

  Object? _parseLiteral(String word, Object? value) {
    if (_text.length - _pos < word.length) return _missing;
    if (_text.substring(_pos, _pos + word.length) != word) return _missing;
    _pos += word.length;
    return value;
  }
}

/// ------------------------------------------------------------ persistence ---
Future<Map<String, Object?>> loadJson() async {
  try {
    final file = File(_DATA_FILE);
    if (!await file.exists()) return {};
    final text = await file.readAsString();
    final root = jsonDecode(text);
    if (root is! Map) return {};
    return root as Map<String, Object?>;
  } catch (e) {
    return {};
  }
}

Future<void> saveJson(Map<String, Object?> root) async {
  try {
    final file = File(_DATA_FILE);
    await file.writeAsString(jsonEncode(root));
  } catch (e) {
    // Disk writes can be restricted; the in-memory state still works.
  }
}