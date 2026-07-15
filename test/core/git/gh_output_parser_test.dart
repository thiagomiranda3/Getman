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
}
