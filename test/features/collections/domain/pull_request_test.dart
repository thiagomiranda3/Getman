import 'package:flutter_test/flutter_test.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';

void main() {
  test('PullRequestEntity equality is by value', () {
    const a = PullRequestEntity(
      number: 1,
      title: 't',
      state: PrState.open,
      url: 'u',
      isDraft: false,
      checks: PrChecks.passing,
    );
    const b = PullRequestEntity(
      number: 1,
      title: 't',
      state: PrState.open,
      url: 'u',
      isDraft: false,
      checks: PrChecks.passing,
    );
    expect(a, b);
  });

  test('PullRequestEntity differs when any field differs', () {
    const base = PullRequestEntity(
      number: 1,
      title: 't',
      state: PrState.open,
      url: 'u',
      isDraft: false,
      checks: PrChecks.passing,
    );
    expect(
      base,
      isNot(
        const PullRequestEntity(
          number: 1,
          title: 't',
          state: PrState.open,
          url: 'u',
          isDraft: false,
          checks: PrChecks.failing,
        ),
      ),
    );
  });

  test('PullRequestRef equality is by value', () {
    expect(
      const PullRequestRef(number: 5, url: 'u'),
      const PullRequestRef(number: 5, url: 'u'),
    );
  });
}
