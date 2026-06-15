import 'package:collection/collection.dart';

/// Shared `MapEquality<String, String>` instance used wherever header /
/// query-param / environment-variable maps are compared (`buildWhen`,
/// `listenWhen`, editor echo-suppression). Instantiating one per file is
/// pointless allocation — the type has no state.
const MapEquality<String, String> stringMapEquality =
    MapEquality<String, String>();
