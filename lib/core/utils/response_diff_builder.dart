import 'package:equatable/equatable.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/domain/persistence_limits.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/core/utils/line_diff.dart';

/// One differing response header. [left]/[right] are the values on each side;
/// `null` means the header is absent on that side.
class HeaderDelta extends Equatable {
  const HeaderDelta({
    required this.key,
    required this.left,
    required this.right,
  });

  final String key;
  final String? left;
  final String? right;

  bool get isAdded => left == null && right != null;
  bool get isRemoved => left != null && right == null;
  bool get isChanged => left != null && right != null && left != right;

  @override
  List<Object?> get props => [key, left, right];
}

/// A fully-rendered, render-agnostic diff of two responses. The widget layer
/// only paints this — prettify + the large-body guard already ran here.
class ResponseDiffModel extends Equatable {
  const ResponseDiffModel({
    required this.leftStatus,
    required this.rightStatus,
    required this.bodyLines,
    required this.headerDeltas,
    required this.bodiesIdentical,
    required this.tooLarge,
  });

  final int leftStatus;
  final int rightStatus;

  /// Unified line diff of the pretty-printed bodies. Empty when [tooLarge].
  final List<DiffLine> bodyLines;

  /// Only the header keys that differ (added / removed / changed).
  final List<HeaderDelta> headerDeltas;

  /// True when no add/remove lines exist (bodies render identically).
  final bool bodiesIdentical;

  /// True when a body exceeded [kLargeResponseViewerChars]; no prettify/LCS ran.
  final bool tooLarge;

  @override
  List<Object?> get props => [
    leftStatus,
    rightStatus,
    bodyLines,
    headerDeltas,
    bodiesIdentical,
    tooLarge,
  ];
}

/// Maps two [HttpResponseEntity] into a [ResponseDiffModel]. `left` is the
/// current tab's response, `right` the chosen target. Async because it awaits
/// [JsonUtils.prettify] (which may hop an isolate).
class ResponseDiffBuilder {
  const ResponseDiffBuilder._();

  static Future<ResponseDiffModel> build(
    HttpResponseEntity left,
    HttpResponseEntity right,
  ) async {
    final headerDeltas = _headerDeltas(left.headers, right.headers);

    // Large guard: never prettify / diff multi-MB strings on the UI isolate.
    if (left.body.length > kLargeResponseViewerChars ||
        right.body.length > kLargeResponseViewerChars) {
      return ResponseDiffModel(
        leftStatus: left.statusCode,
        rightStatus: right.statusCode,
        bodyLines: const [],
        headerDeltas: headerDeltas,
        bodiesIdentical: false,
        tooLarge: true,
      );
    }

    final prettyLeft = await JsonUtils.prettify(left.body);
    final prettyRight = await JsonUtils.prettify(right.body);
    final lines = LineDiff.diffText(prettyLeft, prettyRight);
    final identical = lines.every((l) => l.kind == DiffLineKind.equal);

    return ResponseDiffModel(
      leftStatus: left.statusCode,
      rightStatus: right.statusCode,
      bodyLines: lines,
      headerDeltas: headerDeltas,
      bodiesIdentical: identical,
      tooLarge: false,
    );
  }

  /// Header names are case-insensitive (HTTP). Compare via lowercased keys;
  /// surface the left's original casing, falling back to the right's.
  static List<HeaderDelta> _headerDeltas(
    Map<String, String> left,
    Map<String, String> right,
  ) {
    final leftByLower = {for (final e in left.entries) e.key.toLowerCase(): e};
    final rightByLower = {
      for (final e in right.entries) e.key.toLowerCase(): e,
    };
    final keys = <String>{...leftByLower.keys, ...rightByLower.keys};

    final deltas = <HeaderDelta>[];
    for (final lower in keys) {
      final l = leftByLower[lower];
      final r = rightByLower[lower];
      if (l != null && r != null && l.value == r.value) continue; // unchanged
      deltas.add(
        HeaderDelta(
          key: l?.key ?? r!.key,
          left: l?.value,
          right: r?.value,
        ),
      );
    }
    deltas.sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    return deltas;
  }
}

/// Reconstructs an [HttpResponseEntity] from a config that carries response
/// columns (a saved example or a history entry). Returns null when no response
/// was captured (`statusCode == null`). Pure + testable so the widget does no
/// reconstruction inline.
HttpResponseEntity? responseFromConfig(HttpRequestConfigEntity config) {
  final status = config.statusCode;
  if (status == null) return null;
  return HttpResponseEntity(
    statusCode: status,
    body: config.responseBody ?? '',
    headers: config.responseHeaders ?? const {},
    durationMs: config.durationMs ?? 0,
  );
}
