import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/updates/domain/entities/release_info.dart';

void main() {
  test('ReleaseInfo value equality', () {
    const a = ReleaseInfo(version: '1.1.0', changelog: 'notes', assetUrl: 'u');
    const b = ReleaseInfo(version: '1.1.0', changelog: 'notes', assetUrl: 'u');
    const c = ReleaseInfo(version: '1.2.0', changelog: 'notes', assetUrl: 'u');
    expect(a, equals(b));
    expect(a, isNot(equals(c)));
  });
}
