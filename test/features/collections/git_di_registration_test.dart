import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/git/git_service.dart';
import 'package:getman/features/collections/domain/review_service.dart';
import 'package:getman/features/collections/presentation/bloc/review_bloc.dart';

void main() {
  test('git service, review service, and ReviewBloc are registered', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = await Directory.systemTemp.createTemp('getman_di');
    await di.init(storageDirectoryOverride: tmp.path);
    expect(di.sl.isRegistered<GitService>(), isTrue);
    expect(di.sl.isRegistered<ReviewService>(), isTrue);
    expect(di.sl<ReviewBloc>(), isA<ReviewBloc>());
    await tmp.delete(recursive: true);
  });
}
