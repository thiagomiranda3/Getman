import 'dart:convert';

import 'package:getman/core/git/gh_service.dart';

/// Reduces a `statusCheckRollup` array to `none`/`pending`/`passing`/`failing`.
/// A check is unfinished when a CheckRun's `status` != `COMPLETED` or a
/// StatusContext's `state` is `PENDING`/`EXPECTED`. Pending wins over failing
/// wins over passing.
String rollupChecks(Object? statusCheckRollup) {
  if (statusCheckRollup is! List || statusCheckRollup.isEmpty) return 'none';
  var anyPending = false;
  var anyFailing = false;
  for (final raw in statusCheckRollup) {
    if (raw is! Map) continue;
    final type = raw['__typename'];
    if (type == 'CheckRun') {
      final status = raw['status'] as String?;
      if (status != 'COMPLETED') {
        anyPending = true;
      } else {
        final c = raw['conclusion'] as String?;
        if (c != 'SUCCESS' && c != 'NEUTRAL' && c != 'SKIPPED') {
          anyFailing = true;
        }
      }
    } else {
      // StatusContext
      final state = raw['state'] as String?;
      if (state == 'PENDING' || state == 'EXPECTED') {
        anyPending = true;
      } else if (state != 'SUCCESS') {
        anyFailing = true;
      }
    }
  }
  if (anyPending) return 'pending';
  if (anyFailing) return 'failing';
  return 'passing';
}

/// Parses `gh pr list --json number,title,state,url,isDraft,statusCheckRollup`.
List<PullRequestInfo> parsePrList(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! List) return const [];
  return [
    for (final raw in decoded)
      if (raw is Map)
        PullRequestInfo(
          number: (raw['number'] as num?)?.toInt() ?? 0,
          title: raw['title'] as String? ?? '',
          state: raw['state'] as String? ?? 'OPEN',
          url: raw['url'] as String? ?? '',
          isDraft: raw['isDraft'] as bool? ?? false,
          checks: rollupChecks(raw['statusCheckRollup']),
        ),
  ];
}

/// The last `https://…` token gh printed — that is the created PR's URL.
String parsePrUrl(String stdout) {
  final match = RegExp(r'https://\S+').allMatches(stdout).toList();
  return match.isEmpty ? '' : match.last.group(0)!.trim();
}
