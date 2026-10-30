# JavaScript Scripts — desenho da implementação

Data: 2026-10-29. Estado: proposta para implementação; nenhum código de produto foi alterado para produzir este documento.

## Objetivo e decisões da conversa

Adicionar JavaScript antes e depois de requisições HTTP, para preparar dados (inclusive extrair uma sessão de um JWT), capturar variáveis e escrever testes. Substituir a configuração visual de Rules, mantendo uma visualização útil dos resultados dos testes.

**Não implementar migração de Rules.** O usuário confirmou que a feature nunca foi usada. Remover sua UI, engines, BLoC, modelos, repositórios e wiring. Não converter regras, criar backups, leitores de compatibilidade ou executar o código antigo em paralelo. Os typeIds Hive 7, 8 e 9 ficam aposentados e nunca serão reutilizados. A antiga box não será aberta nem apagada automaticamente: simplesmente deixa de participar do produto.

Este desenho acompanha o [plano de trabalho](../plans/2026-10-29-javascript-scripts.md). O pedido atual é planejar; executar o plano é uma etapa posterior.

## Escopo da entrega

- Scripts por requisição HTTP, com etapas `PRE-REQUEST` e `POST-RESPONSE`, API versionada `gm` v1 e habilitação independente por etapa.
- Preparação de variáveis, URL, método, headers e body textual; o caminho existente continua resolvendo auth e todos os tipos de body.
- Helpers JWT decode, Base64/Base64URL UTF-8 e JSONPath; extração por header e regex usando a linguagem.
- Assertions e testes nomeados, erros com etapa/linha/coluna e console limitado.
- Persistência, dirty tracking, save/revert/duplicate, histórico, exemplos, workspace Git, diff e merge.
- Desktop macOS/Windows/Linux e web: mesmos contratos observáveis, artefatos embarcados e execução offline.
- TDD em cada incremento; testes unitários, widgets, contrato com engine real e integração final com scripts reais.

Não faz parte desta entrega: runtime Node.js, npm no aplicativo, `require`, módulos externos, acesso a arquivos/shell/DOM, `fetch` ou requisições HTTP feitas pelo próprio script, assinatura/verificação criptográfica de JWT, scripts herdados de pasta/coleção, runner de coleções e compatibilidade completa com `pm.*`. Essas ausências devem constar da ajuda e dos testes de limites; não anunciar compatibilidade Postman que não existe. WS/SSE/MCP mantêm seus fluxos atuais e não executam scripts HTTP.

## Runtime e isolamento

Usar QuickJS/QuickJS-NG embarcado atrás de `ScriptRuntimeRepository`, sem dependência do engine no domínio/BLoC. Candidato nativo inicial: `quickjs_engine` 0.1.6, sujeito à prova de capacidades da tarefa 2. Se não expuser interrupção, quota de heap e execução em isolate, implementar bridge mínima própria sobre QuickJS-NG; não aceitar um pacote incapaz apenas para fechar a tarefa. Registrar versões, hashes e licenças realmente usados.

No desktop, criar runtime/contexto em isolate de trabalho, limitar a duas execuções simultâneas e descartar o contexto ao terminar cada etapa. Instanciar o engine somente quando houver script habilitado e não vazio. Cancelar trabalhos na fila antes de iniciar. Não executar código nativo síncrono no isolate da UI. Um timer Dart ou `Future.timeout` não constitui interrupção da engine.

No web, executar QuickJS em WASM dentro de Web Worker dedicado, carregado de assets locais; o programa do usuário roda no contexto QuickJS, nunca via `eval` do navegador ou do worker hospedeiro. O host não expõe `fetch`, DOM, storage ou mensagens arbitrárias ao guest. Um Worker sozinho não é uma sandbox de JavaScript do navegador. Validar os contratos entre engines; não pressupor a mesma versão interna de bibliotecas diferentes.

Limites iniciais, centralizados em `ScriptLimits`, sem novos ajustes de usuário nesta entrega:

| Recurso | Limite |
|---|---:|
| Tempo total de uma etapa, incluindo jobs de promises | 1.000 ms |
| Heap JavaScript por execução | 32 MiB |
| Source por etapa, UTF-8 | 256 KiB |
| Envelope de entrada serializado | 8 MiB |
| Envelope de saída serializado | 1 MiB |
| Console por etapa | 200 entradas e 64 KiB |
| Testes por etapa | 200 |
| Execuções simultâneas por aplicativo | 2 |

Excesso de source/input/output/memória/testes falha explicitamente; logs excedentes são truncados com indicação. Requisições sem script não herdam limites do engine. Resposta maior que o envelope continua visível, mas o pós-script apresenta `inputTooLarge` e não roda com dados truncados. O limite de heap não é uma promessa de limite de RSS do processo.

Suportar JavaScript moderno e `await` no corpo do script, encapsulado em função async. Drenar a fila de jobs até resolver/rejeitar, cancelar ou expirar o prazo. Promises que nunca resolvem falham pelo prazo. `gm.test` aceita callback síncrono ou async, executa na ordem de registro e só conclui a etapa depois dos callbacks. Erro de assertion dentro de teste gera resultado reprovado e permite os próximos testes; exceção fora de teste aborta a etapa.

## Contrato público JavaScript v1

| API | Contrato |
|---|---|
| `gm.variables.get(name)` / `has(name)` | Leitura da composição coleção → ambiente → temporárias; ausente retorna `undefined`. |
| `gm.variables.set(name, value)` / `unset(name)` | Overlay temporário da execução; `set` aceita string, boolean, número finito, null, array ou objeto JSON. Objetos usam JSON.stringify; strings permanecem strings. Rejeitar undefined, BigInt, ciclos e funções. `unset` retira o override temporário, revelando o valor inferior. |
| `gm.environment.get(name)` / `has(name)` | Snapshot do ambiente escolhido no SEND, incluindo alterações pendentes desta execução; não inclui variáveis de coleção. |
| `gm.environment.set(name, value)` / `unset(name)` | Patch persistente com a mesma conversão de valores; sem ambiente ativo gera erro explícito. Não guardar patches para um ambiente selecionado posteriormente. |
| `gm.request.url`, `.method`, `.body` | Snapshot textual da requisição; body é o template atual. |
| `gm.request.setUrl(text)`, `.setMethod(method)`, `.setBody(text)` | Somente PRE-REQUEST; alteram a cópia enviada, não o editor/histórico. Método validado contra `HttpMethods.all`. setBody permitido apenas para body raw; outros modos usam variáveis nos respectivos campos. |
| `gm.request.headers.get/set/unset` | Lookup case-insensitive; mutação somente PRE-REQUEST. Mantém precedência existente de auth e headers explícitos. |
| `gm.response.status`, `.durationMs`, `.text()`, `.json()`, `.header(name)` | Somente POST-RESPONSE; JSON inválido gera erro, headers case-insensitive, ausente retorna undefined. |
| `gm.response.lookup(path)` | `{found, value}` usando o subconjunto JSONPath já suportado no projeto; null existente é diferente de ausente. |
| `gm.jwt.decode(token)` | Decodifica payload de JWS compacto com três segmentos, Base64URL + UTF-8 + objeto JSON; não verifica assinatura nem validade temporal. JWE/malformado gera erro. |
| `gm.base64.encode/decode(text)` | UTF-8, alfabeto Base64 padrão; erro explícito em dados inválidos. |
| `gm.base64url.encode/decode(text)` | UTF-8, alfabeto URL-safe, aceita padding válido ou omitido. |
| `gm.test(name, callback)` | Registra teste; conserva ordem e nomes repetidos com ids de resultado distintos. |
| `gm.expect(value).to.equal(expected)` | Igualdade estrita de primitivas; objetos exigem `deep.equal`. |
| `gm.expect(value).to.deep.equal(expected)` | Igualdade estrutural de JSON, sem coerção. |
| `.to.be.a(type)`, `.to.contain(value)` | Tipos `string`, `number`, `boolean`, `object`, `array`, `null`, `undefined`; contains em string ou array. |
| `.to.be.lessThan(n)`, `.greaterThan(n)`, `.within(lo, hi)` | Comparações numéricas, intervalo inclusivo, rejeitando operandos não numéricos/não finitos. |
| `.to.exist`, `.to.not.equal(expected)` | Existência significa diferente de undefined, inclusive null. Negação limitada a equal na v1. |
| `console.log/info/warn/error(...values)` | Eventos de console estruturados; serialização resistente a ciclos e limites; sem exceção por logging. |

O namespace é somente leitura e versionado; a aplicação valida o envelope resultante independentemente da engine. Resultados e patches não carregam objetos Dart, handles ou callbacks entre isolates. Passar dados por serialização, nunca concatenar valores de variável como código. Escape de valores para JSON do body é responsabilidade de `JSON.stringify`/setBody; a substituição textual existente não muda silenciosamente.

## Pipeline, erros e concorrência

```text
SEND: executionId + tabId + config + ambiente id/vars + coleção vars
  → verificar confiança e limites
  → PRE-REQUEST → validar saída → aplicar patch de ambiente da etapa
  → resolver {{variáveis}} → auth/body serialization → HTTP
  → POST-RESPONSE → validar saída → aplicar patch de ambiente da etapa
  → publicar testes/logs/diagnósticos → finalizar execução
```

Preservar config original no histórico; efeitos do script alteram somente a cópia enviada. Temporárias e patches bem-sucedidos do pré-script alimentam o pós-script; globals JavaScript não atravessam etapas.

- Pré-script com erro uncaught/timeout/saída inválida: não enviar HTTP; descartar patches da etapa. Teste reprovado no pré-script também bloqueia o envio e descarta seus patches, com motivo visível.
- Pós-script com erro: manter resposta HTTP, testes já finalizados e logs; descartar patches daquela etapa. Não alterar o status HTTP para simular erro de script.
- Testes reprovados no pós-script: preservar resposta e aplicar patches válidos da etapa; resultado de testes é separado do sucesso de execução do script.
- Sem resposta HTTP (DNS/TLS/cancelamento): não executar pós-script. Resposta HTTP 4xx/5xx com corpo/headers executa pós-script. Verificar o mapeamento atual de Dio antes de integrar.
- Cancelar/re-enviar/fechar a aba invalida executionId e interrompe engine/HTTP; não publicar resultados atrasados nem admitir novos patches dessa execução. Trocar aba/painel não cancela.
- O destino dos patches é o environmentId capturado no início; troca de ambiente não redireciona escritas. Se o ambiente for excluído, não recriar e apresentar falha de persistência.
- Validar a execução imediatamente antes de admitir um commit serializado de ambiente. Um commit já admitido é concluído, mesmo se o cancelamento vier depois; não prometer rollback de escrita já iniciada ou HTTP já enviado.
- Patches são merge sobre o estado vivo, nunca substituição do snapshot. Em abas distintas, commits no mesmo campo usam ordem de admissão; campos diferentes não se perdem. Exclusão/edição de ambientes compartilham a mesma fila de mutações.
- Falha ao persistir patch pré-script bloqueia HTTP; falha pós-script mantém resposta e mostra erro. SEND só termina depois da confirmação de persistência, para a próxima requisição ver as capturas.

## Arquitetura e persistência

`RequestScripts` é value object compartilhado em `core/domain/entities`, com `apiVersion=1`, `preRequest`, `postResponse`, `preRequestEnabled=true`, `postResponseEnabled=true`. HttpRequestConfigEntity passa a carregar `scripts`, vazio por padrão, incluído em igualdade/copyWith. Eventos continuam identificados por tabId.

`features/scripting/domain` define inputs/outputs imutáveis, patch, teste, log, erro, cancelamento e o repositório abstrato de execução. `data` implementa engine, bridge e assets; `presentation` contém editor/resultados. A orquestração HTTP fica num use case do domínio de tabs que usa repositórios abstratos e o SendRequestUseCase existente. BLoCs não importam adapter, Hive ou engine.

Persistir `RequestScripts` como mapa primitivo no novo `HiveField(19)` de HttpRequestConfig (typeId 1), depois de verificar o ledger na execução. Ausência lê como vazio; versão desconhecida preserva conteúdo e bloqueia execução com diagnóstico, sem descartar scripts. Não criar novo typeId só para o bundle. Atualizar conversões, igualdade de assinatura do histórico e serializações. Configs que diferem apenas em scripts não podem ser deduplicados como iguais.

Workspace: scripts são intenção do usuário e entram em `request.scripts`; omitir bundle vazio, não serializar logs, patches, dados resolvidos, confiança ou resultados. Diff e merge tratam source/habilitação de cada etapa independentemente; conflito no mesmo source exige escolha, nunca concatenação automática de código. Código pode conter segredos literais: a documentação orienta usar variáveis; não prometer detectar/redigir arbitrary source.

Import/export Postman: preservar scripts Getman em extensão `x-getman-scripts` para round-trip; não exportar `gm.*` como `event` executável no Postman. Scripts Postman externos não são executados/traduzidos nesta entrega. Detectar eventos em request/pasta/coleção e recusar a importação com diagnóstico dos locais afetados antes de gravar qualquer nó; não importá-los silenciosamente sem scripts. Coleções sem eventos continuam funcionando. Documentar a restrição e cobri-la por testes.

Confiança é local, por digest de source+apiVersion e identidade da requisição: conteúdo escrito localmente e habilitado no editor pode rodar; conteúdo importado/recarregado do Git requer ação `TRUST SCRIPTS` antes de SEND. Mudança externa do source invalida confiança. Confiança nunca vem de JSON/Hive compartilhável e não é exportada. Scripts habilitados sem confiança bloqueiam SEND com explicação, em vez de enviar uma versão incompleta da request. Desabilitar ambas as etapas permite envio sem executá-las.

## UI e remoção de Rules

Trocar `RULES` por `SCRIPTS` no mesmo índice das seções. Subabas `PRE-REQUEST` e `POST-RESPONSE`, toggle `ENABLED`, editor re_editor com JavaScript, snippets e ajuda da API. Usar CodeLineEditingController, tokens do tema, buildWhen/listenWhen, e atalhos de salvar/enviar existentes.

Preservar `TESTS` no painel de resposta com nome, etapa, pass/fail e erro. Adicionar `CONSOLE` para logs/erros de ambas as etapas, inclusive falha antes de existir resposta. Exibir estado `RUNNING PRE-REQUEST`/`RUNNING POST-RESPONSE`, cancelamento e limites atingidos. Logs/resultados são efêmeros, por execução/aba, sem persistência nem inclusão automática em bug report.

Valores marcados como secretos são mascarados ao renderizar logs/diagnósticos, assim como valores recém-gravados em chaves secretas existentes. Isso não é rastreamento de informação: transformações arbitrárias de um segredo podem impedir reconhecimento. Não registrar token/variáveis no log do host ou em arquivos de teste.

Retirar o menu de árvore `Extract to {{var}}` que cria Rules, seus prompts e chamadas; o snippet de extração no editor cobre essa operação. Manter JSONPath como helper compartilhado, sem manter a engine de Rules. Retirar o listener antigo de write-back; a nova persistência confirmada pertence à orquestração/repositório, e o EnvironmentsBloc observa as alterações sem acoplamento BLoC→BLoC.

## Qualidade e entrega

Cada comportamento novo passa por RED observado, GREEN mínimo e REFACTOR. Testes de engine usam JavaScript real, não mock de evaluate. Testes unitários do coordenador usam engine fake controlável somente para ordenar corridas e falhas; as mesmas jornadas são exercitadas no fim com runtime e HTTP reais.

Casos obrigatórios: JWT Unicode/Base64URL; JWT inválido/JWE; body com escaping; ausência versus null; console circular; loop infinito; promise pendente; memória/limites; POST em erro HTTP; pré-erro sem rede; perda de confiança após Git; segredo mascarado; ambiente alterado/excluído; reenvio/fechamento; persistência/restart; import/export; diff/merge; UI offstage e layouts.

Release exige quatro análises estáticas, format clean, suite unitária/widget completa, suite E2E macOS completa, contrato real nos demais targets e build release de cada plataforma. Executar apenas `flutter analyze` ou apenas testes com mocks não cumpre o plano. Atualizar wiki GitHub na mesma entrega de produto; este planejamento não publica documentação de feature inexistente.

## Fontes técnicas consultadas

- [QuickJS: C API, memória e interrupção](https://bellard.org/quickjs/quickjs.html): engine oferece hooks; a exposição/segurança no binding Flutter ainda deve ser comprovada.
- [quickjs_engine](https://pub.dev/packages/quickjs_engine): candidato Flutter com QuickJS-NG; listagem de plataformas não substitui validação de builds e cancelamento.
- [quickjs-emscripten](https://github.com/justjake/quickjs-emscripten): alternativa de embedding WASM; revisar versão, disposal e limites no ensaio web.
- Código local: `environment_resolver.dart`, `tabs_repository_impl.dart`, `send_request_use_case.dart`, engines/listener de chaining, serializers de workspace, `semantic_diff.dart`, `three_way_merge.dart` e harness de integração.
