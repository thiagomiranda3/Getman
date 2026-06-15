import 'package:equatable/equatable.dart';

/// One cookie parsed from a `Set-Cookie` response header.
class ParsedCookie extends Equatable {
  const ParsedCookie({
    required this.name,
    required this.value,
    this.attributes = '',
  });
  final String name;
  final String value;

  /// Remaining attributes joined back with `; ` (Path, HttpOnly, Expires, …).
  final String attributes;

  @override
  List<Object?> get props => [name, value, attributes];
}

/// Parses a `Set-Cookie` header into individual cookies.
///
/// Multiple cookies arrive joined with `', '` (the network layer joins
/// multi-valued headers that way). Splitting naively on `, ` would break on
/// the comma inside an `Expires=Wed, 21 Oct ...` date, so we only split on a
/// comma that is followed by a `token=` — the start of the next cookie.
/// Best-effort: see CLAUDE.md notes on the lossy header join.
class CookieParser {
  CookieParser._();

  // Split before `, name=` but not before `, 21 Oct ...` (no `=` follows).
  static final RegExp _between = RegExp(r',(?=\s*[^=;,\s]+=)');

  static List<ParsedCookie> parse(String? header) {
    if (header == null || header.trim().isEmpty) return const [];
    final result = <ParsedCookie>[];
    for (final chunk in header.split(_between)) {
      final trimmed = chunk.trim();
      if (trimmed.isEmpty) continue;
      final parts = trimmed.split(';');
      final first = parts.first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue; // no name=value pair
      final name = first.substring(0, eq).trim();
      final value = first.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      final attributes = parts
          .skip(1)
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .join('; ');
      result.add(
        ParsedCookie(name: name, value: value, attributes: attributes),
      );
    }
    return result;
  }
}
