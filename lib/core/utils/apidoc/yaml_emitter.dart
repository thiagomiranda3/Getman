/// Minimal block-style YAML serializer for a JSON-like tree (maps, lists,
/// strings, nums, bools, null). Enough for OpenAPI output — not a general YAML
/// library. Zero dependencies.
class YamlEmitter {
  YamlEmitter._();

  static String emit(Object? value) {
    final buf = StringBuffer();
    _emit(value, 0, buf);
    return buf.toString();
  }

  static void _emit(Object? value, int indent, StringBuffer buf) {
    if (value is Map) {
      if (value.isEmpty) {
        buf.writeln('{}');
        return;
      }
      value.forEach((key, dynamic v) {
        final pad = ' ' * indent;
        if (v is Map && v.isNotEmpty) {
          buf
            ..write(pad)
            ..write(_key(key))
            ..writeln(':');
          _emit(v, indent + 2, buf);
        } else if (v is List && v.isNotEmpty) {
          buf
            ..write(pad)
            ..write(_key(key))
            ..writeln(':');
          _emitList(v, indent + 2, buf);
        } else if (v is Map && v.isEmpty) {
          buf
            ..write(pad)
            ..write(_key(key))
            ..writeln(': {}');
        } else if (v is List && v.isEmpty) {
          buf
            ..write(pad)
            ..write(_key(key))
            ..writeln(': []');
        } else {
          buf
            ..write(pad)
            ..write(_key(key))
            ..write(': ')
            ..writeln(_scalar(v));
        }
      });
      return;
    }
    if (value is List) {
      if (value.isEmpty) {
        buf.writeln('[]');
        return;
      }
      _emitList(value, indent, buf);
      return;
    }
    buf.writeln(_scalar(value));
  }

  static void _emitList(List<dynamic> list, int indent, StringBuffer buf) {
    final pad = ' ' * indent;
    for (final item in list) {
      if (item is Map && item.isNotEmpty) {
        // First key on the dash line, remaining keys indented to align.
        final entries = item.entries.toList();
        final firstEntry = entries.first;
        buf
          ..write(pad)
          ..write('- ');
        final dynamic fv = firstEntry.value;
        if (fv is Map && fv.isNotEmpty) {
          buf
            ..write(_key(firstEntry.key))
            ..writeln(':');
          _emit(fv, indent + 4, buf);
        } else if (fv is List && fv.isNotEmpty) {
          buf
            ..write(_key(firstEntry.key))
            ..writeln(':');
          _emitList(fv, indent + 4, buf);
        } else if (fv is Map && fv.isEmpty) {
          buf
            ..write(_key(firstEntry.key))
            ..writeln(': {}');
        } else if (fv is List && fv.isEmpty) {
          buf
            ..write(_key(firstEntry.key))
            ..writeln(': []');
        } else {
          buf
            ..write(_key(firstEntry.key))
            ..write(': ')
            ..writeln(_scalar(fv));
        }
        for (final entry in entries.skip(1)) {
          final subPad = ' ' * (indent + 2);
          final dynamic v = entry.value;
          if (v is Map && v.isNotEmpty) {
            buf
              ..write(subPad)
              ..write(_key(entry.key))
              ..writeln(':');
            _emit(v, indent + 4, buf);
          } else if (v is List && v.isNotEmpty) {
            buf
              ..write(subPad)
              ..write(_key(entry.key))
              ..writeln(':');
            _emitList(v, indent + 4, buf);
          } else if (v is Map && v.isEmpty) {
            buf
              ..write(subPad)
              ..write(_key(entry.key))
              ..writeln(': {}');
          } else if (v is List && v.isEmpty) {
            buf
              ..write(subPad)
              ..write(_key(entry.key))
              ..writeln(': []');
          } else {
            buf
              ..write(subPad)
              ..write(_key(entry.key))
              ..write(': ')
              ..writeln(_scalar(v));
          }
        }
      } else if (item is List && item.isNotEmpty) {
        buf
          ..write(pad)
          ..writeln('-');
        _emitList(item, indent + 2, buf);
      } else if (item is Map && item.isEmpty) {
        buf
          ..write(pad)
          ..writeln('- {}');
      } else if (item is List && item.isEmpty) {
        buf
          ..write(pad)
          ..writeln('- []');
      } else {
        buf
          ..write(pad)
          ..write('- ')
          ..writeln(_scalar(item));
      }
    }
  }

  static String _scalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    return _scalarString(value.toString());
  }

  /// Runs a map key through the same quoting logic as a scalar value — an
  /// unquoted key like `weird: key` or `#lead` would either break the
  /// `key: value` grammar or vanish as a comment.
  static String _key(Object? key) => _scalarString(key.toString());

  static String _scalarString(String s) {
    if (!_needsQuote(s)) return s;
    final escaped = s
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  /// Quote only when leaving the scalar bare would change its meaning: empty,
  /// padded, contains control characters, structurally ambiguous (`: ` /
  /// trailing `:` / ` #`), starting with a YAML indicator char, or parseable
  /// as a bool/null/number. A URL (`https://x` — colon without a following
  /// space) and a dotted version (`1.0.0` — not a valid number) stay bare.
  static bool _needsQuote(String s) {
    if (s.isEmpty || s != s.trim()) return true;
    if (s.contains(RegExp(r'[\x00-\x1f]'))) return true;
    if (s.contains(': ') || s.endsWith(':') || s.contains(' #')) return true;
    if (_indicators.contains(s[0])) return true;
    final lower = s.toLowerCase();
    if (const {'true', 'false', 'null', 'yes', 'no', '~'}.contains(lower)) {
      return true;
    }
    return num.tryParse(s) != null;
  }

  static const _indicators = {
    '{',
    '}',
    '[',
    ']',
    ',',
    '&',
    '*',
    '!',
    '|',
    '>',
    "'",
    '"',
    '%',
    '@',
    '`',
    '#',
    '?',
    '-',
    ':',
  };
}
