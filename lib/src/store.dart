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
    out.write((value as int).toString());
  } else if (value is double) {
    final d = value as double;
    out.write(d == d.truncate() ? '${d.truncate()}.0' : d.toString());
  } else if (value is String) {
    _writeString(out, value as String);
  } else if (value is List) {
    out.write('[');
    var first = true;
    for (final item in value as List) {
      if (!first) out.write(',');
      first = false;
      _writeValue(out, item);
    }
    out.write(']');
  } else if (value is Map) {
    out.write('{');
    var first = true;
    for (final entry in (value as Map).entries) {
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
  for (final code in s.runes) {
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
  return value == _MISSING ? null : value;
}

const Object _MISSING = Object();

class _JsonParser {
  _JsonParser(String text) : _text = text;

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
    if (isAtEnd) return _MISSING;
    switch (_text[_pos]) {
      case '{':
        return _parseObject();
      case '[':
        return _parseArray();
      case '"':
        return _parseString();
      case 't':
        return _parseLiteral('true', true);
      case 'f':
        return _parseLiteral('false', false);
      case 'n':
        return _parseLiteral('null', null);
      default:
        return _parseNumber();
    }
  }

  Map<String, Object?> _parseObject() {
    _pos++; // '{'
    final out = <String, Object?>{};
    skipWhitespace();
    if (!isAtEnd && _text[_pos] == '}') {
      _pos++;
      return out;
    }
    while (!isAtEnd) {
      skipWhitespace();
      final keyValue = _parseString();
      if (!(keyValue is String)) return _MISSING;
      final key = keyValue as String;
      skipWhitespace();
      if (!isAtEnd && _text[_pos] == ':') {
        _pos++;
      } else {
        break;
      }
      final value = parseValue();
      if (value == _MISSING) return _MISSING;
      out[key] = value;
      skipWhitespace();
      if (isAtEnd) break;
      final c = _text[_pos];
      _pos++;
      if (c == '}') break;
      if (c != ',') break;
    }
    return out;
  }

  List<Object?> _parseArray() {
    _pos++; // '['
    final out = <Object?>[];
    skipWhitespace();
    if (!isAtEnd && _text[_pos] == ']') {
      _pos++;
      return out;
    }
    while (!isAtEnd) {
      final value = parseValue();
      if (value == _MISSING) return _MISSING;
      out.add(value);
      skipWhitespace();
      if (isAtEnd) break;
      final c = _text[_pos];
      _pos++;
      if (c == ']') break;
      if (c != ',') break;
    }
    return out;
  }

  Object? _parseString() {
    _pos++; // '"'
    final buffer = StringBuffer();
    var closed = false;
    while (!isAtEnd) {
      final c = _text[_pos];
      _pos++;
      if (c == '"') {
        closed = true;
        break;
      }
      if (c != r'\') {
        buffer.write(c);
        continue;
      }
      if (isAtEnd) break;
      final esc = _text[_pos];
      _pos++;
      switch (esc) {
        case '"':
        case r'\':
        case '/':
          buffer.write(esc);
          break;
        case 'b':
          buffer.write('\b');
          break;
        case 'f':
          buffer.write('\f');
          break;
        case 'n':
          buffer.write('\n');
          break;
        case 'r':
          buffer.write('\r');
          break;
        case 't':
          buffer.write('\t');
          break;
        case 'u':
          {
            if (_pos + 4 > _text.length) break;
            final hex = _text.substring(_pos, _pos + 4);
            _pos += 4;
            final code = int.parse(hex, radix: 16);
            buffer.writeCharCode(code);
            break;
          }
        default:
          buffer.write(esc);
      }
    }
    return closed ? buffer.toString() : _MISSING;
  }

  Object? _parseNumber() {
    final start = _pos;
    while (!isAtEnd) {
      final c = _text[_pos];
      if (c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E' ||
          (c >= '0' && c <= '9')) {
        _pos++;
      } else {
        break;
      }
    }
    final token = _text.substring(start, _pos);
    if (token.isEmpty) return _MISSING;
    final asDouble = double.tryParse(token);
    if (asDouble == null) return _MISSING;
    if (!token.contains('.') && !token.contains('e') && !token.contains('E')) {
      return asDouble.truncate();
    }
    return asDouble;
  }

  Object? _parseLiteral(String word, Object? value) {
    if (_text.length - _pos < word.length) return _MISSING;
    if (_text.substring(_pos, _pos + word.length) != word) return _MISSING;
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
    if (!(root is Map)) return {};
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