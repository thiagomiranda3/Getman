import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_output_parser.dart';

void main() {
  test('parsePrList maps fields and rolls up passing checks', () {
    const json = '''
    [
      {"number":123,"title":"feat: x","state":"OPEN",
       "url":"https://github.com/o/r/pull/123","isDraft":false,
       "statusCheckRollup":[
         {"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"},
         {"__typename":"StatusContext","state":"SUCCESS"}]}
    ]''';
    final prs = parsePrList(json);
    expect(prs.single.number, 123);
    expect(prs.single.title, 'feat: x');
    expect(prs.single.state, 'OPEN');
    expect(prs.single.url, endsWith('/pull/123'));
    expect(prs.single.isDraft, isFalse);
    expect(prs.single.checks, 'passing');
  });

  test('rollupChecks: empty rollup is none', () {
    expect(rollupChecks(const <Object?>[]), 'none');
    expect(rollupChecks(null), 'none');
  });

  test('rollupChecks: an unfinished check is pending', () {
    final rollup = [
      {'__typename': 'CheckRun', 'status': 'IN_PROGRESS'},
      {
        '__typename': 'CheckRun',
        'status': 'COMPLETED',
        'conclusion': 'SUCCESS',
      },
    ];
    expect(rollupChecks(rollup), 'pending');
  });

  test('rollupChecks: pending wins over failing in the same rollup', () {
    // Guards the spec's headline precedence: an unfinished check alongside a
    // completed failure must report `pending`, not `failing`.
    final rollup = [
      {'__typename': 'CheckRun', 'status': 'IN_PROGRESS'},
      {
        '__typename': 'CheckRun',
        'status': 'COMPLETED',
        'conclusion': 'FAILURE',
      },
    ];
    expect(rollupChecks(rollup), 'pending');
  });

  test('rollupChecks: a completed failure (all finished) is failing', () {
    final rollup = [
      {
        '__typename': 'CheckRun',
        'status': 'COMPLETED',
        'conclusion': 'FAILURE',
      },
      {'__typename': 'StatusContext', 'state': 'SUCCESS'},
    ];
    expect(rollupChecks(rollup), 'failing');
  });

  test('rollupChecks: draft PR still parses', () {
    const json = '''
    [{"number":9,"title":"wip","state":"OPEN","url":"u","isDraft":true,
      "statusCheckRollup":[]}]''';
    expect(parsePrList(json).single.isDraft, isTrue);
    expect(parsePrList(json).single.checks, 'none');
  });

  test('parsePrList tolerates wrong-typed fields instead of throwing', () {
    // A malformed entry (number as string, isDraft as int) must degrade to
    // defaults, not abort the whole parse with a CastError.
    const json = '''
    [{"number":"oops","title":42,"state":null,"url":true,"isDraft":1,
      "statusCheckRollup":null}]''';
    final pr = parsePrList(json).single;
    expect(pr.number, 0);
    expect(pr.title, '');
    expect(pr.state, 'OPEN');
    expect(pr.url, '');
    expect(pr.isDraft, isFalse);
    expect(pr.checks, 'none');
  });

  test('parsePrList degrades a non-list to empty', () {
    expect(parsePrList('{"not":"a list"}'), isEmpty);
  });

  test('parsePrUrl returns the last url when gh prints more than one', () {
    // gh may echo a remote/branch URL before the created PR URL; the PR URL is
    // last. Guards the `match.last` selection against a `.first` regression.
    const out =
        'https://github.com/o/r/tree/my-branch\n'
        'https://github.com/o/r/pull/456\n';
    expect(parsePrUrl(out), 'https://github.com/o/r/pull/456');
  });

  test('parsePrUrl returns empty when no url is present', () {
    expect(parsePrUrl('nothing here'), '');
  });
}
