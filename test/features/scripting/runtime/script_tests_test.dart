import 'package:flutter_test/flutter_test.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart';
import 'package:getman/features/scripting/data/repositories/script_runtime_repository_impl.dart';
import 'package:getman/features/scripting/domain/entities/script_error_kind.dart';
import 'package:getman/features/scripting/domain/entities/script_input.dart';
import 'package:getman/features/scripting/domain/entities/script_limits.dart';
import 'package:getman/features/scripting/domain/entities/script_output.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_cancellation.dart';

import '../support/runtime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ScriptRuntimeRepositoryImpl runtime;
  // The browser test server exposes checked-in assets through test/ symlinks.
  // Its platform asset channel is absent; fetch the actual bytes over HTTP.
  setUp(
    () => runtime = ScriptRuntimeRepositoryImpl(
      assetBundle: ScriptRuntimeTestAssets(),
    ),
  );
  tearDown(() async => runtime.close());
  Future<ScriptOutput> run(
    String source, {
    ScriptLimits limits = const ScriptLimits(),
  }) => runtime.execute(
    ScriptInput(
      executionId: 'run',
      tabId: 'tab',
      source: source,
      phase: ScriptPhase.postResponse,
      config: const HttpRequestConfigEntity(id: 'request'),
    ),
    cancellation: ScriptCancellation(),
    limits: limits,
  );
  test(
    'failed test continues and duplicate names retain ordered distinct IDs',
    () async {
      final result = await run('''
      gm.test('same', () => gm.expect(500).to.equal(200));
      gm.test('same', async () => gm.expect(await Promise.resolve('ok')).to.equal('ok'));
      gm.test('third', () => gm.expect(null).to.exist);
    ''');
      expect(result.error, isNull);
      expect(result.tests.map((test) => test.passed), [false, true, true]);
      expect(result.tests.map((test) => test.id).toSet(), hasLength(3));
      expect(result.tests.first.message, contains('200'));
    },
  );
  test(
    'comparators cover strict values, JSON structure, types and finite ranges',
    () async {
      final result = await run('''
      gm.test('comparators', () => {
        gm.expect(1).to.not.equal('1');
        gm.expect({a:[1,null],b:true}).to.deep.equal({b:true,a:[1,null]});
        gm.expect([1]).to.be.a('array');
        gm.expect(null).to.be.a('null');
        gm.expect(undefined).to.be.a('undefined');
        gm.expect('session').to.contain('sess');
        gm.expect([1,2]).to.contain(2);
        gm.expect(2).to.be.lessThan(3);
        gm.expect(2).to.be.greaterThan(1);
        gm.expect(2).to.be.within(2,3);
        gm.expect(3).to.be.within(2,3);
      });
      gm.test('strict', () => gm.expect(1).to.equal('1'));
      gm.test('structure', () => gm.expect({a:1}).to.deep.equal({a:'1'}));
      gm.test('missing', () => gm.expect(undefined).to.exist);
      gm.test('finite', () => gm.expect(NaN).to.be.lessThan(3));
      gm.test('numeric', () => gm.expect('2').to.be.within(1,3));
    ''');
      expect(result.error, isNull);
      expect(result.tests.map((test) => test.passed), [
        true,
        false,
        false,
        false,
        false,
        false,
      ]);
    },
  );
  test(
    'test registration bound fails explicitly and runtime recovers',
    () async {
      final result = await run(
        "for(let i=0;i<3;i++) gm.test('test',()=>{});",
        limits: const ScriptLimits(testCount: 2),
      );
      expect(result.error, isNotNull);
      expect((await run("gm.test('ok',()=>{});")).tests.single.passed, isTrue);
    },
  );
  test(
    'console handles cycles, Unicode and truncates within both limits',
    () async {
      final result = await run(
        "const x={};x.x=x;console.log('sessão 🚀',x); "
        "for(let i=0;i<100;i++) console.warn('á'.repeat(100));",
        limits: const ScriptLimits(logEntries: 4, logBytes: 160),
      );
      expect(result.error, isNull);
      expect(result.logs.length, lessThanOrEqualTo(4));
      expect(result.logs.first.message, contains('sessão 🚀'));
      expect(result.logs.first.message, contains('[Circular]'));
      expect(result.logs.last.message, contains('truncated'));
    },
  );
  test(
    'uncaught error retains earlier console and discards no HTTP status',
    () async {
      final result = await run("console.error('before'); throw Error('stop');");
      expect(result.error?.message, contains('stop'));
      expect(result.logs.single.message, 'before');
    },
  );
  test('completed named tests survive a later uncaught source error', () async {
    final result = await run(
      "gm.test('done', () => gm.expect(1).to.equal(1)); "
      "console.log('before'); throw Error('stop');",
    );
    expect(result.error?.message, contains('stop'));
    expect(result.tests.single.name, 'done');
    expect(result.tests.single.passed, isTrue);
    expect(result.logs.single.message, 'before');
  });

  test('async named tests finish in order before the stage resolves', () async {
    final result = await run('''
      let order = '';
      gm.test('first', async () => {
        await Promise.resolve();
        order += 'a';
      });
      gm.test('second', () => {
        gm.expect(order).to.equal('a');
        order += 'b';
      });
      gm.test('third', async () => {
        await Promise.resolve();
        gm.expect(order).to.equal('ab');
      });
    ''');
    expect(result.error, isNull);
    expect(result.tests.map((test) => test.name), ['first', 'second', 'third']);
    expect(result.tests.every((test) => test.passed), isTrue);
  });
  for (final insideTest in [false, true]) {
    test(
      'real heap exhaustion is fatal with test wrapper $insideTest',
      () async {
        const allocate = 'new ArrayBuffer(8 * 1024 * 1024);';
        final result = await run(
          insideTest
              ? 'gm.test("heap",()=>{$allocate}); '
                    'gm.variables.set("partial","yes");'
              : allocate,
          limits: const ScriptLimits(
            memoryBytes: 2 * 1024 * 1024,
            timeout: Duration(seconds: 2),
          ),
        );
        expect(
          result.error?.kind,
          ScriptErrorKind.memoryLimit,
          reason: result.error?.message,
        );
        expect(result.temporaryVariables, isEmpty);
        expect((await run('gm.test("healthy",()=>{});')).error, isNull);
      },
    );
  }
  for (final memory in [false, true]) {
    test(
      'fatal resource failure preserves completed diagnostics memory=$memory',
      () async {
        final failure = memory
            ? 'new ArrayBuffer(8 * 1024 * 1024);'
            : 'while(true) {}';
        final result = await run(
          "console.log('before'); gm.test('done',()=>{}); "
          'gm.variables.set("pending","discard"); $failure',
          limits: ScriptLimits(
            timeout: const Duration(milliseconds: 150),
            memoryBytes: memory ? 2 * 1024 * 1024 : 32 * 1024 * 1024,
          ),
        );
        expect(
          result.error?.kind,
          memory ? ScriptErrorKind.memoryLimit : ScriptErrorKind.timeout,
        );
        expect(result.tests.single.name, 'done');
        expect(result.tests.single.passed, isTrue);
        expect(result.logs.single.message, 'before');
        expect(result.temporaryVariables, isEmpty);
        expect(result.environmentPatch.isEmpty, isTrue);
        expect(result.requestPatch.isEmpty, isTrue);
      },
    );
  }
  test(
    'fatal diagnostics capability stays private and skips user toJSON',
    () async {
      final result = await run("""
      if (typeof globalThis.__getmanDiagnosticSink !== 'undefined') {
        throw Error('diagnostic capability leaked');
      }
      Object.prototype.toJSON = () => { throw Error('user toJSON ran'); };
      Array.prototype.toJSON = () => { throw Error('array toJSON ran'); };
      JSON.stringify = () => { throw Error('user stringify ran'); };
      console.log('safe');
      gm.test('completed',()=>{});
      while(true) {}
    """, limits: const ScriptLimits(timeout: Duration(milliseconds: 150)));
      expect(result.error?.kind, ScriptErrorKind.timeout);
      expect(result.tests.single.name, 'completed');
      expect(result.logs.single.message, 'safe');
    },
  );
  test(
    'nested async tests drain their final tail before stage completion',
    () async {
      final result = await run("""
      gm.test('outer',async()=>{
        for(let i=0;i<5;i++) await Promise.resolve();
        gm.test('inner',async()=>{
          for(let i=0;i<5;i++) await Promise.resolve();
          throw Error('inner failed');
        });
      });
    """);
      expect(result.error, isNull);
      expect(result.tests.map((test) => test.name), ['outer', 'inner']);
      expect(result.tests.map((test) => test.passed), [true, false]);
      expect(result.tests.last.message, contains('inner failed'));
    },
  );

  test(
    'immediately nested async callbacks are not overwritten by outer tail',
    () async {
      final result = await run("""
      gm.test('outer',async()=>{
        gm.test('inner',async()=>{
          for(let i=0;i<15;i++) await Promise.resolve();
          throw Error('immediate inner failed');
        });
        for(let i=0;i<5;i++) await Promise.resolve();
      });
    """);
      expect(result.tests.map((test) => test.name), ['outer', 'inner']);
      expect(result.tests.map((test) => test.passed), [true, false]);
    },
  );
}
