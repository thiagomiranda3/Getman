import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/network/realtime_service.dart';
import 'package:getman/features/realtime/presentation/bloc/realtime_bloc.dart';

/// Guards the H2 DI reordering: RealtimeService is registered alongside
/// NetworkService (after the cookie store is hydrated), not in the earlier
/// "Features - Tabs/Realtime" block where the cookie store doesn't exist yet.
/// A `sl<RealtimeService>()` call resolving without a "not registered" /
/// null-cookie-store crash is the regression this guards.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_di_realtime_test');
  });

  tearDown(() async {
    await di.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('RealtimeService and RealtimeBloc are registered after init', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await di.init(storageDirectoryOverride: tempDir.path);

    expect(di.sl.isRegistered<RealtimeService>(), isTrue);
    expect(di.sl<RealtimeService>(), isA<RealtimeService>());
    expect(di.sl<RealtimeBloc>(), isA<RealtimeBloc>());
  });
}
