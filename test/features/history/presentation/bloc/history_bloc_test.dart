import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/history/domain/repositories/history_repository.dart';
import 'package:getman/features/history/domain/usecases/history_usecases.dart';
import 'package:getman/features/history/presentation/bloc/history_bloc.dart';
import 'package:mocktail/mocktail.dart';

class MockHistoryRepository extends Mock implements HistoryRepository {}

void main() {
  late MockHistoryRepository repo;
  late StreamController<List<HttpRequestConfigEntity>> controller;

  HttpRequestConfigEntity req(String url) => HttpRequestConfigEntity(id: url, url: url);

  setUp(() {
    repo = MockHistoryRepository();
    controller = StreamController<List<HttpRequestConfigEntity>>();
    when(() => repo.watchHistory()).thenAnswer((_) => controller.stream);
  });

  HistoryBloc build() => HistoryBloc(watchHistoryUseCase: WatchHistoryUseCase(repo));

  test('starts loading, then mirrors the watched history', () async {
    final bloc = build();
    addTearDown(bloc.close);
    expect(bloc.state.isLoading, isTrue);

    controller.add([req('https://a.com')]);
    await bloc.stream.firstWhere((s) => !s.isLoading);

    expect(bloc.state.isLoading, isFalse);
    expect(bloc.state.history.map((e) => e.url), ['https://a.com']);
  });

  test('updates on each subsequent emission', () async {
    final bloc = build();
    addTearDown(bloc.close);

    controller.add([req('https://a.com')]);
    await bloc.stream.firstWhere((s) => s.history.length == 1);
    controller.add([req('https://a.com'), req('https://b.com')]);
    await bloc.stream.firstWhere((s) => s.history.length == 2);

    expect(bloc.state.history.map((e) => e.url), ['https://a.com', 'https://b.com']);
  });

  test('close() cancels the subscription so later emissions are ignored', () async {
    final bloc = build();
    controller.add([req('https://a.com')]);
    await bloc.stream.firstWhere((s) => !s.isLoading);

    await bloc.close();

    // Emitting after close must not throw (the subscription is cancelled and
    // the listener also guards on isClosed).
    expect(() => controller.add([req('https://c.com')]), returnsNormally);
    expect(bloc.state.history.map((e) => e.url), ['https://a.com']);
  });
}
