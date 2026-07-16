import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/git/gh_service.dart';
import 'package:getman/features/collections/data/services/gh_pull_request_service.dart';
import 'package:getman/features/collections/domain/branch_service.dart';
import 'package:getman/features/collections/domain/entities/pull_request.dart';
import 'package:mocktail/mocktail.dart';

class _MockGh extends Mock implements GhService {}

class _MockBranch extends Mock implements BranchService {}

void main() {
  const root = '/ws';
  late _MockGh gh;
  late _MockBranch branch;
  late GhPullRequestService service;

  setUp(() {
    gh = _MockGh();
    branch = _MockBranch();
    service = GhPullRequestService(gh, branch);
  });

  test('availability: notInstalled when gh is absent', () async {
    when(gh.isAvailable).thenAnswer((_) async => false);
    expect(await service.availability(root), GhAvailability.notInstalled);
    verifyNever(() => gh.isAuthenticated(any()));
  });

  test(
    'availability: notAuthenticated when gh present but not logged in',
    () async {
      when(gh.isAvailable).thenAnswer((_) async => true);
      when(() => gh.isAuthenticated(root)).thenAnswer((_) async => false);
      expect(await service.availability(root), GhAvailability.notAuthenticated);
    },
  );

  test('availability: available when installed + authenticated', () async {
    when(gh.isAvailable).thenAnswer((_) async => true);
    when(() => gh.isAuthenticated(root)).thenAnswer((_) async => true);
    expect(await service.availability(root), GhAvailability.available);
  });

  test('list maps gh state + checks strings to domain enums', () async {
    when(() => gh.listPrs(root)).thenAnswer(
      (_) async => const [
        PullRequestInfo(
          number: 12,
          title: 't',
          state: 'OPEN',
          url: 'https://github.com/o/r/pull/12',
          isDraft: true,
          checks: 'failing',
        ),
        PullRequestInfo(
          number: 8,
          title: 'merged one',
          state: 'MERGED',
          url: 'https://github.com/o/r/pull/8',
          isDraft: false,
          checks: 'passing',
        ),
        PullRequestInfo(
          number: 5,
          title: 'closed one',
          state: 'CLOSED',
          url: 'https://github.com/o/r/pull/5',
          isDraft: false,
          checks: 'pending',
        ),
        PullRequestInfo(
          number: 3,
          title: 'no checks',
          state: 'OPEN',
          url: 'https://github.com/o/r/pull/3',
          isDraft: false,
          checks: 'none',
        ),
      ],
    );
    final prs = await service.list(root);
    expect(prs[0].number, 12);
    expect(prs[0].state, PrState.open);
    expect(prs[0].checks, PrChecks.failing);
    expect(prs[0].isDraft, isTrue);
    expect(prs[1].state, PrState.merged);
    expect(prs[1].checks, PrChecks.passing);
    expect(prs[2].state, PrState.closed);
    expect(prs[2].checks, PrChecks.pending);
    expect(prs[3].checks, PrChecks.none);
  });

  test('create pushes BEFORE gh.createPr, and parses the PR number from the '
      'url', () async {
    final pushGate = Completer<void>();
    var pushed = false;
    var createdBeforePush = false;
    when(() => branch.push(root)).thenAnswer((_) async {
      await pushGate.future;
      pushed = true;
    });
    when(
      () => gh.createPr(
        root,
        base: any(named: 'base'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        draft: any(named: 'draft'),
      ),
    ).thenAnswer((_) async {
      if (!pushed) createdBeforePush = true;
      return 'https://github.com/o/r/pull/77';
    });

    final op = service.create(
      root,
      base: 'main',
      title: 't',
      body: 'b',
      draft: false,
    );
    await Future<void>.delayed(Duration.zero);
    // gh.createPr must not have fired yet — push is gated open.
    verifyNever(
      () => gh.createPr(
        root,
        base: any(named: 'base'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        draft: any(named: 'draft'),
      ),
    );
    pushGate.complete();
    final ref = await op;

    expect(
      createdBeforePush,
      isFalse,
      reason: 'push must finish before create',
    );
    expect(ref.number, 77);
    expect(ref.url, endsWith('/pull/77'));
  });

  test(
    'create parses the PR number even when the url carries a query',
    () async {
      when(() => branch.push(root)).thenAnswer((_) async {});
      when(
        () => gh.createPr(
          root,
          base: any(named: 'base'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          draft: any(named: 'draft'),
        ),
      ).thenAnswer((_) async => 'https://github.com/o/r/pull/91?tab=files');
      final ref = await service.create(
        root,
        base: 'main',
        title: 't',
        body: 'b',
        draft: false,
      );
      expect(ref.number, 91);
    },
  );

  test('defaultBase delegates to gh.defaultBranch (incl. null)', () async {
    when(() => gh.defaultBranch(root)).thenAnswer((_) async => 'main');
    expect(await service.defaultBase(root), 'main');
    when(() => gh.defaultBranch(root)).thenAnswer((_) async => null);
    expect(await service.defaultBase(root), isNull);
  });
}
