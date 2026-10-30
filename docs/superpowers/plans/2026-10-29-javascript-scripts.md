# JavaScript Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. O método de execução será escolhido ao iniciar a implementação; este documento não inicia agentes nem altera o produto.

**Goal:** Substituir Rules por JavaScript pré/pós-requisição, com variáveis, JWT, testes e console, mantendo o Getman leve e cobrindo cada incremento com TDD.

**Architecture:** Engine QuickJS encapsulada em repositório abstrato, com isolate nativo e Worker/WASM web. Scripts pertencem à configuração da request; um use case coordena execução, HTTP e patches confirmados de ambiente, preservando identidade/cancelamento. UI e resultados permanecem separados do runtime.

**Tech Stack:** Flutter 3.44.4 via FVM, Dart ^3.12.0, flutter_bloc/Equatable, Hive CE, re_editor/re_highlight, QuickJS/QuickJS-NG, flutter_test/bloc_test, integration_test/patrol_finders.

**Spec:** [2026-10-29-javascript-scripts-design.md](../specs/2026-10-29-javascript-scripts-design.md). Ler ambos antes de executar.

## Global Constraints

- **Não implementar migração de Rules.** Remover o mecanismo antigo; typeIds 7, 8 e 9 ficam aposentados. Não converter dados, abrir ou apagar automaticamente a box antiga.
- Desktop macOS/Windows/Linux e web: mesmos contratos observáveis, artefatos embarcados e execução offline.
- Scripts por requisição HTTP; WS/SSE/MCP não executam esses hooks. Sem npm, Node, fetch, módulos externos, scripts herdados, JWT signing ou promessa de compatibilidade `pm.*` nesta entrega.
- Limites: 1.000 ms por etapa; heap JS 32 MiB; source 256 KiB; input 8 MiB; output 1 MiB; console 200 entradas/64 KiB; 200 testes; duas execuções simultâneas.
- Executar sempre `fvm flutter` / `fvm dart`. Domínio puro, BLoCs dependem de repositórios abstratos, DI somente em DI/main, imports package, entidades/eventos/estados Equatable, entidades com copyWith.
- Adicionar headers de arquivos, entradas no CODEMAP e tokens de tema quando necessários. Nenhum acesso a GetIt em widgets, engine em BLoCs ou hardcode de estilo.
- Histórico guarda request template com source original. Patches do script não editam automaticamente o texto salvo. Confiança/logs/resultados não entram no workspace exportado.
- Registrar RED e GREEN por comportamento. Testes que passam imediatamente são caracterização, não prova de TDD de uma feature nova.
- Novo campo Hive previsto: 19 de typeId 1; verificar ledger antes de editar, nunca reutilizar campo/typeId. Regenerar adapters com FVM.
- Nenhum script é executado ao abrir editor, gerar código, importar, exportar, fazer diff ou salvar.

## Review Focus

1. Reenviar/fechar aba ou trocar/excluir ambiente durante JS: resultado atrasado não pode contaminar aba/ambiente (tarefas 7–9, 14).
2. Loop infinito, promise pendente e heap excessivo: engine realmente interrompida e próxima execução funcional, não apenas Future expirado (2–3, 14).
3. Requests iguais que diferem somente em script: dirty tracking, histórico, cópia e Git preservam a distinção (6, 12, 14).
4. Erro pré-HTTP e erro pós-HTTP: primeiro não envia; segundo preserva resposta e não confirma patches parciais (9, 11, 14).
5. Conteúdo vindo de Git/importação: não executar automaticamente, não perder source nem anunciar compatibilidade Postman inexistente (8, 12, 14).

## Preparação, inventário e disciplina TDD

Antes da primeira alteração, ler `docs/CODEMAP.md` e as arquiteturas `testing`, `tabs-and-panels`, `environments-and-chaining`, `persistence-hive`, `app-shell`, `theming`, `collections`, `git-sync`, `network-and-cookies` e `settings-history-updates`. Verificar `git status` e trabalhar numa branch/worktree isolada conforme a skill; não sobrepor alterações do usuário.

O projeto estava limpo durante este planejamento. Não há resultados de testes da implementação: nenhum código foi implementado/executado para este plano.

Rodar os gates atuais antes de editar para conhecer a linha de base. Registrar falhas preexistentes por nome; não atribuí-las à feature nem escondê-las. Reexecutar os quatro linters, formatter e suite completa antes de cada commit de implementação, conforme os mandatos do projeto. As tarefas abaixo também indicam testes focados para o ciclo curto.

Cada caso listado em uma tarefa é um incremento separado:

```text
escrever um teste → executar e observar falha pelo comportamento ausente
→ implementar o mínimo → executar e observar sucesso
→ refatorar com testes verdes → verificar regressões → commit da tarefa
```

Não escrever todos os testes depois do código. Não adicionar casos artificiais para documentação/configuração: nesses passos, a evidência é executar os contratos e gates reais que dependem da alteração.

## Mapa de arquivos e contratos

Arquivos propostos são novos, salvo os marcados como existentes nas tarefas. Cada diretório novo em lib recebe entrada no CODEMAP. Usar arquivos pequenos; não inserir engine ou bridge dentro de `tabs_bloc.dart`.

| Local | Responsabilidade |
|---|---|
| `lib/core/domain/entities/request_scripts.dart` | Bundle v1 compartilhado pelas features de tabs/collections/history. |
| `lib/features/scripting/domain/entities/` | `script_input.dart`, `script_output.dart`, `script_error.dart`, `script_limits.dart`, `script_patch.dart`, `script_test_result.dart`, `script_log_entry.dart`, `script_response.dart`. |
| `lib/features/scripting/domain/repositories/` | `script_runtime_repository.dart`, `script_trust_repository.dart`. |
| `lib/features/scripting/domain/logic/` | `script_cancellation.dart`, `script_execution_registry.dart`, `script_output_validator.dart`, `script_diagnostic_redactor.dart`. |
| `lib/features/scripting/data/runtime/` | `script_runtime_factory.dart`, `quickjs_runtime_io.dart`, `quickjs_runtime_web.dart`, `script_worker_protocol.dart`, `script_runtime_pool.dart`. |
| `lib/features/scripting/data/repositories/script_runtime_repository_impl.dart` | Adapter do contrato de domínio, bridge e erros normalizados. |
| `lib/features/scripting/data/repositories/script_trust_repository_impl.dart` | Confiança local por identidade/digest, sem campo compartilhável. |
| `assets/scripting/` | `gm_bootstrap.js`, `gm_helpers.js`, `gm_expect.js`, `gm_console.js`, `quickjs_worker.js`, WASM/bundle gerados, licenças. |
| `lib/features/tabs/domain/usecases/execute_request_use_case.dart` | Pré-script → HTTP/histórico existente → pós-script → resultados/commit. |
| `lib/features/scripting/presentation/widgets/` | `scripts_tab_view.dart`, `script_code_editor.dart`, `script_console_view.dart`, `script_help_view.dart`, `script_trust_banner.dart`. |
| `lib/features/scripting/domain/logic/script_snippets.dart` | Catálogo de exemplos de uso, sem dependência de widgets. |
| `tool/scripting/` | Rebuild verificável de assets/engine, manifest de versões/hashes e benchmark. |
| `test/features/scripting/` | Domínio, runtime real, bridge, snippets, confiança e widgets. |
| `integration_test/fixtures/scripts/` | Corpus JS real, manifest JSON e resultados esperados, usado também pelos contratos. |

Interfaces a estabelecer na tarefa 1, mantidas nas demais:

```dart
enum ScriptPhase { preRequest, postResponse }

abstract class ScriptRuntimeRepository {
  Future<ScriptOutput> execute(
    ScriptInput input, {
    required ScriptCancellation cancellation,
    ScriptLimits limits = const ScriptLimits(),
  });
  Future<void> close();
}

abstract class ScriptTrustRepository {
  Future<bool> isTrusted(String configId, RequestScripts scripts);
  Future<void> trust(String configId, RequestScripts scripts);
}
```

`ScriptInput`: executionId/tabId/source/phase, config snapshot, environmentId nullable, environmentVariables, collectionVariables, temporaryVariables e response nullable. Mapas imutáveis. `ScriptResponse`: status, durationMs, text e headers; não inclui arquivos/handles/bytes binários. `ScriptPatch`: sets `Map<String,String>` e unsets `Set<String>`; rejeitar chave nos dois. `ScriptOutput`: temporárias, environmentPatch, requestPatch validado, tests, logs, error nullable e duration. RequestPatch tem url/method/body opcionais, headerSets/headerUnsets; é proibido na etapa post. `ScriptError`: kind, message, phase, line/column nullable; kinds incluem syntax/runtime/timeout/cancelled/memoryLimit/inputTooLarge/outputTooLarge/unsupportedApi/untrusted/persistence. `ScriptCancellation.cancel()` é idempotente e notifica o adapter; não atravessa isolate como objeto vivo.

Helpers **somente de teste**, criados junto do primeiro teste que os usa:

```dart
// test/features/scripting/support/script_fixtures.dart
ScriptInput scriptInput({
  required String source,
  ScriptPhase phase = ScriptPhase.preRequest,
  String executionId = 'run-1',
  String tabId = 'tab-1',
  String? environmentId = 'env-1',
  Map<String, String> environmentVariables = const {},
  Map<String, String> collectionVariables = const {},
  Map<String, String> temporaryVariables = const {},
  ScriptResponse? response,
});
// Constrói ScriptInput com config HTTP raw fixa, sem defaults de teste em lib.

// test/features/scripting/support/runtime_fixture.dart
Future<ScriptRuntimeRepository> createRealRuntime();
// Usa factory real. Não substitui evaluate por um fake.
```

Nos exemplos abaixo, `runtime` é criado por `createRealRuntime` no setUp e fechado no tearDown; `cancel` é novo ScriptCancellation por teste. Exemplos mostram o caso inicial de cada ciclo; implementar todos os casos enumerados, não apenas o trecho ilustrativo.

## Tarefa 1 — Contratos de domínio e defaults sem runtime

**Depende de:** preparação. **Arquivos:** criar RequestScripts e os arquivos de domínio do mapa; testes em `test/features/scripting/domain/`; atualizar CODEMAP.

**Consome:** HttpRequestConfigEntity. **Produz:** contratos acima, `RequestScripts` com source/habilitação por etapa e `isEmpty`; `ScriptLimits` com os valores exatos da spec.

- [ ] **RED:** testar defaults vazios, igualdade/copyWith de todos os campos, imutabilidade de mapas/listas e cancel idempotente. Primeiro caso:

```dart
test('source diferente altera a identidade do bundle', () {
  const before = RequestScripts();
  final after = before.copyWith(preRequest: 'const n = 1;');
  expect(after, isNot(before));
  expect(before.preRequest, isEmpty);
  expect(after.apiVersion, 1);
});
```

- [ ] Executar `fvm flutter test test/features/scripting/domain`; corrigir erros de harness e observar RED por contrato ausente antes de implementar comportamento.
- [ ] **GREEN:** implementar value objects Equatable/copyWith e cópias defensivas. Imutabilidade segue `Map.unmodifiable(values)` / `List.unmodifiable(values)`. Cancellation notifica uma única vez, inclusive inscrição tardia. Não importar Flutter/Hive/FFI.
- [ ] **REFACTOR:** repetir comando; adicionar casos de props completo e mutação indireta. Gates globais; commit `feat: define script execution contracts`.

## Tarefa 2 — Runtime nativo real, interrupção e descarte

**Depende de:** 1. **Arquivos:** runtime io/factory/pool/protocol e repository impl do mapa; `pubspec.yaml`/lock; `test/features/scripting/runtime/native_runtime_test.dart`; `tool/scripting/runtime-manifest.json`; `docs/architecture/scripting.md`. Bridge própria, se necessária: `native/scripting/quickjs_bridge.c` e integração de build em macOS/Windows/Linux.

**Consome:** execute/cancellation/limits. **Produz:** `createRealRuntime()`, execução em isolate e código JS real, resultado/erro normalizado e disposal. Inicialmente testar linguagem/erro sem depender da API gm completa.

- [ ] **RED:** contrato de linguagem, erro com linha, `while(true){}`, alocação acima da quota, cancelamento em execução e na fila, duas execuções concorrentes, terceira enfileirada, execução posterior saudável. Exemplo:

```dart
test('interrompe loop e permite a próxima execução', () async {
  final failed = await runtime.execute(
    scriptInput(source: 'while (true) {}'),
    cancellation: ScriptCancellation(),
    limits: const ScriptLimits(timeout: Duration(milliseconds: 50)),
  );
  expect(failed.error?.kind, ScriptErrorKind.timeout);
  final next = await runtime.execute(
    scriptInput(source: 'const answer = 6 * 7;'),
    cancellation: ScriptCancellation(),
  );
  expect(next.error, isNull);
});
```

- [ ] Rodar `fvm flutter test test/features/scripting/runtime/native_runtime_test.dart`. Se o binding só puder carregar em app compilado, hospedar o mesmo contrato em `integration_test/flows/scripts_runtime_test.dart` e rodar com `-d macos`; não simular a engine para obter verde.
- [ ] **GREEN:** validar `quickjs_engine` 0.1.6 com timeout via interrupt hook nativo, memory limit e isolate; rejeitar binding sem esses controles. Nesse caso, implementar bridge mínima com `JS_NewRuntime`, `JS_SetMemoryLimit`, `JS_SetMaxStackSize`, `JS_SetInterruptHandler`, eval/execute-pending-job e free de todos os handles. O interrupt hook compara deadline monotônico e flag atômica de cancelamento, sem callback Dart reentrante bloqueado no FFI.

```c
static int should_interrupt(JSRuntime *rt, void *opaque) {
  ScriptRunControl *control = opaque;
  return atomic_load(&control->cancelled) ||
         monotonic_millis() >= control->deadline_ms;
}
```

`ScriptRunControl` pertence à bridge: deadline inteiro + atomic bool, alocado por execução; `monotonic_millis` usa relógio monotônico específico da plataforma. Confirmar via código/teste que a bridge candidata tem mecanismo equivalente, sem copiar este trecho sem seus donos de memória.
- [ ] Validar async wrapper e microtask pump com `await Promise.resolve(42)` e `await new Promise(() => {})`. SourceURL virtual com fase; descontar linhas do wrapper na mensagem.
- [ ] **REFACTOR:** factory condicional, runtime criado sob demanda; teste de nenhum runtime para scripts vazios e zero handles/workers após close. Registrar versão/hashes/licenças, build de cada desktop e benchmark basal no documento de arquitetura. Gates; commit `feat: run bounded JavaScript off the UI isolate`.

## Tarefa 3 — Runtime web com WASM dentro de Worker

**Depende de:** 2. **Arquivos:** `quickjs_runtime_web.dart`, `assets/scripting/quickjs_worker.js`, `tool/scripting/package.json`, lock npm, script de bundle, manifest; `test/features/scripting/runtime/web_runtime_test.dart`; pipeline `.github/workflows/pages.yml`.

**Consome/produz:** mesmo ScriptRuntimeRepository e contrato de resultados. Build tooling npm não significa npm exposto ao usuário.

- [ ] **RED:** executar o mesmo corpus de linguagem, limites, cancelamento e recovery no navegador; verificar que `typeof fetch`, `typeof document`, `typeof localStorage` e `typeof process` no guest são `undefined`. Testar offline, base href não raiz, asset ausente, fila cancelada e erro de Worker.

```dart
test('guest não recebe APIs do worker hospedeiro', () async {
  final result = await runtime.execute(scriptInput(source: '''
    if (typeof fetch !== 'undefined' || typeof document !== 'undefined') {
      throw new Error('host capability leaked');
    }
  '''), cancellation: ScriptCancellation());
  expect(result.error, isNull);
});
```

- [ ] Rodar `fvm flutter test --platform chrome test/features/scripting/runtime/web_runtime_test.dart`; configurar o bootstrap de assets no harness de teste, sem acesso a CDN.
- [ ] **GREEN:** bundle local de QuickJS WASM por dependência travada (`quickjs-emscripten` é candidato), guest isolado, input/output apenas JSON, deadline no engine e watchdog host que termina worker como defesa adicional. Worker recebe somente schema validado de execução/cancelamento.

```javascript
// No hospedeiro do Worker; userSource nunca é passado a eval do navegador.
const result = context.evalCode(userSource, sourceUrl);
// Liberar result/context/runtime em finally e drenar pending jobs com deadline.
```

- [ ] **REFACTOR:** submeter os dois adapters ao mesmo corpus esperado, registrar versões efetivas e comandos reproduzíveis de assets. Build `fvm flutter build web`; contratos Chrome; gates; commit `feat: execute scripts in a bounded web worker`.

## Tarefa 4 — API gm: variáveis, request/response, JWT e helpers

**Depende de:** 1–3. **Arquivos:** `assets/scripting/gm_bootstrap.js`, `gm_helpers.js`, `script_output_validator.dart`; `test/features/scripting/runtime/script_api_test.dart`; `test/features/scripting/domain/script_output_validator_test.dart`; fixture JWT em `integration_test/fixtures/scripts/`.

**Consome:** snapshots do ScriptInput. **Produz:** gm v1 conforme tabela da spec; output com overlays/patches sem efeitos externos durante evaluate.

- [ ] **RED:** JWT com claim de sessão, Unicode e padding omitido; JWT inválido/JWE; Base64 inválido; collection→env→temporary; ausência/null; JSONPath root/arrays/chaves escapadas; header case-insensitive; método inválido; mutação em pós-script; setBody em multipart; env ausente; BigInt/ciclo/undefined; output excessivo e tentativa de forjar envelope.

```dart
test('claim JWT torna-se variável temporária', () async {
  final payload = base64Url.encode(utf8.encode(
    '{"session":{"id":"sessão-42"}}',
  )).replaceAll('=', '');
  final result = await runtime.execute(scriptInput(
    environmentVariables: {'token': 'eyJhbGciOiJIUzI1NiJ9.$payload.sig'},
    source: '''
      const claims = gm.jwt.decode(gm.variables.get('token'));
      gm.variables.set('session_id', claims.session.id);
    ''',
  ), cancellation: ScriptCancellation());
  expect(result.temporaryVariables['session_id'], 'sessão-42');
  expect(result.environmentPatch.sets, isEmpty);
});
```

- [ ] Rodar `fvm flutter test test/features/scripting/runtime/script_api_test.dart test/features/scripting/domain/script_output_validator_test.dart` e equivalente Chrome do contrato real.
- [ ] **GREEN:** serializar snapshots como dados; criar Maps sem prototype para nomes como `__proto__`; gerar patches ao fim da execução. Normalização explícita:

```javascript
function variableText(value) {
  if (typeof value === 'string') return value;
  if (value === undefined || typeof value === 'bigint' ||
      typeof value === 'function' || typeof value === 'symbol') {
    throw new TypeError('Variable value must be JSON-compatible');
  }
  // validateJsonValue percorre arrays/objetos, rejeita ciclos e não finitos.
  validateJsonValue(value);
  return JSON.stringify(value);
}
```

Implementar `validateJsonValue` neste mesmo arquivo e testá-lo com NaN/Infinity e objetos aninhados; não confiar só em JSON.stringify, que converte NaN para null. Adaptar semântica de JsonPath existente com corpus compartilhado; não manter dependência da feature chaining.
- [ ] **REFACTOR:** validar schema/limites do output no Dart também, preservar secrets metadata e restringir APIs por fase. Gates; commit `feat: expose request variables and JWT helpers to scripts`.

## Tarefa 5 — Testes nomeados, expect e console

**Depende de:** 4. **Arquivos:** `assets/scripting/gm_expect.js`, `gm_console.js`; `script_diagnostic_redactor.dart`; `test/features/scripting/runtime/script_tests_test.dart`, `script_console_test.dart`; `test/features/scripting/domain/script_diagnostic_redactor_test.dart`.

**Consome:** gm bootstrap/output. **Produz:** ScriptTestResult/ScriptLogEntry com executionId/phase, ordem, mensagens, erro/stack e bounds da spec.

- [ ] **RED:** passar/falhar/continuar; nomes duplicados; callback async; erro fora de teste; cada comparator da spec; strict/deep equality; null versus ausente; limite de testes; console circular/Unicode/truncado; secrets na mensagem/stack e em novo valor de chave secreta.

```dart
test('falha de assertion não impede o próximo teste', () async {
  final result = await runtime.execute(scriptInput(source: '''
    gm.test('falha', () => gm.expect(500).to.equal(200));
    gm.test('passa', async () => {
      gm.expect(await Promise.resolve('ok')).to.equal('ok');
    });
  '''), cancellation: ScriptCancellation());
  expect(result.tests.map((t) => t.passed), [false, true]);
  expect(result.error, isNull);
});
```

- [ ] Rodar `fvm flutter test test/features/scripting/runtime/script_tests_test.dart test/features/scripting/runtime/script_console_test.dart test/features/scripting/domain/script_diagnostic_redactor_test.dart`.
- [ ] **GREEN:** registrar testes e executar sequencialmente com await; capturar erro dentro do callback como reprovação. Console usa serializador limitado resistente a ciclos; redator no host antes de exibir qualquer diagnostic, sem logging bruto em dart:developer.

```javascript
for (const test of registeredTests) {
  try {
    await test.callback();
    appendTestResult(test.id, test.name, true, null);
  } catch (error) {
    appendTestResult(test.id, test.name, false, formatError(error));
  }
}
```

`registeredTests`, `appendTestResult` e `formatError` são privados de gm_expect/bootstrap e possuem testes reais; deadline global continua ativo durante o loop.
- [ ] **REFACTOR:** resultados parciais disponíveis em erro posterior; nenhuma alteração de ambiente confirmada pelo bootstrap. Corpus real nos dois adapters; gates; commit `feat: collect script tests and bounded console output`.

## Tarefa 6 — Scripts na request, Hive e ciclo de edição

**Depende de:** 1. **Arquivos existentes:** `lib/core/domain/entities/request_config_entity.dart`, `lib/features/history/data/models/request_config_model.dart` e adapter gerado, `lib/features/tabs/domain/entities/request_tab_entity.dart`, `lib/features/home/domain/usecases/tab_dirty_checker.dart`, conversões JSON/copy no mesmo fluxo; ledger `docs/architecture/persistence-hive.md`. Testes: `test/core/domain/entities/request_config_entity_test.dart`, `test/features/history/data/models/request_config_model_test.dart`, `test/features/tabs/save_collectionless_request_dirty_test.dart` e novo `test/features/scripting/persistence/script_request_lifecycle_test.dart`.

**Consome:** RequestScripts. **Produz:** config.scripts default vazio, HiveField19 mapa, igualdade/dedup/clone/round-trip completos.

- [ ] **RED:** registro antigo sem campo; restart Hive real em temp dir; scripts vazios; disabled; versão desconhecida preservada; mudança só no source marca dirty; Save/Revert; duplicate com novo id e mesmo source; histórico distingue scripts; exemplos; fechar/reabrir aba; flush no exit.

```dart
test('scripts fazem parte da assinatura de histórico', () {
  final a = HttpRequestConfigEntity(id: 'a');
  final b = a.copyWith(scripts: const RequestScripts(
    preRequest: 'gm.variables.set("x", "1");',
  ));
  expect(HttpRequestConfig.fromEntity(a),
      isNot(HttpRequestConfig.fromEntity(b)));
});
```

- [ ] Rodar os arquivos de teste listados e observar RED; criar fixture binária de registro antigo usando schema de campos 0–18, sem depender do novo serializer para produzir o dado legado.
- [ ] **GREEN:** `@HiveField(19) Map<String, dynamic>? scripts;` com conversão restrita ao bundle, default vazio e preservação de versão desconhecida. Incluir source/enabled/version em igualdade/hash/copyWith. Não incluir logs/resultados em assinatura nem na persistência de config.
- [ ] Regenerar com `fvm dart run build_runner build --delete-conflicting-outputs`; inspecionar diff gerado. **REFACTOR:** rodar testes de lifecycle + modelos + tabs/history/collections; gates; commit `feat: persist scripts with request configurations`.

## Tarefa 7 — Patches de ambiente confirmados e observáveis

**Depende de:** 1. **Arquivos existentes:** `features/environments/domain/repositories/environments_repository.dart`, usecases, data repository/local data source e EnvironmentsBloc/event/state. Novos testes `test/features/environments/data/script_environment_patch_test.dart` e `test/features/environments/presentation/bloc/environment_external_changes_test.dart`.

**Consome:** ScriptPatch. **Produz:** no repositório, `Future<void> applyVariablePatch(String environmentId, ScriptPatch patch)` e `Stream<List<EnvironmentEntity>> watchEnvironments()`. Serializar todas as mutações de ambiente, incluindo editor/import/delete, contra o estado vivo.

- [ ] **RED:** patches concorrentes em campos diferentes; mesma chave segue ordem admitida; unset; secret flags preservadas/prunadas corretamente; ambiente ausente não recria; falha de escrita é propagada; watcher atualiza Bloc/editor; delete concorrente; não perder edição comum contra script.

```dart
test('patches independentes não sobrescrevem outras variáveis', () async {
  await Future.wait([
    repository.applyVariablePatch('env-1',
        ScriptPatch(sets: {'token': 'abc'})),
    repository.applyVariablePatch('env-1',
        ScriptPatch(sets: {'session': '42'})),
  ]);
  final env = (await repository.getEnvironments()).single;
  expect(env.variables, containsPair('token', 'abc'));
  expect(env.variables, containsPair('session', '42'));
});
```

`repository` usa Hive real temporário inicializado com env-1; um fake de storage que falha serve apenas para testar propagação de falha.
- [ ] Rodar `fvm flutter test test/features/environments`; identificar RED nos novos contratos antes de implementar.
- [ ] **GREEN:** fila única de mutações no repositório; leitura dentro da seção serializada, merge e put; só completar Future após put. Bloc observa stream e não chama outro Bloc; cancelar subscription no close. Atualizar editor para preservar alterações locais ainda não enviadas quando watcher emitir.

```dart
final nextVariables = {...current.variables, ...patch.sets}
  ..removeWhere((key, _) => patch.unsets.contains(key));
// putEnvironment ocorre dentro da mesma fila, sem reentrar/enfileirar em si.
```

- [ ] **REFACTOR:** casos watcher inicial, emissão igual, editor aberto e disposal; gates; commit `feat: commit script variable patches without lost updates`.

## Tarefa 8 — Confiança local de scripts

**Depende de:** 1, 6. **Arquivos:** trust repository impl, `lib/core/storage/hive_boxes.dart`, `lib/core/di/injection_container.dart`, `script_trust_banner.dart`; novos `test/features/scripting/data/script_trust_repository_test.dart`, `test/features/scripting/presentation/script_trust_banner_test.dart`.

**Consome:** RequestScripts e configId. **Produz:** confiança por digest de versão/source, local à instalação. Habilitação não permite forjar confiança; source novo precisa de decisão local.

- [ ] **RED:** trusted source reabre; source modificado externamente falha; JSON `trusted:true` é ignorado; config distinta não herda; bundle vazio não exige; disabled não executa; aprovação específica do conteúdo mostrado; falha de persistência não marca trusted.

```dart
test('mudar source invalida confiança', () async {
  const scripts = RequestScripts(preRequest: 'const x = 1;');
  await trust.trust('request-1', scripts);
  expect(await trust.isTrusted('request-1', scripts), isTrue);
  expect(await trust.isTrusted('request-1',
    scripts.copyWith(preRequest: 'const x = 2;')), isFalse);
});
```

- [ ] Rodar os dois testes; **GREEN:** digest criptográfico sobre representação canônica (version + ambos os sources), usando dependência explicitamente declarada, e box primitiva local sem typeId. UI apresenta source antes de `TRUST SCRIPTS`; edição local aceita pelo usuário associa confiança ao conteúdo salvo, sem confiar em reload/import.
- [ ] **REFACTOR:** teste de corrida entre source exibido e alterado antes do clique: confiar somente no digest mostrado. Gates; commit `feat: require local trust for imported script content`.

## Tarefa 9 — Orquestração pré/HTTP/pós e cancelamento

**Depende de:** 2–8. **Arquivos:** novo `execute_request_use_case.dart` e `execute_request_result.dart` no domínio de tabs; execution registry do mapa; existentes `send_request_use_case.dart`, `tabs_repository_impl.dart`, `tabs_bloc.dart`, `tabs_event.dart`, `request_manager.dart`, `url_bar.dart`, `main_screen.dart`, DI; testes `test/features/tabs/domain/usecases/execute_request_use_case_test.dart`, `test/features/tabs/presentation/bloc/script_execution_test.dart`.

**Interfaces:** `ExecuteRequestUseCase.call({required String executionId, required String tabId, required HttpRequestConfigEntity config, required ScriptVariableSnapshot variables, required ScriptCancellation cancellation, NetworkCancelHandle? cancelHandle}) → Future<ExecuteRequestResult>`; snapshot contém environmentId, mapas separados coleção/ambiente e secretKeys. Resultado contém response nullable, `preRequest`/`postResponse` (ScriptOutput nullable), error nullable e bool cancelled; construtor `ExecuteRequestResult.cancelled()` fixa cancelled=true, sem novos efeitos. Criar `script_variable_snapshot.dart` junto do contrato.

- [ ] **RED:** request sem scripts conserva o comportamento; pré transforma JWT/body/header antes da resolução; template/histórico intactos; pré erro/reprovação/persistência falha = zero HTTP; pós erro conserva resposta; pós assertion falha permite patch; 400/500 roda pós; DNS não roda; cancel/re-send/close em cada await; troca/exclusão de env; segunda request lê patch confirmado; source modificado durante send usa snapshot original.

```dart
test('pré-script com erro não chama HTTP', () async {
  final result = await harness.send(pre: 'throw new Error("stop");');
  expect(harness.networkCalls, 0);
  expect(result.preRequest?.error?.kind, ScriptErrorKind.runtime);
  expect(await harness.persistedVariables(), isEmpty);
});
```

Criar `test/features/tabs/support/script_execution_harness.dart`: `send({String pre='', String post=''})`, `networkCalls`, `persistedVariables()`, engine fake controlável por Completer para corridas, repo temporário e gateway HTTP gravador. Não usá-lo como substituto dos E2E reais da tarefa 14.
- [ ] Rodar `fvm flutter test test/features/tabs/domain/usecases/execute_request_use_case_test.dart test/features/tabs/presentation/bloc/script_execution_test.dart`.
- [ ] **GREEN:** use case coordena o fluxo da spec, e execução é identificada pelo registry. Estender SendRequestUseCase com parâmetro opcional `historyConfig` para registrar template original quando enviar cópia alterada; padrão preserva callers existentes. Merge temporário é usado na resolução pelo repositório, sem mudar EnvironmentResolver para interpretar código.

```dart
// Admissão síncrona antes da operação de persistência enfileirada.
if (!registry.isCurrent(tabId, executionId) || cancellation.isCancelled) {
  return const ExecuteRequestResult.cancelled();
}
await environmentsRepository.applyVariablePatch(environmentId, patch);
// Revalidar antes do próximo efeito/HTTP/publicação, sem prometer undo do put.
```

Registry registra/invalidates por tabId; resultado de Future nunca decide sozinho se ainda é atual. RequestManager mantém ownership até fim do pós e commits. Criar estado explícito de fase e limpar resultados no início de cada execução.
- [ ] EnvironmentsRepository não é chamado com ID lido de Settings depois do SEND. Atualizar todos os disparadores (botão, Enter, atalho) para o mesmo snapshot em vez de passar apenas envVars achatadas.
- [ ] **REFACTOR:** timers/clock controláveis, testar linearização de cancelamento antes/depois da admissão de commit; rodar testes atuais de send/cancel/history também. Gates; commit `feat: execute pre and post scripts in the request pipeline`.

## Tarefa 10 — Editor SCRIPTS e exemplos práticos

**Depende de:** 4–6, 8–9. **Arquivos:** widgets scripts/help/code editor e script_snippets; existentes `request_config_section.dart`, `unified_request_panel.dart`, `request_section_index.dart`, atalhos do code editor e extensões de tema; testes `test/features/scripting/presentation/scripts_tab_view_test.dart`, `script_editor_lifecycle_test.dart`, `test/features/tabs/presentation/widgets/request_section_offstage_sync_test.dart`, `request_section_index_test.dart`.

**Interfaces:** `ScriptsTabView({required String tabId})`; edições despacham UpdateTab por id com config.copyWith(scripts:...). Editor usa CodeLineEditingController; state de source vem da config, não de um segundo banco de scripts.

- [ ] **RED:** SCRIPTS no índice antes ocupado por Rules; pré/pós separados; toggle; dirty/save/revert; trocar aba sem misturar texto; seleção-only não altera config; texto externo enquanto offstage; first↔last e non-adjacent jump; layout compacto; tema; Ctrl/Cmd+S e Send preservados; snippet JWT inserido sem execução.

```dart
// Após editar a config da aba enquanto seu RequestView estava offstage:
await tester.pump();
expect(find.text('POST-RESPONSE').hitTestable(), findsOneWidget);
expect(find.byKey(const ValueKey('script_editor_post')).hitTestable(),
    findsOneWidget);
// Inspecionar o texto do CodeLineEditingController visível, não de outro editor.
```

- [ ] Rodar os quatro arquivos de widget acima. Não usar pumpAndSettle antes das assertions do primeiro frame.
- [ ] **GREEN:** substituir seção por SCRIPTS; subabas PRE-REQUEST/POST-RESPONSE; toggle ENABLED; highlight JavaScript; ajuda/snippets cobrindo JWT, captura de token, status, headers, JSONPath, regex e setBody com JSON.stringify. Tokens via context.app*; recriar TabController em sync offstage conforme padrão existente.
- [ ] **REFACTOR:** snippets exportados como catálogo puro e executados no corpus real, não apenas string goldens. Gates; commit `feat: edit request scripts in desktop and compact layouts`.

## Tarefa 11 — Resultados TESTS, CONSOLE e diagnósticos

**Depende de:** 5, 9–10. **Arquivos existentes:** `response_tests_view.dart`, `response_section.dart`, `unified_request_panel.dart`, `request_tab_entity.dart`; novo script_console_view; testes `test/features/scripting/presentation/script_results_test.dart`, `script_console_view_test.dart`.

**Consome:** ExecuteRequestResult por executionId. **Produz:** resultados visíveis antes/depois de HTTP; nenhum dado de execução em Hive, Git ou bug report automático.

- [ ] **RED:** resumo 1/2 passed, etapas distintas, nomes repetidos, log truncado, erro de syntax com linha clicável, timeout antes de resposta, response 200 + pós erro, segredo mascarado, aba em background, reset em reenvio e não reexibir resultados da execução antiga.

```dart
// Montar estado com erro PRE-REQUEST e response == null.
await tester.pump();
expect(find.text('PRE-REQUEST').hitTestable(), findsWidgets);
expect(find.textContaining('line 2').hitTestable(), findsOneWidget);
expect(find.textContaining('secret-token'), findsNothing);
```

- [ ] Rodar `fvm flutter test test/features/scripting/presentation/script_results_test.dart test/features/scripting/presentation/script_console_view_test.dart`.
- [ ] **GREEN:** TESTS mantém nomes/vereditos, CONSOLE mostra log/erros, clique em erro seleciona fase/posição no editor. Não condicionar painel inteiro à existência de response. Estados RUNNING PRE-REQUEST/POST-RESPONSE e CANCEL disponíveis; preservar métricas HTTP separadas do tempo do script.
- [ ] **REFACTOR:** buildWhen/listenWhen estreitos, payloads limitados, dispose durante execução, alternância de temas/resize e painel offstage. Gates; commit `feat: show script diagnostics and test results`.

## Tarefa 12 — Workspace, import/export, diff/merge e codegen

**Depende de:** 6, 8. **Arquivos existentes:** `workspace_collection_serializer.dart`, `postman_collection_mapper.dart`, `semantic_diff.dart`, `three_way_merge.dart`, import dialogs/coordinators e code_gen_service; testes existentes de workspace/postman/semantic/merge e novo `test/features/scripting/sharing/script_interchange_test.dart`.

**Consome:** config.scripts. **Produz:** `request.scripts` no workspace e `x-getman-scripts` na exportação Postman; confiança e resultados nunca serializados. Postman event externo é diagnóstico de import não suportado, atômico, com caminho do item.

- [ ] **RED:** round-trip vazio/nonempty/disabled/versão desconhecida; source Unicode e newline; modificar apenas pré versus apenas pós faz auto-merge; ambos modificam mesmo pré gera conflito; Git reload exige confiança no novo conteúdo; JSON confiável forjado não funciona; import com evento request/pasta/root aborta sem gravar parte da coleção; codegen nunca avalia scripts.

```dart
test('workspace preserva scripts sem exportar confiança', () {
  final json = WorkspaceCollectionSerializer.requestToJson(scriptedLeaf);
  final restored = WorkspaceCollectionSerializer.requestFromJson(json);
  expect(restored.config!.scripts, scriptedLeaf.config!.scripts);
  expect(jsonEncode(json), isNot(contains('trusted')));
  expect(jsonEncode(json), isNot(contains('scriptLogs')));
});
```

`scriptedLeaf` é CollectionNodeEntity de fixture com config.scripts e sem segredos reais. Acrescentar asserts por chave/schema para evitar depender apenas de busca textual.
- [ ] Rodar testes atuais em `test/core/utils/workspace`, `test/core/utils/postman`, `test/features/collections/domain/logic` e novo interchange.
- [ ] **GREEN:** omitir bundle vazio, preservar source exatamente; diff de source/enabled/version por campo; merge conforme _pick existente, sem concatenar JS. Validação de import ocorre antes de mutar CollectionsBloc; mensagem indica `Postman scripts are not supported` e caminhos. Extensão Getman round-trip funciona, porém source gm não vira event Postman.
- [ ] Codegen/export API docs mostra aviso `Scripts are not included in generated code` quando aplicável; não executa source para produzir um comando supostamente equivalente. Testar presença do aviso e que o runtime não foi criado.
- [ ] **REFACTOR:** testar reload Git com editor dirty, conflito resolvido e import legado sem scripts inalterado. Gates; commit `feat: preserve scripts across workspace and request sharing`.

## Tarefa 13 — Remover Rules e integrações antigas

**Depende de:** 9–12. **Arquivos:** remover `lib/features/chaining/` e testes exclusivamente dessa UI/engine; retirar dependências de main/DI/home/tabs e resposta; `hive_boxes.dart`; `assertion_result.dart`/`extraction_result.dart` se não houver consumidores fora do legado. Atualizar `integration_test/all_flows_test.dart` e substituir os fluxos chaining existentes pelos novos da tarefa 14, mantendo casos úteis.

**Consome:** feature Scripts funcional. **Produz:** um só mecanismo de automação; typeIds aposentados, nenhuma migração.

- [ ] **RED:** widgets não exibem RULES/ADD ASSERTION/ADD EXTRACTION; boot não abre requestRules; SEND não avalia engines legadas; árvore JSON não oferece ação antiga; existing profile sem scripts ainda envia normalmente.

```dart
await tester.pump();
expect(find.text('RULES'), findsNothing);
expect(find.text('SCRIPTS').hitTestable(), findsOneWidget);
expect(find.text('ADD EXTRACTION'), findsNothing);
```

- [ ] Rodar testes de boot, section index, response tree e Scripts; novos negativos devem falhar enquanto a UI/wiring legado existir.
- [ ] **GREEN:** remover RulesBloc/provider/listener/usecases/engines/modelos/adapters/registro/sweep, imports e thresholds exclusivos de compute de regras. Preservar JsonPath e quaisquer utilitários realmente compartilhados. Retirar ação Extract to {{var}} e aviso edit in RULES; não deixar botão sem efeito. Não apagar boxes antigas em disco nem reaproveitar typeIds.
- [ ] **REFACTOR:** `rg -n 'RulesBloc|RulesTabView|ChainingWriteBackListener|runRules|GetRequestRulesUseCase|ExtractionEngine|AssertionEngine' lib` deve retornar vazio. Referências históricas em docs/specs são permitidas. Converter cenários relevantes em testes de script antes de remover cobertura legada. Gates; commit `refactor: retire unused no-code request rules`.

## Tarefa 14 — Integração final com scripts reais e jornadas completas

**Depende de:** 1–13. **Arquivos novos:** `integration_test/flows/scripts_jwt_test.dart`, `scripts_tests_test.dart`, `scripts_lifecycle_test.dart`, `scripts_limits_test.dart`, `scripts_persistence_test.dart`; `integration_test/support/script_actions.dart`; fixtures abaixo. Modificar `support/mock_server.dart`, `support/app_harness.dart`, `all_flows_test.dart`, README e runners.

**Interfaces de teste:** `setScript(PatrolTester $, ScriptPhase phase, String source)` digita no editor visível; `waitForScriptCompletion(PatrolTester $, String executionId)` observa conclusão daquela execução, nunca status HTTP antigo; `loadScriptFixture(String name)` carrega asset compartilhado; `restartGetmanWithSameProfile(PatrolTester $)` remonta app/DI usando o diretório temporário do caso sem removê-lo antes. Registrar helpers em arquivos de suporte, sem hooks de teste em domínio.

**Regra:** utilizar app, motor, bridge, Dio e Hive reais. Único servidor é HTTP local hermético; nenhuma chamada a Postman, serviços públicos, token ou credencial real. Cada caso testa efeitos no servidor, persistência e UI, não só texto de console.

- [ ] **RED:** adicionar um cenário abaixo por vez, rodar seu flow e observar a falha esperada antes de corrigir qualquer gap. Se o cenário já passar por cobertura das tarefas anteriores, registrar como validação; qualquer comportamento novo descoberto exige teste unitário RED antes da correção.
- [ ] Criar corpus `.js` abaixo e `manifest.json` com phase/input/expected para reutilização em native/web. Assets de fixtures pertencem a harness de testes dedicado, não ao bundle release do produto; loader desktop lê diretório de fixtures e loader Chrome usa harness que o serve. Não duplicar source em strings divergentes.

**Fixture `jwt_session_pre.js`:**

```javascript
const claims = gm.jwt.decode(gm.variables.get('access_token'));
gm.variables.set('session_id', claims.session.id);
gm.request.headers.set('X-Session', claims.session.id);
gm.request.setBody(JSON.stringify({
  sessionId: claims.session.id,
  description: 'texto com "aspas" e acentuação'
}));
```

**Fixture `login_post.js`:**

```javascript
const body = gm.response.json();
gm.environment.set('access_token', body.token);
gm.test('Login retornou sucesso', () => {
  gm.expect(gm.response.status).to.equal(200);
});
gm.test('Resposta contém token', () => {
  gm.expect(body.token).to.be.a('string');
});
```

**Fixture `response_tests_post.js`:**

```javascript
gm.test('Status', () => gm.expect(gm.response.status).to.equal(200));
gm.test('Header', () => {
  gm.expect(gm.response.header('X-Trace')).to.equal('trace-42');
});
gm.test('Null existe', () => {
  gm.expect(gm.response.lookup('$.nullable').found).to.equal(true);
  gm.expect(gm.response.lookup('$.nullable').value).to.equal(null);
});
gm.test('Falha intencional', () => gm.expect(1).to.equal(2));
gm.test('Continua após falha', async () => {
  gm.expect(await Promise.resolve('ok')).to.equal('ok');
});
console.info('Resposta verificada');
```

**Fixture `extract_regex_post.js`:**

```javascript
const match = /a=(\w+)|b=(\w+)/.exec(gm.response.text());
if (match) gm.environment.set('capture', match[1] ?? match[2] ?? match[0]);
gm.environment.set('trace', gm.response.header('X-Trace'));
```

**Fixture `pre_failure.js`:**

```javascript
gm.environment.set('must_not_persist', 'pending');
throw new Error('Preparação interrompida');
```

**Fixture `post_failure.js`:**

```javascript
gm.environment.set('must_not_persist', 'pending');
gm.test('Executado antes do erro', () => gm.expect(1).to.equal(1));
throw new Error('Pós-processamento interrompido');
```

**Fixtures de limites, cada uma em seu arquivo:**

```javascript
// infinite_loop.js
while (true) {}
```

```javascript
// pending_promise.js
await new Promise(() => {});
```

```javascript
// memory_limit.js
const retained = [];
while (true) retained.push(new Array(8192).fill('payload'));
```

```javascript
// console_limit.js
const cycle = {}; cycle.self = cycle;
console.log(cycle);
for (let i = 0; i < 1000; i++) console.log('entrada', i);
```

Na quota de memória, usar configuração de teste com deadline suficiente para a quota disparar antes do tempo; exigir `memoryLimit`, não aceitar timeout como sucesso desse caso. No loop/promise, usar timeout curto injetado e watchdog externo do runner para matar processo travado, sem timeout excessivamente apertado que gere flakiness de CI.

| Jornada | Asserções obrigatórias |
|---|---|
| Login → JWT → outra request | Servidor retorna token sintético; pós salva; request seguinte usa token/claim; servidor recebeu body/header exatos, editor continua template. |
| JWT inválido/JWE/Unicode | Erro explícito antes de rede nos inválidos; Unicode preservado; assinatura não é validada pelo helper. |
| Testes pós-resposta | 4/5 PASSED, header e null corretos, erro do teste isolado, async concluído, console acessível. |
| Captura JSONPath/header/regex | Variáveis confirmadas no Hive e usadas na próxima request; ausência é diferente de null. |
| Pré-script falha | Contador HTTP continua zero; patch não persistiu; erro/linha visíveis sem resposta. |
| Pós-script falha | Resposta HTTP preservada; teste já executado visível; patch não persistiu. |
| 4xx/5xx e DNS | Pós executa com resposta 400/500; não executa quando não há resposta de rede. |
| Loop, promise, quota, logs | UI responde ao cancelamento; runtime é liberado; log limitado; próximo SEND passa. |
| Re-send/close/background | Segunda execução vence; fechar impede resultado tardio; mudar painel não perde resultado da aba original. |
| Troca/exclusão de ambiente | Patch vai para ID original, não para o novo; excluído não reaparece; erro de persistência visível. |
| Persistência/restart | Salvar, reiniciar perfil temporário, reabrir e executar; source/enabled intactos; histórico não contém payload resolvido. |
| Duplicate/revert/history | Novo id, source copiado; reverter restaura; replay usa source registrado e ambiente atual. |
| Confiança/Git/import | Source novo vindo de fora bloqueia SEND; TRUST permite; mudança invalida; nada executa durante import/diff. |
| Desktop/compact/offstage | Editor correto no primeiro frame após troca; resize preserva texto; atalhos funcionam. |

- [ ] **GREEN:** corrigir somente gaps reproduzidos por testes; registrar todos os novos flows no aggregator. Extender MockServer para responder por rota `/login` e `/echo`, sem dependências externas; usar `received` para validar método, header e JSON decodificado.
- [ ] Rodar, individualmente: `fvm flutter test integration_test/flows/scripts_jwt_test.dart -d macos`, depois os quatro flows restantes. Usar executionId/counters novos para não confundir resposta anterior com send atual.
- [ ] **REFACTOR:** executar `bash integration_test/run_macos.sh` com todos os flows; levar contrato de runtime e jornadas HTTP portáveis a Windows/Linux. Chrome roda corpus real no harness web com servidor local CORS, sem reutilizar dart:io dentro do navegador.
- [ ] Adicionar `test_driver/integration_test.dart` com `integrationDriver()` e runner web de testes que inicia servidor de fixture na máquina host, passa base URL por dart-define e inicia ChromeDriver compatível em porta 4444 (`chromedriver --port=4444`). Executar `fvm flutter drive --driver=test_driver/integration_test.dart --target=integration_test/web/scripts_web_test.dart -d web-server --browser-name=chrome`. Runner deve encerrar servidor/driver em finally, inclusive ao falhar. Separar helpers IO dos web e usar perfil/origem temporários para não tocar IndexedDB real. Seguir o [harness oficial de integração Flutter web](https://docs.flutter.dev/testing/integration-tests). Não alegar E2E web com apenas teste unitário Chrome.
- [ ] Gates; commit `test: cover real script execution end to end`.

## Tarefa 15 — Regressão completa, performance, documentação e release

**Depende de:** 1–14. **Arquivos:** `docs/architecture/scripting.md`, CODEMAP, routing table de CLAUDE.md, arquiteturas afetadas, BACKLOG (M9/DL2), README, `integration_test/README.md`, `.github/workflows/ci.yml`, `pages.yml`, `release.yml`; wiki externa; `tool/scripting/benchmark.dart` e manifest final de engine/assets.

- [ ] **TDD de regressão final:** executar o corpus completo; para cada defeito encontrado, adicionar primeiro teste unitário/widget que reproduza a causa, ver RED, corrigir e reexecutar o E2E. Não escrever testes que apenas procuram frases na documentação.
- [ ] **Performance:** medir release/profile na mesma máquina antes/depois: cold boot e send sem script (30 amostras após aquecimento apropriado), primeira execução, execuções seguintes, 500 sends com script, RSS/handles/workers e tamanho dos artefatos. Zero runtimes antes do primeiro script; sem crescimento de workers/handles após disposal. Definir alerta de regressão de p95 sem script acima de 10% em amostra repetida, investigar ruído antes de concluir; publicar valores reais e ambiente de medição. Não prometer números de performance não medidos.
- [ ] **Documentação:** API completa, snippets executáveis do corpus, limites, sem assinatura JWT, escopos/commit de variáveis, resposta versus falha de script, confiança e restrições de import/export. Remover instruções atuais de Rules. Marcar typeIds 7/8/9 retired e campo 19 utilizado; não anunciar migração.
- [ ] **Wiki:** clonar `https://github.com/thiagomiranda3/Getman.wiki.git` em diretório temporário de trabalho; inspecionar `_Sidebar.md`; atualizar páginas de requests/testes/variáveis/import-export com labels literais SCRIPTS/PRE-REQUEST/POST-RESPONSE/TESTS/CONSOLE; adicionar navegação necessária, commit e push em master junto da entrega. Não publicar durante a etapa atual de planejamento.
- [ ] **Gates obrigatórios, todos separados:**

```bash
fvm flutter analyze
fvm dart run custom_lint
(cd tools/getman_lints/example && fvm dart run custom_lint)
fvm dart run bloc_tools:bloc lint lib
fvm dart format --output=none --set-exit-if-changed lib test tools integration_test test_driver
fvm flutter test
bash integration_test/run_macos.sh
fvm flutter test --platform chrome test/features/scripting/runtime/web_runtime_test.dart
```

Após campo Hive modificado, também `fvm dart run build_runner build --delete-conflicting-outputs`, seguido de revisão de diff e testes. Formatar qualquer Dart novo em `tool/scripting` explicitamente. Gerar cobertura com `bash tool/coverage.sh`; cobertura complementa, não substitui, asserts de comportamento.

- [ ] **Matriz real:** build/test release nas runners correspondentes: `fvm flutter build macos --release`, `fvm flutter build windows --release`, `fvm flutter build linux --release`, `fvm flutter build web --release`; contratos de runtime reais em cada OS + jornadas de script. Inspecionar bundling/linkage/licenças e assets web offline. Registrar plataformas indisponíveis como não verificadas; não declarar a entrega multiplataforma concluída até a matriz passar.
- [ ] **Revisão final:** diff focado, nenhum uso legado em lib, nenhum secret de fixture real, todos os testes sem skip novo, sem mock no contrato de engine, estados/erros utilizáveis e wiki sincronizada. Commit `docs: document JavaScript scripting and verification`.

## Ordem de execução e critérios de conclusão

Executar 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 12 → 13 → 14 → 15. Dependências permitem trabalho independente em persistência, mas esse plano não exige paralelismo. A prova de engine vem cedo para não construir UI sobre um runtime que não consegue interromper scripts.

O marco intermediário útil é a tarefa 9: engine + API + persistência + pipeline verificados sem depender da interface nova. A entrega ao usuário só ocorre após remoção de Rules, jornadas reais, gates e documentação.

Checklist final:

- [ ] Usuário extrai sessão de JWT com script e servidor recebe payload correto.
- [ ] Scripts antes/depois e testes funcionam; Rules não existe mais na UI/execução.
- [ ] Nenhuma migração de Rules foi implementada.
- [ ] RED/GREEN registrado em cada incremento comportamental; exemplos da ajuda executam no corpus.
- [ ] Runtime não bloqueia UI; limites/cancelamento/recovery comprovados com JS real.
- [ ] Scripts sobrevivem save/restart/clone/history/Git sem exportar confiança/logs/resultados.
- [ ] Todos os linters, formatter, testes unitários/widgets, E2E e matriz de plataforma aprovados.
- [ ] Wiki e documentação técnica atualizadas com o comportamento efetivamente entregue.

## Handoff

Este plano e a spec são os artefatos da solicitação atual. Recomendo execução sequencial pelo agente na sessão, com revisão ao final, porque runtime, API e pipeline compartilham contratos sensíveis. Também é possível execução por subagentes, com revisão por tarefa, se escolhida pelo usuário. Não iniciar implementação apenas porque os documentos foram gravados.
