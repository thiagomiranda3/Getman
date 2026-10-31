// Native release benchmark: real shell, isolated Hive, raw frame timings.
// Never used by the shipping entrypoint. See README.md for measurement scope.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:getman/core/di/injection_container.dart' as di;
import 'package:getman/core/domain/entities/body_type.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/core/network/dio_adapter_config_io.dart';
import 'package:getman/core/network/http_response.dart';
import 'package:getman/core/storage/background_repositories.dart';
import 'package:getman/core/storage/hive_boxes.dart';
import 'package:getman/core/storage/storage_connection.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/home/presentation/widgets/startup_gate.dart';
import 'package:getman/features/settings/data/models/settings_model.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';
import 'package:getman/features/tabs/data/request_serializer.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:getman/main.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_ce/hive.dart';

Future<void> main() async {
  final boot = Stopwatch()..start();
  final binding = WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  final env = Platform.environment;
  final client = HttpClient();
  Future<void> report(Map<String, Object?> value) async {
    final request = await client.postUrl(
      Uri.parse('${env['GETMAN_PERF_URL']}/report'),
    );
    request.write(jsonEncode(value));
    await (await request.close()).drain<void>();
  }

  try {
    if (!const bool.fromEnvironment('dart.vm.product')) {
      throw StateError('Release build required');
    }
    final mode = env['GETMAN_PERF_MODE']!;
    if (mode == 'seed') {
      final dir = await Directory.systemTemp.createTemp('getman-perf-');
      for (final name in ['client.pem', 'client.key']) {
        final request = await client.getUrl(
          Uri.parse('${env['GETMAN_PERF_URL']}/$name'),
        );
        final response = await request.close();
        await response.pipe(File('${dir.path}/$name').openWrite());
      }
      await di.initSettings(storageDirectoryOverride: dir.path);
      const settings = SettingsEntity(checkForUpdatesOnStartup: false);
      await Hive.box<SettingsModel>(
        HiveBoxes.settings,
      ).put('current', SettingsModel.fromEntity(settings));
      await di.initServices(settings);
      final count = int.parse(env['GETMAN_PERF_TABS']!);
      final body = 'x' * (128 * 1024);
      await BackgroundTabsPersistence(di.sl<StorageConnection>()).saveTabs([
        for (var i = 0; i < count; i++)
          HttpRequestTabEntity(
            config: HttpRequestConfigEntity(
              id: 'request-$i',
              url: 'https://example.test/$i',
            ),
            tabId: 'tab-$i',
            response: HttpResponseEntity(
              statusCode: 200,
              body: body,
              headers: const {},
              durationMs: 1,
            ),
          ),
      ]);
      await di.reset();
      await report({'event': 'seed', 'directory': dir.path});
      exit(0);
    }
    final storage = env['GETMAN_PERF_STORAGE']!;
    if (mode == 'cleanup') {
      if (!storage.contains('/getman-perf-')) throw StateError('Not a fixture');
      await Directory(storage).delete(recursive: true);
      await report({'event': 'cleanup'});
      exit(0);
    }
    final frames = <Map<String, int>>[];
    binding.addTimingsCallback((timings) {
      for (final t in timings) {
        frames.add({
          'build_us': t.buildDuration.inMicroseconds,
          'raster_us': t.rasterDuration.inMicroseconds,
          'total_us': t.totalSpan.inMicroseconds,
        });
      }
    });
    var maxGap = 0;
    var last = boot.elapsedMicroseconds;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 1), (_) {
      final now = boot.elapsedMicroseconds;
      if (now - last > maxGap) maxGap = now - last;
      last = now;
    });
    final settings = await di.initSettings(storageDirectoryOverride: storage);
    final settingsUs = boot.elapsedMicroseconds;
    final servicesReady = Completer<void>();
    runApp(
      StartupGate(
        settings: settings,
        initialize: () async {
          await di.initServices(settings);
          servicesReady.complete();
          return MyApp(initialSettings: settings);
        },
      ),
    );
    await binding.waitUntilFirstFrameRasterized;
    final firstUs = boot.elapsedMicroseconds;
    await report({'event': 'first_frame', 'dart_us': firstUs});
    await servicesReady.future;
    final tabs = di.sl<TabsBloc>();
    if (tabs.state.isLoading || tabs.state.tabs.isEmpty) {
      await tabs.stream.firstWhere((s) => !s.isLoading && s.tabs.isNotEmpty);
    }
    final collections = di.sl<CollectionsBloc>();
    if (collections.state.isLoading) {
      await collections.stream.firstWhere((s) => !s.isLoading);
    }
    await binding.endOfFrame;
    final readyUs = boot.elapsedMicroseconds;
    final startupGap = maxGap;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await report({
      'event': 'startup',
      'settings_us': settingsUs,
      'first_frame_us': firstUs,
      'workspace_frame_us': readyUs,
      'max_gap_us': startupGap,
      'rss': ProcessInfo.currentRss,
      'frames': List.of(frames),
    });
    Future<void> measure(String name, Future<void> Function() work) async {
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      frames.clear();
      maxGap = 0;
      last = boot.elapsedMicroseconds;
      final startRss = ProcessInfo.currentRss;
      final clock = Stopwatch()..start();
      await work();
      await binding.endOfFrame;
      clock.stop();
      final gap = maxGap;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await report({
        'event': 'work',
        'name': name,
        'elapsed_us': clock.elapsedMicroseconds,
        'max_gap_us': gap,
        'rss_before': startRss,
        'rss_after': ProcessInfo.currentRss,
        'frames': List.of(frames),
      });
    }

    if (mode == 'workloads') {
      final raw = jsonEncode({
        'items': List.generate(
          40000,
          (i) => {
            'id': i,
            'name': '{{value}}',
            'payload': 'abcdefghijklmnopqrstuv',
          },
        ),
      });
      final graphql = jsonEncode({
        'items': List.generate(80000, (i) => {'id': i, 'name': '{{value}}'}),
      });
      for (var round = 0; round < 5; round++) {
        await measure('prepare_raw', () async {
          final result = await RequestSerializer.buildBody(
            config: HttpRequestConfigEntity(id: 'raw', body: raw),
            headers: {},
            envVars: {'value': 'resolved'},
          );
          if (result is! String || result.contains('{{value}}')) {
            throw StateError('Unresolved body');
          }
        });
        await measure('prepare_graphql', () async {
          await RequestSerializer.buildBody(
            config: HttpRequestConfigEntity(
              id: 'graphql',
              bodyType: BodyType.graphql,
              body: 'query Test { items }',
              graphqlVariables: graphql,
            ),
            headers: {},
            envVars: {'value': 'resolved'},
          );
        });
        await measure('pretty_depth_1000', () async {
          await JsonUtils.prettify('${'[' * 1000}0${']' * 1000}');
        });
        final cert = '$storage/client.pem';
        await measure('mtls_configure', () async {
          buildConfiguredHttpClient(
            verifySsl: true,
            clientCertPath: cert,
            clientKeyPath: '$storage/client.key',
          ).close(force: true);
          if (lastCertificateError != null) {
            throw StateError(lastCertificateError!);
          }
        });
      }
      di.sl<RequestSectionIndex>().value = 3;
      await binding.endOfFrame;
      for (final content in [
        raw,
        const JsonEncoder.withIndent('  ').convert(jsonDecode(raw)),
      ]) {
        await measure(
          content.contains('\n')
              ? 'open_multiline_body'
              : 'open_singleline_body',
          () async {
            final id = 'large-${content.length}';
            final added = tabs.stream.firstWhere(
              (s) => s.tabs.any((t) => t.config.id == id),
            );
            tabs.add(
              AddTab(
                config: HttpRequestConfigEntity(id: id, body: content),
              ),
            );
            await added;
            await binding.endOfFrame;
            await Future<void>.delayed(const Duration(milliseconds: 600));
            JsonCodeEditor? editor;
            void visit(Element element) {
              final widget = element.widget;
              if (widget is JsonCodeEditor &&
                  widget.controller.text == content) {
                editor = widget;
              }
              element.visitChildElements(visit);
            }

            binding.rootElement!.visitChildElements(visit);
            if (editor == null) throw StateError('Editor not ready');
          },
        );
        if (!content.contains('\n')) {
          JsonCodeEditor? editor;
          void visit(Element element) {
            final widget = element.widget;
            if (widget is JsonCodeEditor && widget.controller.text == content) {
              editor = widget;
            }
            element.visitChildElements(visit);
          }

          binding.rootElement!.visitChildElements(visit);
          final finder = editor!.findController!;
          await measure('find_singleline_body', () async {
            finder.findMode();
            await binding.endOfFrame;
            await Future<void>.delayed(const Duration(milliseconds: 600));
          });
          await measure('find_singleline_match', () async {
            TextField? field;
            void visit(Element element) {
              final widget = element.widget;
              if (widget is TextField &&
                  widget.key == const ValueKey('large_find_field')) {
                field = widget;
              }
              element.visitChildElements(visit);
            }

            binding.rootElement!.visitChildElements(visit);
            if (field == null) throw StateError('Windowed find not visible');
            field!.controller!.text = '39999';
            await Future<void>.delayed(const Duration(milliseconds: 600));
            await binding.endOfFrame;
            String? snippet;
            void check(Element element) {
              final widget = element.widget;
              if (widget is SelectableText &&
                  widget.key == const ValueKey('large_find_window_text')) {
                snippet = widget.textSpan!.toPlainText();
              }
              element.visitChildElements(check);
            }

            binding.rootElement!.visitChildElements(check);
            if (snippet == null ||
                !snippet!.contains('39999') ||
                snippet!.length > 4100) {
              throw StateError('Tail match missing or unbounded');
            }
          });
          finder.close();
        }
      }
    }
    heartbeat.cancel();
    await tabs.flushPendingSaves();
    await di.sl<StorageConnection>().flush();
    await report({'event': 'done', 'peak_rss': ProcessInfo.maxRss});
    client.close(force: true);
    exit(0);
  } on Object catch (error, stack) {
    await report({'event': 'error', 'error': '$error\n$stack'});
    client.close(force: true);
    exit(1);
  }
}
