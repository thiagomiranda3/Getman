import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/utils/path_utils.dart';

void main() {
  group('PathUtils.basename', () {
    test('returns the final segment for posix and windows paths', () {
      expect(PathUtils.basename('/home/user/report.pdf'), 'report.pdf');
      expect(PathUtils.basename(r'C:\Users\me\photo.png'), 'photo.png');
      expect(PathUtils.basename('file.txt'), 'file.txt');
    });

    test('trims trailing separators instead of returning empty', () {
      expect(PathUtils.basename('/home/user/'), 'user');
      expect(PathUtils.basename(r'C:\Users\me\\'), 'me');
    });

    test('handles empty and root paths', () {
      expect(PathUtils.basename(''), '');
      expect(PathUtils.basename('/'), '');
    });
  });
}
