import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/git_service.dart';

void main() {
  group('GitException.isMissingIdentity', () {
    test('matches the classic "Please tell me who you are" failure', () {
      expect(
        GitException.isMissingIdentity('''
*** Please tell me who you are.

Run

  git config --global user.email "you@example.com"
  git config --global user.name "Your Name"

fatal: unable to auto-detect email address (got 'user@host.(none)')
'''),
        isTrue,
      );
    });

    test('matches "Author identity unknown"', () {
      expect(
        GitException.isMissingIdentity(
          'fatal: unable to auto-detect email address (got '
          "'user@host.(none)')\n\n*** Please tell me who you are.",
        ),
        isTrue,
      );
      expect(
        GitException.isMissingIdentity(
          'Author identity unknown\n\n*** empty ident name',
        ),
        isTrue,
      );
    });

    test('matches "unable to auto-detect email" on its own', () {
      expect(
        GitException.isMissingIdentity(
          "fatal: unable to auto-detect email address (got 'a@b.(none)')",
        ),
        isTrue,
      );
    });

    test('is case-insensitive', () {
      expect(
        GitException.isMissingIdentity('PLEASE TELL ME WHO YOU ARE.'),
        isTrue,
      );
    });

    test('does not match an unrelated git failure', () {
      expect(
        GitException.isMissingIdentity('fatal: not a git repository'),
        isFalse,
      );
      expect(
        GitException.isMissingIdentity(
          'CONFLICT (content): Merge conflict in a.json',
        ),
        isFalse,
      );
    });
  });
}
