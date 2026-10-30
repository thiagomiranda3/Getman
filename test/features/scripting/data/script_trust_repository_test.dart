import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/scripting/data/repositories/script_trust_repository_impl.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;
  late Box<String> box;
  late ScriptTrustRepositoryImpl repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('getman-script-trust-');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('script_trust');
    repository = ScriptTrustRepositoryImpl(box);
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'trust survives restart and binds both source strings and identity',
    () async {
      const scripts = RequestScripts(
        preRequest: 'const n = 1;',
        postResponse: 'const n = 2;',
      );
      expect(await repository.isTrusted('one', scripts), isFalse);
      await repository.trust('one', scripts);
      await box.close();
      box = await Hive.openBox<String>('script_trust');
      repository = ScriptTrustRepositoryImpl(box);
      expect(await repository.isTrusted('one', scripts), isTrue);
      expect(await repository.isTrusted('two', scripts), isFalse);
      expect(
        await repository.isTrusted(
          'one',
          scripts.copyWith(preRequest: 'const n = 2;'),
        ),
        isFalse,
      );
      expect(
        await repository.isTrusted(
          'one',
          scripts.copyWith(postResponse: 'const n = 1;'),
        ),
        isFalse,
      );
      expect(
        await repository.isTrusted('one', scripts.copyWith(apiVersion: 2)),
        isFalse,
      );
      expect(
        await repository.isTrusted(
          'one',
          scripts.copyWith(preRequestEnabled: false),
        ),
        isTrue,
      );
    },
  );

  test('empty scripts require no stored approval', () async {
    expect(await repository.isTrusted('new', const RequestScripts()), isTrue);
    expect(box.isEmpty, isTrue);
  });

  test('a stale approval only trusts the content it was shown', () async {
    const shown = RequestScripts(preRequest: 'const safe = 1;');
    final changed = shown.copyWith(preRequest: 'throw new Error("new");');
    await repository.trust('one', shown);
    expect(await repository.isTrusted('one', changed), isFalse);
  });

  test('failed persistence cannot report a successful approval', () async {
    await box.close();
    await expectLater(
      repository.trust('one', const RequestScripts(preRequest: '1;')),
      throwsA(isA<PersistenceFailure>()),
    );
  });
}
