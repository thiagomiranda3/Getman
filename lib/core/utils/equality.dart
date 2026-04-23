import 'package:collection/collection.dart';

/// Shared `MapEquality<String, String>` instance used by widgets that compare
/// header/param maps in `buildWhen` / `listenWhen`. Instantiating one per file
/// is pointless allocation — the type has no state.
const MapEquality<String, String> headerMapEquality = MapEquality<String, String>();
