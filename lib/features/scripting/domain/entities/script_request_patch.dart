// Immutable ScriptRequestPatch value exchanged by script execution components.
import 'package:equatable/equatable.dart';

const _unchanged = Object();

class ScriptRequestPatch extends Equatable {
  ScriptRequestPatch({
    this.url,
    this.method,
    this.body,
    Map<String, String> headerSets = const {},
    Set<String> headerUnsets = const {},
  }) : headerSets = Map.unmodifiable(headerSets),
       headerUnsets = Set.unmodifiable(headerUnsets);
  final String? url;
  final String? method;
  final String? body;
  final Map<String, String> headerSets;
  final Set<String> headerUnsets;
  bool get isEmpty =>
      url == null &&
      method == null &&
      body == null &&
      headerSets.isEmpty &&
      headerUnsets.isEmpty;

  ScriptRequestPatch copyWith({
    Object? url = _unchanged,
    Object? method = _unchanged,
    Object? body = _unchanged,
    Map<String, String>? headerSets,
    Set<String>? headerUnsets,
  }) => ScriptRequestPatch(
    url: identical(url, _unchanged) ? this.url : url as String?,
    method: identical(method, _unchanged) ? this.method : method as String?,
    body: identical(body, _unchanged) ? this.body : body as String?,
    headerSets: headerSets ?? this.headerSets,
    headerUnsets: headerUnsets ?? this.headerUnsets,
  );
  @override
  List<Object?> get props => [url, method, body, headerSets, headerUnsets];
}
