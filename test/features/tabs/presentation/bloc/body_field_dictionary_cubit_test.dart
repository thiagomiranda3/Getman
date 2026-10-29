import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/error/failures.dart';
import 'package:getman/features/tabs/domain/entities/body_field_entry.dart';
import 'package:getman/features/tabs/domain/repositories/body_field_dictionary_repository.dart';
import 'package:getman/features/tabs/presentation/bloc/body_field_dictionary_cubit.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements BodyFieldDictionaryRepository {}

void main() {
  test('hydrates persisted names and publishes successful additions', () async {
    final repository = _Repository();
    when(() => repository.entries).thenReturn(const [
      BodyFieldEntry(name: 'name', usageCount: 2),
    ]);
    when(() => repository.recordUsage(any())).thenAnswer((_) async {
      when(() => repository.entries).thenReturn(const [
        BodyFieldEntry(name: 'name', usageCount: 3),
      ]);
    });
    final cubit = BodyFieldDictionaryCubit(repository);
    addTearDown(cubit.close);
    expect(cubit.state.entries.single.usageCount, 2);
    await cubit.recordUsage({'name': 1});
    expect(cubit.state.entries.single.usageCount, 3);
  });

  test(
    'storage failure keeps previous state and permits later updates',
    () async {
      final repository = _Repository();
      when(() => repository.entries).thenReturn(const []);
      var fail = true;
      when(() => repository.recordUsage(any())).thenAnswer((_) async {
        if (fail) {
          fail = false;
          throw const PersistenceFailure('disk full');
        }
        when(() => repository.entries).thenReturn(const [
          BodyFieldEntry(name: 'recovered', usageCount: 1),
        ]);
      });
      final cubit = BodyFieldDictionaryCubit(repository);
      addTearDown(cubit.close);
      await cubit.recordUsage({'lost': 1});
      expect(cubit.state.entries, isEmpty);
      await cubit.recordUsage({'recovered': 1});
      expect(cubit.state.entries.single.name, 'recovered');
    },
  );

  test('dispose during a write never emits after close', () async {
    final repository = _Repository();
    final pending = Completer<void>();
    when(() => repository.entries).thenReturn(const []);
    when(() => repository.recordUsage(any())).thenAnswer((_) => pending.future);
    final cubit = BodyFieldDictionaryCubit(repository);
    final saving = cubit.recordUsage({'name': 1});
    await cubit.close();
    pending.complete();
    await saving;
    expect(cubit.isClosed, isTrue);
  });
}
