import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';

void main() {
  HttpRequestTabEntity tab({String? collectionName, String url = ''}) =>
      HttpRequestTabEntity(
        tabId: 't1',
        collectionName: collectionName,
        config: HttpRequestConfigEntity(id: 'c1', url: url),
      );

  group('displayTitle', () {
    test('prefers the saved collection name', () {
      expect(
        tab(collectionName: 'Login', url: 'https://x.dev').displayTitle,
        'Login',
      );
    });

    test('falls back to the URL', () {
      expect(tab(url: 'https://x.dev').displayTitle, 'https://x.dev');
    });

    test('labels unsaved empty tabs NEW REQUEST', () {
      expect(tab().displayTitle, 'NEW REQUEST');
    });
  });

  group('byId', () {
    test('finds a tab by id and returns null on miss', () {
      final tabs = [tab(url: 'a')];
      expect(tabs.byId('t1'), tabs.single);
      expect(tabs.byId('ghost'), isNull);
    });
  });

  group('viewedHistoryEntryId', () {
    test('defaults to null (viewing latest) and participates in props', () {
      final base = tab();
      expect(base.viewedHistoryEntryId, isNull);
      // Same tab differing ONLY by viewedHistoryEntryId must not be equal —
      // this inequality is what keeps a time-travel emission between
      // value-equal responses from being suppressed (G2).
      expect(base, isNot(base.copyWith(viewedHistoryEntryId: 'e1')));
      expect(
        base.copyWith(viewedHistoryEntryId: 'e1'),
        base.copyWith(viewedHistoryEntryId: 'e1'),
      );
    });

    test('copyWith sets, keeps, and explicitly clears it', () {
      final viewing = tab().copyWith(viewedHistoryEntryId: 'e1');
      expect(viewing.viewedHistoryEntryId, 'e1');
      // Omitted -> unchanged (the _unset sentinel, same as response).
      expect(viewing.copyWith(isSending: true).viewedHistoryEntryId, 'e1');
      // Explicit null -> cleared (back to viewing the latest response).
      expect(
        viewing.copyWith(viewedHistoryEntryId: null).viewedHistoryEntryId,
        isNull,
      );
    });
  });
}
