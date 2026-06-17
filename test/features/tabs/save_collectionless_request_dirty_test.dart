// Regression guard for "saving a brand-new (collectionless) request leaves the
// tab dirty". Root cause (fixed): the save dialog generated a node id, but the
// pre-generated id was not threaded into SaveRequestToCollection, so the bloc
// self-generated a DIFFERENT id. The tab's collectionNodeId then pointed at a
// node that did not exist → TabDirtyChecker's configById lookup always missed →
// the tab stayed dirty (and stayed dirty across a reopen, since the broken link
// is persisted verbatim).
//
// These tests drive the EXACT sequence the save dialog runs against the real
// CollectionsBloc + TabsBloc model layer and assert the tab is clean — both
// immediately after save and after a Hive round-trip (reopen).
import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/multipart_field_entity.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/collections/data/models/collection_node_model.dart';
import 'package:getman/features/collections/domain/entities/collection_node_entity.dart';
import 'package:getman/features/collections/domain/repositories/collections_repository.dart';
import 'package:getman/features/collections/domain/usecases/collections_usecases.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/home/domain/usecases/tab_dirty_checker.dart';
import 'package:getman/features/tabs/data/models/request_tab_model.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';

class MockCollectionsRepository extends Mock implements CollectionsRepository {}

void main() {
  const checker = TabDirtyChecker();

  late MockCollectionsRepository repo;

  setUpAll(() => registerFallbackValue(<CollectionNodeEntity>[]));

  setUp(() {
    repo = MockCollectionsRepository();
    when(() => repo.getCollections()).thenAnswer((_) async => const []);
    when(() => repo.saveCollections(any())).thenAnswer((_) async {});
  });

  CollectionsBloc buildCollections() => CollectionsBloc(
    getCollectionsUseCase: GetCollectionsUseCase(repo),
    saveCollectionsUseCase: SaveCollectionsUseCase(repo),
    saveDebounce: const Duration(milliseconds: 5),
  );

  // An unlinked tab the user has edited (non-default URL) but not yet saved.
  HttpRequestTabEntity editedUnlinkedTab() => const HttpRequestTabEntity(
    tabId: 'tab-1',
    config: HttpRequestConfigEntity(id: 'cfg-1', url: 'https://edited.dev'),
  );

  group('symptom (a): immediately after save the tab is NOT dirty', () {
    test(
      'SaveRequestToCollection + UpdateTab link → checker reports clean',
      () async {
        final collections = buildCollections();
        addTearDown(collections.close);

        final tab = editedUnlinkedTab();

        // Sanity: an unlinked, edited tab IS dirty before saving.
        expect(
          checker(tab: tab, savedConfigs: collections.state.configById),
          isTrue,
          reason: 'edited unlinked tab should start dirty',
        );

        // --- the exact sequence _showSaveDialog.onConfirm runs ---
        final nodeId = const Uuid().v4();
        collections.add(
          SaveRequestToCollection(
            'My Request',
            tab.config.copyWith(),
            id: nodeId,
          ),
        );
        await collections.stream.first; // wait for the emit

        // The open tab links itself to the new node (UpdateTab in the real
        // flow), using the SAME pre-generated id the dialog passed to the bloc.
        final linkedTab = tab.copyWith(
          collectionName: 'My Request',
          collectionNodeId: nodeId,
        );

        final savedConfigs = collections.state.configById;
        // The saved node must exist under exactly the id the tab points at.
        expect(savedConfigs.containsKey(nodeId), isTrue);
        expect(savedConfigs[nodeId], tab.config);

        expect(
          checker(tab: linkedTab, savedConfigs: savedConfigs),
          isFalse,
          reason:
              'after saving, the tab must resolve to its saved node and be '
              'clean',
        );
      },
    );

    test('the bloc honors the caller-supplied node id verbatim', () async {
      final collections = buildCollections();
      addTearDown(collections.close);

      const suppliedId = 'caller-supplied-id';
      collections.add(
        const SaveRequestToCollection(
          'My Request',
          HttpRequestConfigEntity(id: 'cfg-1', url: 'https://x.dev'),
          id: suppliedId,
        ),
      );
      await collections.stream.first;

      // The new root node must carry the supplied id (not a fresh UUID) — this
      // is what lets the open tab link to it.
      expect(
        collections.state.collections.single.id,
        suppliedId,
      );
    });
  });

  group('symptom (b): the link survives a reopen (Hive round-trip)', () {
    test('collectionNodeId + collectionName encode→decode preserved', () {
      const nodeId = 'node-xyz';
      const linkedTab = HttpRequestTabEntity(
        tabId: 'tab-1',
        config: HttpRequestConfigEntity(id: 'cfg-1', url: 'https://edited.dev'),
        collectionNodeId: nodeId,
        collectionName: 'My Request',
      );

      final restored = HttpRequestTabModel.fromEntity(linkedTab).toEntity();

      expect(restored.collectionNodeId, nodeId);
      expect(restored.collectionName, 'My Request');
    });

    test(
      'rich config survives BOTH Hive round-trips → reopened tab is clean',
      () {
        // A realistic, heavily-customized request (the kind a user actually
        // edits before saving): non-default headers, auth, urlencoded body.
        final richConfig = HttpRequestConfigEntity(
          id: 'cfg-1',
          method: 'POST',
          url: 'https://api.example.dev/users?page=2',
          headers: const {
            'Content-Type': 'application/json',
            'Accept': '*/*',
            'X-Custom': 'yes',
          },
          body: '{"name":"jane"}',
          auth: const AuthConfig(
            type: AuthType.bearer,
            token: 'tok-123',
          ).toMap(),
          bodyType: BodyType.urlencoded,
          formFields: const [MultipartFieldEntity(name: 'a', value: '1')],
        );

        const nodeId = 'node-1';

        // The tab the user has open (linked to the node after save).
        final linkedTab = HttpRequestTabEntity(
          tabId: 'tab-1',
          config: richConfig,
          collectionNodeId: nodeId,
          collectionName: 'My Request',
        );

        // The collection node the save created (config = a copyWith of the
        // tab config).
        final node = CollectionNodeEntity(
          id: nodeId,
          name: 'My Request',
          isFolder: false,
          config: richConfig.copyWith(),
        );

        // --- reopen: both come back through their Hive models ---
        final restoredTab = HttpRequestTabModel.fromEntity(
          linkedTab,
        ).toEntity();
        final restoredNode = CollectionNode.fromEntity(node).toEntity();

        final savedConfigs = {restoredNode.id: restoredNode.config!};

        expect(
          checker(tab: restoredTab, savedConfigs: savedConfigs),
          isFalse,
          reason:
              'after a restart, a saved request must round-trip to a clean tab',
        );
      },
    );
  });
}
