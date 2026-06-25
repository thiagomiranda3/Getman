import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/network/mcp_service.dart';
import 'package:getman/features/mcp/presentation/bloc/mcp_bloc.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('getman_di_mcp_test');
  });

  tearDown(() async {
    await di.reset();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('McpService and McpBloc are registered after init', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await di.init(storageDirectoryOverride: tempDir.path);
    expect(di.sl.isRegistered<McpService>(), isTrue);
    expect(di.sl<McpBloc>(), isA<McpBloc>());
  });
}
