// Equality tests for every TabsEvent subclass: equal instances compare
// equal, and each constructor field participates in Equatable props (a
// differing value per field must break equality). Guards against the
// "field added but forgotten in props" regression class.
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';

void main() {
  const configA = HttpRequestConfigEntity(id: 'cfg-a', url: 'https://a.dev');
  const configB = HttpRequestConfigEntity(id: 'cfg-b', url: 'https://b.dev');
  const tabA = HttpRequestTabEntity(tabId: 'tab-a', config: configA);
  const tabB = HttpRequestTabEntity(tabId: 'tab-b', config: configB);
  const responseA = HttpResponseEntity(
    statusCode: 200,
    body: 'ok',
    headers: {},
    durationMs: 1,
  );
  const responseB = HttpResponseEntity(
    statusCode: 500,
    body: 'boom',
    headers: {},
    durationMs: 2,
  );

  group('LoadTabs', () {
    test('instances are equal (no payload)', () {
      expect(const LoadTabs(), const LoadTabs());
      expect(const LoadTabs().props, isEmpty);
    });
  });

  group('AddTab', () {
    const full = AddTab(
      config: configA,
      collectionNodeId: 'node-1',
      collectionName: 'Saved',
      response: responseA,
    );

    test('equal instances compare equal', () {
      expect(
        full,
        const AddTab(
          config: configA,
          collectionNodeId: 'node-1',
          collectionName: 'Saved',
          response: responseA,
        ),
      );
      expect(const AddTab(), const AddTab());
    });

    test('every field participates in props', () {
      expect(full, isNot(full.copyWithConfig(configB)));
      expect(
        full,
        isNot(
          const AddTab(
            config: configA,
            collectionNodeId: 'node-2',
            collectionName: 'Saved',
            response: responseA,
          ),
        ),
      );
      expect(
        full,
        isNot(
          const AddTab(
            config: configA,
            collectionNodeId: 'node-1',
            collectionName: 'Renamed',
            response: responseA,
          ),
        ),
      );
      expect(
        full,
        isNot(
          const AddTab(
            config: configA,
            collectionNodeId: 'node-1',
            collectionName: 'Saved',
            response: responseB,
          ),
        ),
      );
    });
  });

  group('RemoveTab', () {
    test('tabId participates in props', () {
      expect(const RemoveTab('t1'), const RemoveTab('t1'));
      expect(const RemoveTab('t1'), isNot(const RemoveTab('t2')));
    });
  });

  group('SetActiveIndex', () {
    test('index participates in props', () {
      expect(const SetActiveIndex(3), const SetActiveIndex(3));
      expect(const SetActiveIndex(3), isNot(const SetActiveIndex(4)));
    });
  });

  group('ReorderTabs', () {
    test('both indices participate in props', () {
      expect(const ReorderTabs(1, 2), const ReorderTabs(1, 2));
      expect(const ReorderTabs(1, 2), isNot(const ReorderTabs(0, 2)));
      expect(const ReorderTabs(1, 2), isNot(const ReorderTabs(1, 3)));
    });
  });

  group('UpdateTab', () {
    test('tab participates in props', () {
      expect(const UpdateTab(tabA), const UpdateTab(tabA));
      expect(const UpdateTab(tabA), isNot(const UpdateTab(tabB)));
    });
  });

  group('CloseOtherTabs', () {
    test('tabId participates in props', () {
      expect(const CloseOtherTabs('t1'), const CloseOtherTabs('t1'));
      expect(const CloseOtherTabs('t1'), isNot(const CloseOtherTabs('t2')));
    });
  });

  group('CloseTabsToTheRight', () {
    test('tabId participates in props', () {
      expect(const CloseTabsToTheRight('t1'), const CloseTabsToTheRight('t1'));
      expect(
        const CloseTabsToTheRight('t1'),
        isNot(const CloseTabsToTheRight('t2')),
      );
    });
  });

  group('CloseTabsToTheLeft', () {
    test('tabId participates in props', () {
      expect(const CloseTabsToTheLeft('t1'), const CloseTabsToTheLeft('t1'));
      expect(
        const CloseTabsToTheLeft('t1'),
        isNot(const CloseTabsToTheLeft('t2')),
      );
    });
  });

  group('DuplicateTab', () {
    test('tabId participates in props', () {
      expect(const DuplicateTab('t1'), const DuplicateTab('t1'));
      expect(const DuplicateTab('t1'), isNot(const DuplicateTab('t2')));
    });
  });

  group('SendRequest', () {
    const full = SendRequest(
      tabId: 't1',
      envVars: {'host': 'a.dev'},
      responseHistoryLimit: 3,
      saveLargeResponsesInHistory: false,
    );

    test('equal instances compare equal (defaults included)', () {
      expect(
        full,
        const SendRequest(
          tabId: 't1',
          envVars: {'host': 'a.dev'},
          responseHistoryLimit: 3,
          saveLargeResponsesInHistory: false,
        ),
      );
      expect(const SendRequest(tabId: 't1'), const SendRequest(tabId: 't1'));
    });

    test('defaults are an empty env map, limit 5, save-large true', () {
      const event = SendRequest(tabId: 't1');
      expect(event.envVars, isEmpty);
      expect(event.responseHistoryLimit, 5);
      expect(event.saveLargeResponsesInHistory, isTrue);
    });

    test('every field participates in props', () {
      expect(
        full,
        isNot(
          const SendRequest(
            tabId: 't2',
            envVars: {'host': 'a.dev'},
            responseHistoryLimit: 3,
            saveLargeResponsesInHistory: false,
          ),
        ),
      );
      expect(
        full,
        isNot(
          const SendRequest(
            tabId: 't1',
            envVars: {'host': 'b.dev'},
            responseHistoryLimit: 3,
            saveLargeResponsesInHistory: false,
          ),
        ),
      );
      expect(
        full,
        isNot(
          const SendRequest(
            tabId: 't1',
            envVars: {'host': 'a.dev'},
            responseHistoryLimit: 9,
            saveLargeResponsesInHistory: false,
          ),
        ),
      );
      expect(
        full,
        isNot(
          const SendRequest(
            tabId: 't1',
            envVars: {'host': 'a.dev'},
            responseHistoryLimit: 3,
          ),
        ),
      );
    });
  });

  group('ViewResponseHistoryEntry', () {
    test('tabId and entryId participate in props', () {
      expect(
        const ViewResponseHistoryEntry(tabId: 't1', entryId: 'e1'),
        const ViewResponseHistoryEntry(tabId: 't1', entryId: 'e1'),
      );
      expect(
        const ViewResponseHistoryEntry(tabId: 't1', entryId: 'e1'),
        isNot(const ViewResponseHistoryEntry(tabId: 't2', entryId: 'e1')),
      );
      expect(
        const ViewResponseHistoryEntry(tabId: 't1', entryId: 'e1'),
        isNot(const ViewResponseHistoryEntry(tabId: 't1', entryId: 'e2')),
      );
    });
  });

  group('CancelRequest', () {
    test('tabId participates in props', () {
      expect(const CancelRequest('t1'), const CancelRequest('t1'));
      expect(const CancelRequest('t1'), isNot(const CancelRequest('t2')));
    });
  });

  group('AddPanel', () {
    test('name participates in props', () {
      expect(const AddPanel(name: 'Work'), const AddPanel(name: 'Work'));
      expect(const AddPanel(), const AddPanel());
      expect(const AddPanel(name: 'Work'), isNot(const AddPanel(name: 'Api')));
      expect(const AddPanel(name: 'Work'), isNot(const AddPanel()));
    });
  });

  group('RemovePanel', () {
    test('panelId participates in props', () {
      expect(const RemovePanel('p1'), const RemovePanel('p1'));
      expect(const RemovePanel('p1'), isNot(const RemovePanel('p2')));
    });
  });

  group('RenamePanel', () {
    test('panelId and name participate in props', () {
      expect(const RenamePanel('p1', 'Work'), const RenamePanel('p1', 'Work'));
      expect(
        const RenamePanel('p1', 'Work'),
        isNot(const RenamePanel('p2', 'Work')),
      );
      expect(
        const RenamePanel('p1', 'Work'),
        isNot(const RenamePanel('p1', 'Api')),
      );
    });
  });

  group('SetActivePanel', () {
    test('panelId participates in props', () {
      expect(const SetActivePanel('p1'), const SetActivePanel('p1'));
      expect(const SetActivePanel('p1'), isNot(const SetActivePanel('p2')));
    });
  });

  group('ReorderPanels', () {
    test('both indices participate in props', () {
      expect(const ReorderPanels(0, 1), const ReorderPanels(0, 1));
      expect(const ReorderPanels(0, 1), isNot(const ReorderPanels(2, 1)));
      expect(const ReorderPanels(0, 1), isNot(const ReorderPanels(0, 2)));
    });
  });

  group('MoveTabToPanel', () {
    test('tabId and targetPanelId participate in props', () {
      expect(
        const MoveTabToPanel('t1', 'p1'),
        const MoveTabToPanel('t1', 'p1'),
      );
      expect(
        const MoveTabToPanel('t1', 'p1'),
        isNot(const MoveTabToPanel('t2', 'p1')),
      );
      expect(
        const MoveTabToPanel('t1', 'p1'),
        isNot(const MoveTabToPanel('t1', 'p2')),
      );
    });
  });

  group('MoveTabToNewPanel', () {
    test('tabId and name participate in props', () {
      expect(
        const MoveTabToNewPanel('t1', name: 'Work'),
        const MoveTabToNewPanel('t1', name: 'Work'),
      );
      expect(const MoveTabToNewPanel('t1'), const MoveTabToNewPanel('t1'));
      expect(
        const MoveTabToNewPanel('t1', name: 'Work'),
        isNot(const MoveTabToNewPanel('t2', name: 'Work')),
      );
      expect(
        const MoveTabToNewPanel('t1', name: 'Work'),
        isNot(const MoveTabToNewPanel('t1', name: 'Api')),
      );
    });
  });

  group('ReopenClosedTab', () {
    test('instances are equal (no payload)', () {
      expect(const ReopenClosedTab(), const ReopenClosedTab());
      expect(const ReopenClosedTab().props, isEmpty);
    });
  });

  group('CloseSavedTabs', () {
    test('panelId and savedConfigs participate in props', () {
      expect(
        const CloseSavedTabs(panelId: 'p1', savedConfigs: {'n1': configA}),
        const CloseSavedTabs(panelId: 'p1', savedConfigs: {'n1': configA}),
      );
      expect(
        const CloseSavedTabs(panelId: 'p1', savedConfigs: {'n1': configA}),
        isNot(
          const CloseSavedTabs(panelId: 'p2', savedConfigs: {'n1': configA}),
        ),
      );
      expect(
        const CloseSavedTabs(panelId: 'p1', savedConfigs: {'n1': configA}),
        isNot(
          const CloseSavedTabs(panelId: 'p1', savedConfigs: {'n1': configB}),
        ),
      );
    });
  });

  group('RevertTab', () {
    test('tabId and savedConfig participate in props', () {
      expect(
        const RevertTab(tabId: 't1', savedConfig: configA),
        const RevertTab(tabId: 't1', savedConfig: configA),
      );
      expect(
        const RevertTab(tabId: 't1', savedConfig: configA),
        isNot(const RevertTab(tabId: 't2', savedConfig: configA)),
      );
      expect(
        const RevertTab(tabId: 't1', savedConfig: configA),
        isNot(const RevertTab(tabId: 't1', savedConfig: configB)),
      );
    });
  });

  group('event types are distinguishable', () {
    test('same-shaped events of different classes are not equal', () {
      // All the single-tabId close variants share a props shape; Equatable
      // includes runtimeType, so they must still be distinct.
      expect(
        const CloseOtherTabs('t1'),
        isNot(const CloseTabsToTheRight('t1')),
      );
      expect(
        const CloseTabsToTheRight('t1'),
        isNot(const CloseTabsToTheLeft('t1')),
      );
      expect(const RemoveTab('t1'), isNot(const DuplicateTab('t1')));
      expect(const LoadTabs(), isNot(const ReopenClosedTab()));
    });
  });
}

/// Convenience for the AddTab config-field check without repeating the other
/// three fields at every call site.
extension on AddTab {
  AddTab copyWithConfig(HttpRequestConfigEntity config) => AddTab(
    config: config,
    collectionNodeId: collectionNodeId,
    collectionName: collectionName,
    response: response,
  );
}
