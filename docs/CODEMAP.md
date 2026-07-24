# Getman Code Map

Start here to find anything. This is the master "where is X?" index for the
whole `lib/` tree.

Three sections:

- **[Directory map](#directory-map)** — every `lib/` directory with a one-line
  purpose (and 2-4 key files for the big ones).
- **[Where is…?](#where-is-concept-lookup)** — an alphabetical concept → file
  lookup.
- **[Cross-cutting flows](#cross-cutting-flows)** — nine end-to-end chains that
  span features.

Format note: every directory path is written as a literal string
(`lib/<path>`). The coverage test in `test/docs/codemap_coverage_test.dart`
requires every `lib/` directory that contains hand-written Dart files to appear
below verbatim, so a new feature can't silently escape the map. Each `.dart`
file also opens with a `//` header describing it — read the file's own header
for detail beyond the one-liners here.

Architecture at a glance: feature-first + clean architecture. Each feature is
`domain/` (pure Dart entities + abstract repositories + use cases), `data/`
(Hive models + data sources + repository impls), `presentation/` (BLoC +
widgets + screens). Shared cross-feature code lives under `lib/core/`. See
`CLAUDE.md` for the mandates.

---

## Directory map

### Root & core

| Path | Purpose | Key files |
|---|---|---|
| `lib` | App entry point. | `main.dart` (DI boot, MultiBlocProvider, global `Shortcuts` map, `MaterialApp.router`) |
| `lib/core/di` | GetIt bootstrap. | `injection_container.dart` (registers all blocs/usecases/repos, opens Hive boxes) |
| `lib/core/domain` | Cross-feature pure-domain helpers. | `auth_application.dart`, `persistence_limits.dart` |
| `lib/core/domain/entities` | Shared entities used by >1 feature. | `request_config_entity.dart`, `auth_config.dart`, `body_type.dart`, `multipart_field_entity.dart` |
| `lib/core/error` | Failure / Exception hierarchy. | `failures.dart`, `exceptions.dart`, `guard.dart` |
| `lib/core/git` | Abstract `git`/`gh` CLI gateways (+ io/stub impls). | `git_service.dart`, `git_service_io.dart`, `gh_service.dart`, `gh_output_parser.dart` |
| `lib/core/navigation` | Router + keyboard intents. | `app_router.dart`, `intents.dart`, `url_focus_registry.dart` |
| `lib/core/network` | Dio client, cookies, realtime, MCP transport. | `network_service.dart`, `realtime_service.dart`, `mcp_service.dart`, `cookie_interceptor.dart` |
| `lib/core/storage` | Hive box-name constants + helpers. | `hive_boxes.dart`, `hive_helpers.dart` |
| `lib/core/theme` | Theme registry + responsive tiers. | `theme_registry.dart`, `theme_ids.dart`, `responsive.dart`, `app_theme.dart` |
| `lib/core/theme/extensions` | The 8 `ThemeExtension`s + `context.app*` accessors. | `app_palette.dart`, `app_components.dart`, `app_theme_access.dart`, `app_layout.dart` |
| `lib/core/theme/motion` | Ambient/pulse/theme-switch motion helpers. | `ambient_signals.dart`, `workspace_pulse_controller.dart`, `theme_switch_transition.dart` |
| `lib/core/theme/themes/auris` | AURIS "sci-fi HUD" theme (composes `auris` pub kit). | `auris_theme.dart`, `auris_components.dart`, `auris_ambient.dart` |
| `lib/core/theme/themes/brutalist` | Brutalist ink-press theme. | `brutalist_theme.dart`, `brutalist_components.dart`, `brutalist_palette.dart` |
| `lib/core/theme/themes/classic` | Classic calm/native default theme. | `classic_theme.dart`, `classic_palette.dart`, `classic_decorations.dart` |
| `lib/core/theme/themes/dracula` | Dracula neon dev-console theme. | `dracula_theme.dart`, `dracula_components.dart`, `dracula_palette.dart` |
| `lib/core/theme/themes/editorial` | Editorial print-magazine theme. | `editorial_theme.dart`, `editorial_components.dart`, `editorial_palette.dart` |
| `lib/core/theme/themes/glass` | Liquid Glass frosted theme. | `glass_theme.dart`, `glass_components.dart`, `glass_decorations.dart` |
| `lib/core/theme/themes/rpg` | Arcane Quest RPG grimoire theme. | `rpg_theme.dart`, `rpg_components.dart`, `rpg_decorations.dart` |
| `lib/core/theme/themes/shared` | Motion/press helpers shared across themes. | `calm_motion.dart`, `subtle_press.dart` |
| `lib/core/ui/widgets` | Cross-feature reusable atoms. | `key_value_list_editor.dart`, `variable_highlight_controller.dart`, `branded_tab_bar.dart`, `splitter.dart` |
| `lib/core/utils` | Pure helpers (JSON, cURL, env, diff, media…). | `json_utils.dart`, `curl_utils.dart`, `environment_resolver.dart`, `code_gen_service.dart` |
| `lib/core/utils/apidoc` | Collection → OpenAPI/Markdown API-docs export. | `collection_to_api_doc.dart`, `openapi_serializer.dart`, `markdown_doc_serializer.dart` |
| `lib/core/utils/io` | File-byte reader (io/stub conditional export). | `file_reader.dart`, `file_reader_io.dart`, `file_reader_stub.dart` |
| `lib/core/utils/openapi` | OpenAPI 3.x / Swagger 2.0 import pipeline. | `spec_normalizer.dart`, `openapi_v3_normalizer.dart`, `collection_builder.dart`, `auth_mapper.dart` |
| `lib/core/utils/postman` | Postman v2.1 collection/environment mappers. | `postman_collection_mapper.dart`, `postman_environment_mapper.dart` |
| `lib/core/utils/workspace` | On-disk git-workspace (de)serialization + picker. | `workspace_collection_serializer.dart`, `workspace_picker.dart`, `workspace_bookmark.dart` |

### `chaining` — no-code post-response assertions + variable extraction

| Path | Purpose |
|---|---|
| `lib/features/chaining/data/datasources` | Hive persistence for per-request rules (`request_rules_local_data_source.dart`). |
| `lib/features/chaining/data/models` | Hive models: `assertion_model.dart` (typeId 8), `extraction_rule_model.dart` (7), `request_rules_model.dart` (9). |
| `lib/features/chaining/data/repositories` | `request_rules_repository_impl.dart`. |
| `lib/features/chaining/domain/entities` | `assertion.dart`, `extraction_rule.dart`, `request_rules_entity.dart`. |
| `lib/features/chaining/domain/logic` | Pure engines: `assertion_engine.dart`, `extraction_engine.dart`, `rules_runner.dart`. |
| `lib/features/chaining/domain/repositories` | `request_rules_repository.dart` (abstract). |
| `lib/features/chaining/domain/usecases` | `request_rules_usecases.dart`. |
| `lib/features/chaining/presentation/bloc` | `rules_bloc.dart` / `rules_event.dart` / `rules_state.dart`. |
| `lib/features/chaining/presentation/widgets` | RULES tab UI + `chaining_write_back_listener.dart` (writes captures back to the active env). |

### `collections` — tree of folders/requests, git workspace, imports

| Path | Purpose |
|---|---|
| `lib/features/collections/data/datasources` | Hive tree store + workspace-mirror data source (io/stub + factory). |
| `lib/features/collections/data/models` | `collection_node_model.dart` (typeId 3), `saved_example_model.dart` (10). |
| `lib/features/collections/data/repositories` | `collections_repository_impl.dart` (per-root diff on save). |
| `lib/features/collections/data/services` | Git integration: `workspace_sync_service.dart`, `git_branch_service.dart`, `git_conflict_service.dart`, `gh_pull_request_service.dart`, `workspace_review_service.dart`. |
| `lib/features/collections/domain` | Abstract git gateways: `branch_service.dart`, `conflict_service.dart`, `pull_request_service.dart`, `review_service.dart`. |
| `lib/features/collections/domain/entities` | `collection_node_entity.dart`, `saved_example_entity.dart`, `branch_status.dart`, `pull_request.dart`, `file_conflict.dart`, `review_entry.dart`. |
| `lib/features/collections/domain/logic` | `collections_tree_helper.dart` (pure tree ops), `semantic_diff.dart`, `three_way_merge.dart`. |
| `lib/features/collections/domain/repositories` | `collections_repository.dart` (abstract). |
| `lib/features/collections/domain/usecases` | `collections_usecases.dart`. |
| `lib/features/collections/presentation/bloc` | `collections_bloc.dart` + git blocs (`git_sync_bloc.dart`, `review_bloc.dart`, `pull_requests_bloc.dart`, `conflict_bloc.dart`). |
| `lib/features/collections/presentation/widgets` | Tree UI + git UI: `collections_list.dart`, `collection_node_row.dart`, `node_drag_data.dart`, `branch_chip.dart`, `review_changes_dialog.dart`, `conflict_resolution_dialog.dart`, `spec_import_dialog.dart`. |

### `command_palette` — Cmd/Ctrl+K fuzzy jump

| Path | Purpose |
|---|---|
| `lib/features/command_palette/presentation/widgets` | `command_palette.dart` (fuzzy jump to request/history/env/theme; no bloc of its own). |

### `cookies` — Hive-backed cookie jar (infra-only, no domain/data split)

| Path | Purpose |
|---|---|
| `lib/features/cookies/data` | `hive_cookie_persistence.dart` (durable backing for the core `CookieStore`). |
| `lib/features/cookies/data/models` | `stored_cookie_model.dart` (typeId 6). |
| `lib/features/cookies/presentation/widgets` | `cookie_manager_dialog.dart` (Settings → COOKIES → MANAGE). |

### `environments` — flat list of `{{var}}` variable sets

| Path | Purpose |
|---|---|
| `lib/features/environments/data/datasources` | `environments_local_data_source.dart` (sorted by name on read). |
| `lib/features/environments/data/models` | `environment_model.dart` (typeId 4). |
| `lib/features/environments/data/repositories` | `environments_repository_impl.dart`. |
| `lib/features/environments/domain/entities` | `environment_entity.dart` (variables map + secretKeys). |
| `lib/features/environments/domain/logic` | `active_environment_helper.dart` (resolve active env + its vars by id). |
| `lib/features/environments/domain/repositories` | `environments_repository.dart` (abstract). |
| `lib/features/environments/domain/usecases` | `environments_usecases.dart`. |
| `lib/features/environments/presentation/bloc` | `environments_bloc.dart` / `environments_event.dart` / `environments_state.dart`. |
| `lib/features/environments/presentation/widgets` | `environments_dialog.dart`, `environment_editor.dart`, `environment_selector.dart`, `quick_env_switcher.dart` (Cmd/Ctrl+E). |

### `history` — read-only request history (writes only via send)

| Path | Purpose |
|---|---|
| `lib/features/history/data/datasources` | `history_local_data_source.dart` (dedup by signature, trim, `Box.watch()`). |
| `lib/features/history/data/models` | `request_config_model.dart` (typeId 1; `==` excludes id). |
| `lib/features/history/data/repositories` | `history_repository_impl.dart` (debounced newest-first watch). |
| `lib/features/history/domain/repositories` | `history_repository.dart` (abstract). |
| `lib/features/history/domain/usecases` | `history_usecases.dart`. |
| `lib/features/history/presentation/bloc` | `history_bloc.dart` (no load event; subscribes on construct). |
| `lib/features/history/presentation/widgets` | `history_list.dart` (side-menu HISTORY tab). |

### `home` — app shell + dirty tracking

| Path | Purpose |
|---|---|
| `lib/features/home/domain/usecases` | `tab_dirty_checker.dart` (unsaved-changes detection). |
| `lib/features/home/presentation/screens` | `main_screen.dart` (app shell; hosts every keyboard `Action` + tab strip). |
| `lib/features/home/presentation/widgets` | `side_menu.dart`, `request_tab_chip.dart`, `tab_content_stack.dart`, `tab_chip.dart`, `add_tab_button.dart`, `tab_strip_double_click.dart`, `empty_tabs_placeholder.dart`. |

### `mcp` — Model Context Protocol client (bloc-over-service)

| Path | Purpose |
|---|---|
| `lib/features/mcp/domain` | `mcp_argument_resolver.dart` (`{{var}}` substitution in tool-call args). |
| `lib/features/mcp/domain/entities` | `mcp_session.dart`, `mcp_tool.dart`, `mcp_tool_result.dart`. |
| `lib/features/mcp/presentation/bloc` | `mcp_bloc.dart` / `mcp_event.dart` / `mcp_state.dart` (per-tab session map). |
| `lib/features/mcp/presentation/widgets` | `mcp_connect_button.dart`, `mcp_panel.dart` (tool picker + CALL + log). |

### `realtime` — WebSocket + SSE (bloc-over-service)

| Path | Purpose |
|---|---|
| `lib/features/realtime/presentation/bloc` | `realtime_bloc.dart` / `realtime_event.dart` / `realtime_state.dart` (per-tab connection + frame log). |
| `lib/features/realtime/presentation/widgets` | `realtime_panel.dart` (live WS/SSE view; composer WS-only). |

### `settings` — single app-wide settings record

| Path | Purpose |
|---|---|
| `lib/features/settings/data/datasources` | `settings_local_data_source.dart` (box `settings`, key `current`). |
| `lib/features/settings/data/models` | `settings_model.dart` (typeId 0). |
| `lib/features/settings/data/repositories` | `settings_repository_impl.dart`. |
| `lib/features/settings/domain/entities` | `settings_entity.dart` (limits, appearance, network/mTLS, workspace, updates, git identity). |
| `lib/features/settings/domain/repositories` | `settings_repository.dart` (abstract). |
| `lib/features/settings/domain/usecases` | `settings_usecases.dart`. |
| `lib/features/settings/presentation/bloc` | `settings_bloc.dart` (one handler per `Update*`; no load event). |
| `lib/features/settings/presentation/widgets` | `settings_dialog.dart` (5 tabs), `network_settings_listener.dart`, `client_certificate_tile.dart`, `git_identity_settings_tile.dart`, `settings_shortcuts_tab.dart`. |

### `tabs` — request/response editor (most complex feature)

| Path | Purpose |
|---|---|
| `lib/features/tabs/data` | `request_serializer.dart` (wire-level auth + body serialization). |
| `lib/features/tabs/data/datasources` | `tabs_local_data_source.dart` (tabs + panels + meta boxes). |
| `lib/features/tabs/data/models` | `request_tab_model.dart` (typeId 2), `panel_model.dart` (12), `stored_response_model.dart` (11), `multipart_field_model.dart` (5). |
| `lib/features/tabs/data/repositories` | `tabs_repository_impl.dart` (persistence + send; env substitution). |
| `lib/features/tabs/domain/entities` | `request_tab_entity.dart`, `panel_entity.dart`, `response_history_entry.dart`. |
| `lib/features/tabs/domain/repositories` | `tabs_repository.dart` (abstract). |
| `lib/features/tabs/domain/usecases` | `send_request_use_case.dart` (couples send + history write). |
| `lib/features/tabs/presentation/bloc` | `tabs_bloc.dart` (panel-aware), `tabs_event.dart`, `tabs_state.dart`, `request_manager.dart`. |
| `lib/features/tabs/presentation/screens` | `request_view.dart` (per-tab request/response screen; owns code controllers + split). |
| `lib/features/tabs/presentation/widgets` | Editor tabs + URL bar + panels: `url_bar.dart`, `params_tab_view.dart`, `headers_tab_view.dart`, `body_tab_view.dart`, `auth_tab_view.dart`, `panel_selector.dart`, `json_code_editor.dart`, `response_section.dart`. |
| `lib/features/tabs/presentation/widgets/response` | Response pane tab bodies: `response_body_view.dart`, `response_headers_view.dart`, `response_cookies_view.dart`, `response_tests_view.dart`, `json_tree_view.dart`, `response_history_timeline.dart`. |
| `lib/features/tabs/presentation/widgets/response/viewers` | Media/binary response viewers: `response_media_panel.dart`, `image_response_view.dart`, `pdf_response_view.dart`, `media_response_view.dart`, `csv_response_view.dart`, `html_response_view.dart`, `binary_response_view.dart`. |

### `updates` — GitHub-release auto-updater

| Path | Purpose |
|---|---|
| `lib/features/updates/data/datasources` | `github_release_data_source.dart` (fetch latest release + platform asset). |
| `lib/features/updates/data/repositories` | `update_repository_impl.dart` (fetch failure → `null`). |
| `lib/features/updates/domain/entities` | `release_info.dart` (`ReleaseInfo` + `UpdatePlatform`). |
| `lib/features/updates/domain/repositories` | `update_repository.dart` (abstract). |
| `lib/features/updates/presentation` | Web-safety gate + logic: `update_gate.dart` (conditional export), `update_gate_io.dart`, `update_gate_stub.dart`, `update_decision.dart`, `update_controller.dart`, `update_phase.dart`. |
| `lib/features/updates/presentation/widgets` | `update_dialog.dart`, `update_download_dialog.dart` (blocking in-app download progress), `update_settings_section.dart`. |

---

## Where is…? (concept lookup)

Alphabetical. Each concept points at its primary file(s); read the file's own
`//` header for detail.

| Concept | File(s) |
|---|---|
| API docs export (OpenAPI/Markdown) | `lib/core/utils/apidoc/collection_to_api_doc.dart`, `lib/features/collections/presentation/widgets/export_api_docs_dialog.dart` |
| Assertions (no-code) | `lib/features/chaining/domain/logic/assertion_engine.dart`, `lib/features/chaining/presentation/widgets/assertion_rule_row.dart` |
| Auth (bearer/basic/api-key) | `lib/core/domain/entities/auth_config.dart`, `lib/core/domain/auth_application.dart`, `lib/features/tabs/presentation/widgets/auth_tab_view.dart` |
| Auto-update | `lib/features/updates/presentation/update_gate.dart`, `lib/features/updates/presentation/update_decision.dart` |
| Autocomplete (`{{var}}`) | `lib/core/ui/widgets/variable_autocomplete.dart`, `lib/core/utils/variable_suggestions.dart` |
| Beautify / prettify JSON | `lib/core/utils/json_utils.dart` |
| Body types (raw/urlencoded/multipart/binary/graphql) | `lib/core/domain/entities/body_type.dart`, `lib/features/tabs/presentation/widgets/body_tab_view.dart` |
| Boot / dependency injection | `lib/main.dart`, `lib/core/di/injection_container.dart` |
| Bulk edit (key/value) | `lib/core/ui/widgets/bulk_kv_editor.dart`, `lib/core/utils/bulk_kv_codec.dart`, `lib/features/tabs/presentation/widgets/bulk_mode_toggle.dart` |
| Byte size / response size | `lib/core/utils/byte_format.dart` |
| Cancel request | `lib/core/network/cancel_handle.dart`, `lib/features/tabs/presentation/bloc/request_manager.dart` |
| Chaining / extraction | `lib/features/chaining/domain/logic/extraction_engine.dart`, `lib/features/chaining/domain/logic/rules_runner.dart` |
| Code generation (cURL/JS/Python/Go/Java) | `lib/core/utils/code_gen_service.dart`, `lib/features/tabs/presentation/widgets/code_export_dialog.dart` |
| Collection-scoped variables | `lib/core/utils/request_variable_resolver.dart`, `lib/features/collections/presentation/widgets/collection_variables_dialog.dart` |
| Collections tree | `lib/features/collections/presentation/widgets/collections_list.dart`, `lib/features/collections/domain/logic/collections_tree_helper.dart` |
| Command palette | `lib/features/command_palette/presentation/widgets/command_palette.dart`, `lib/core/utils/fuzzy_matcher.dart` |
| Compare / diff responses | `lib/core/utils/response_diff_builder.dart`, `lib/core/ui/widgets/response_diff_view.dart`, `lib/core/utils/line_diff.dart` |
| Confirm dialog | `lib/core/ui/widgets/confirm_dialog.dart` |
| Conflict resolution (git rebase) | `lib/features/collections/domain/logic/three_way_merge.dart`, `lib/features/collections/presentation/widgets/conflict_resolution_dialog.dart` |
| Cookie parsing (Set-Cookie) | `lib/core/utils/cookie_parser.dart`, `lib/core/network/network_cookie.dart` |
| Cookies (jar + interceptor) | `lib/core/network/cookie_interceptor.dart`, `lib/core/network/in_memory_cookie_store.dart`, `lib/features/cookies/data/hive_cookie_persistence.dart`, `lib/features/cookies/presentation/widgets/cookie_manager_dialog.dart` |
| cURL parse / paste | `lib/core/utils/curl_utils.dart`, `lib/features/tabs/presentation/widgets/url_bar.dart` |
| Debounce | `lib/core/utils/debouncer.dart` |
| Dirty tracking | `lib/features/home/domain/usecases/tab_dirty_checker.dart` |
| Drag-and-drop (tree/tabs) | `lib/features/collections/presentation/widgets/node_drag_data.dart`, `lib/features/collections/presentation/widgets/collection_node_row.dart`, `lib/features/tabs/presentation/widgets/tab_drag_data.dart` |
| Dynamic variables (`{{$guid}}`…) | `lib/core/utils/environment_resolver.dart` |
| Environments | `lib/features/environments/presentation/bloc/environments_bloc.dart`, `lib/core/utils/environment_resolver.dart` |
| Error model (Failure/Exception) | `lib/core/error/failures.dart`, `lib/core/error/exceptions.dart`, `lib/core/error/guard.dart` |
| Examples (saved) | `lib/features/collections/domain/entities/saved_example_entity.dart`, `lib/features/collections/presentation/widgets/example_row.dart` |
| Form data / multipart | `lib/features/tabs/presentation/widgets/form_data_editor.dart`, `lib/core/domain/entities/multipart_field_entity.dart` |
| Fuzzy matching | `lib/core/utils/fuzzy_matcher.dart` |
| Git — branches / stash / sync | `lib/core/git/git_service.dart`, `lib/features/collections/data/services/git_branch_service.dart` |
| Git — conflicts | `lib/features/collections/data/services/git_conflict_service.dart`, `lib/features/collections/domain/logic/three_way_merge.dart` |
| Git — pull requests | `lib/core/git/gh_service.dart`, `lib/features/collections/data/services/gh_pull_request_service.dart`, `lib/features/collections/presentation/widgets/pull_requests_dialog.dart` |
| Git — review changes | `lib/features/collections/data/services/workspace_review_service.dart`, `lib/features/collections/presentation/widgets/review_changes_dialog.dart` |
| GraphQL | `lib/core/domain/entities/body_type.dart`, `lib/features/tabs/data/request_serializer.dart`, `lib/features/tabs/presentation/widgets/body_tab_view.dart` |
| History + dedup | `lib/features/history/data/datasources/history_local_data_source.dart` |
| Hive boxes / storage | `lib/core/storage/hive_boxes.dart`, `lib/core/storage/hive_helpers.dart` |
| HTTP methods list | `lib/core/network/http_methods.dart` |
| HTTP send / network client | `lib/core/network/network_service.dart` |
| JSONPath | `lib/core/utils/json_path.dart`, `lib/core/utils/json_path_builder.dart` |
| Keyboard shortcuts | `lib/main.dart`, `lib/core/navigation/intents.dart`, `lib/features/settings/presentation/widgets/settings_shortcuts_tab.dart` |
| Large responses | `lib/core/domain/persistence_limits.dart`, `lib/features/tabs/presentation/widgets/response/response_large_body_view.dart` |
| MCP (Model Context Protocol) | `lib/core/network/mcp_service.dart`, `lib/features/mcp/presentation/bloc/mcp_bloc.dart` |
| Media / binary response viewers | `lib/features/tabs/presentation/widgets/response/viewers/response_media_panel.dart` |
| Method colors / badge | `lib/core/theme/extensions/app_palette.dart`, `lib/core/ui/widgets/method_badge.dart` |
| mTLS / client certificates | `lib/core/network/dio_adapter_config_io.dart`, `lib/features/settings/presentation/widgets/client_certificate_tile.dart` |
| Name prompt dialog | `lib/core/ui/widgets/name_prompt_dialog.dart` |
| OpenAPI / Swagger import | `lib/core/utils/openapi/spec_normalizer.dart`, `lib/core/utils/openapi/collection_builder.dart`, `lib/features/collections/presentation/widgets/spec_import_dialog.dart` |
| Panels (virtual desktops) | `lib/features/tabs/data/models/panel_model.dart`, `lib/features/tabs/presentation/widgets/panel_selector.dart`, `lib/features/tabs/presentation/bloc/tabs_bloc.dart` |
| Postman import / export | `lib/core/utils/postman/postman_collection_mapper.dart`, `lib/core/utils/postman/postman_environment_mapper.dart`, `lib/core/utils/json_file_io.dart` |
| Proxy | `lib/core/network/dio_adapter_config_io.dart`, `lib/core/network/network_config.dart` |
| Redirects (manual loop) | `lib/core/network/network_service.dart` |
| Request config entity | `lib/core/domain/entities/request_config_entity.dart` |
| Response time-travel | `lib/features/tabs/domain/entities/response_history_entry.dart`, `lib/features/tabs/presentation/widgets/response/response_history_timeline.dart` |
| Responsive layout tiers | `lib/core/theme/responsive.dart` |
| Routing | `lib/core/navigation/app_router.dart` |
| Secret variables | `lib/core/ui/widgets/key_value_list_editor.dart`, `lib/features/environments/domain/entities/environment_entity.dart` |
| Settings | `lib/features/settings/presentation/bloc/settings_bloc.dart`, `lib/features/settings/domain/entities/settings_entity.dart`, `lib/features/settings/presentation/widgets/settings_dialog.dart` |
| Snackbars | `lib/core/ui/widgets/app_snack_bar.dart` |
| Splitters (pane dividers) | `lib/core/ui/widgets/splitter.dart` |
| SSE (Server-Sent Events) | `lib/core/network/sse_parser.dart`, `lib/core/network/realtime_service.dart` |
| Tab strip / chips | `lib/features/home/presentation/screens/main_screen.dart`, `lib/features/home/presentation/widgets/request_tab_chip.dart`, `lib/features/home/presentation/widgets/tab_strip_double_click.dart` |
| Tabs (request editor) | `lib/features/tabs/presentation/bloc/tabs_bloc.dart`, `lib/features/tabs/domain/entities/request_tab_entity.dart` |
| Theme accessors (`context.app*`) | `lib/core/theme/extensions/app_theme_access.dart`, `lib/core/theme/app_theme.dart` |
| Themes + component slots | `lib/core/theme/theme_registry.dart`, `lib/core/theme/extensions/app_components.dart` |
| Tree view (JSON TREE mode) | `lib/features/tabs/presentation/widgets/response/json_tree_view.dart`, `lib/core/utils/json_path_builder.dart` |
| URL query parsing | `lib/core/utils/url_query_utils.dart` |
| Variable highlighting | `lib/core/ui/widgets/variable_highlight_controller.dart` |
| Variable hover popover | `lib/core/ui/widgets/variable_hover_popover.dart` |
| WebSocket | `lib/core/network/realtime_service.dart`, `lib/features/realtime/presentation/bloc/realtime_bloc.dart`, `lib/features/realtime/presentation/widgets/realtime_panel.dart` |
| Workspace mirror (git-friendly) | `lib/features/collections/data/services/workspace_sync_service.dart`, `lib/features/collections/data/datasources/workspace_collections_data_source.dart` |

---

## Cross-cutting flows

Each numbered chain is a step-by-step `file — role`. These span multiple
features; follow them to trace an end-to-end behavior.

### 1. Send an HTTP request

1. `lib/features/tabs/presentation/widgets/url_bar.dart` — SEND button dispatches `SendRequest(tabId, envVars)`; also the `SendRequestIntent` in `lib/features/home/presentation/screens/main_screen.dart`. Both resolve env vars at press time.
2. `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — `_onSendRequest` sets `isSending`, binds a cancel handle (`request_manager.dart`), calls the use case.
3. `lib/features/tabs/domain/usecases/send_request_use_case.dart` — couples the network send with best-effort history recording.
4. `lib/features/tabs/data/repositories/tabs_repository_impl.dart` — resolves `{{var}}` in URL/params/headers/body directly via `EnvironmentResolver`; `lib/features/tabs/data/request_serializer.dart` handles auth injection + body building (also resolving vars in auth/body values), then the repository calls the network service.
5. `lib/core/network/network_service.dart` — performs the send with the manual redirect loop; the cookie interceptor (`cookie_interceptor.dart`) runs per hop.
6. `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — `_recordResponse` stores the response, trims time-travel history, runs chaining rules.
7. `lib/features/tabs/presentation/widgets/response_section.dart` (+ `response/` tab bodies) — renders the response.
   - Side branch: `lib/features/history/data/datasources/history_local_data_source.dart` — the use case writes the templated (unresolved) config to history.

### 2. Cookie round-trip

1. `lib/core/network/cookie_interceptor.dart` — attaches the `Cookie` header on request, captures `Set-Cookie` on response.
2. `lib/core/network/cookie_store.dart` / `lib/core/network/in_memory_cookie_store.dart` — the abstract jar + runtime impl (matching, expiry, ordering).
3. `lib/features/cookies/data/hive_cookie_persistence.dart` — flushes each mutation to the `cookies` Hive box.
4. `lib/features/cookies/presentation/widgets/cookie_manager_dialog.dart` — Settings → COOKIES → MANAGE view over `CookieStore.all()` / `remove()`.

### 3. Environment / variable resolution

1. `lib/core/utils/environment_resolver.dart` — resolves `{{name}}` (and `{{$dynamic}}`) tokens in strings/maps.
2. `lib/features/environments/domain/logic/active_environment_helper.dart` — picks the active environment's variables by id (`SettingsEntity.activeEnvironmentId`).
3. SEND dispatchers (`lib/features/tabs/presentation/widgets/url_bar.dart`, `lib/features/home/presentation/screens/main_screen.dart`) — read that map and pass it as `SendRequest.envVars`.
4. `lib/core/ui/widgets/variable_highlight_controller.dart` — colors `{{var}}` tokens resolved vs unresolved in the URL/field editors.

### 4. Dirty tracking

1. `lib/features/home/domain/usecases/tab_dirty_checker.dart` — compares a tab's config against its saved node (or a pristine default).
2. Consumed by the tab close/save flows: `lib/features/home/presentation/widgets/request_tab_chip.dart` (close/close-others confirms), `lib/features/tabs/presentation/widgets/panel_close_coordinator.dart` (close-panel save prompt), `lib/features/tabs/presentation/screens/request_view.dart` (SAVE-to-collection).

### 5. Theme resolution

1. `lib/features/settings/domain/entities/settings_entity.dart` — `themeId` (+ `isDarkMode` / `isCompactMode`).
2. `lib/core/theme/theme_registry.dart` — `resolveTheme(themeId)` returns the builder; `resolveThemeData` caches the built `ThemeData`.
3. The theme builder (e.g. `lib/core/theme/themes/classic/classic_theme.dart`) — attaches the 8 `ThemeExtension`s.
4. `lib/core/theme/extensions/app_components.dart` (+ the other extensions in `lib/core/theme/extensions`) — per-theme widget slots + sizes/colors/shapes.
5. Widgets read them via `lib/core/theme/extensions/app_theme_access.dart` (`context.appPalette`, `context.appComponents`, …).

### 6. Panel / tab lifecycle

1. `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — panel events (`AddPanel`/`RemovePanel`/`MoveTabToPanel`/`SetActivePanel`…) mutate the panel-aware state.
2. `lib/features/tabs/data/models/panel_model.dart` — persists panels (ids only) to the `panels` box; order/active in `tabs_meta`.
3. `lib/features/tabs/presentation/widgets/panel_selector.dart` — panel dropdown in the tab strip; `lib/features/home/presentation/screens/main_screen.dart` (`_buildTabBar`) + `lib/features/home/presentation/widgets/request_tab_chip.dart` render the strip; `lib/features/tabs/presentation/widgets/tab_switcher_sheet.dart` is the compact-phone stand-in.

### 7. Chaining (post-response assertions + extraction)

1. Response arrives in `lib/features/tabs/presentation/bloc/tabs_bloc.dart` — loads rules via `GetRequestRulesUseCase`.
2. `lib/features/chaining/domain/logic/rules_runner.dart` — decodes once and runs `lib/features/chaining/domain/logic/assertion_engine.dart` + `lib/features/chaining/domain/logic/extraction_engine.dart`.
3. `lib/features/chaining/presentation/widgets/chaining_write_back_listener.dart` — writes captured values back into the active environment.
4. `lib/features/environments/presentation/bloc/environments_bloc.dart` — `MergeEnvironmentVariables` persists the captures.

### 8. Postman import / export

1. `lib/core/utils/json_file_io.dart` — file picker + snackbar plumbing (`saveJsonFileWithFeedback` / `importJsonFilesWithFeedback`).
2. `lib/core/utils/postman/postman_collection_mapper.dart` / `lib/core/utils/postman/postman_environment_mapper.dart` — map Getman entities ↔ Postman v2.1 JSON.
3. `lib/features/collections/presentation/bloc/collections_bloc.dart` / `lib/features/environments/presentation/bloc/environments_bloc.dart` — apply the imported tree / environments.

### 9. Auto-update

1. `lib/main.dart` provides `UpdateController` above `MaterialApp` via `ChangeNotifierProvider`; the startup check itself runs in `lib/features/updates/presentation/update_gate.dart` (conditional export; native = `update_gate_io.dart`, web = `update_gate_stub.dart`), rendered as a `Stack` overlay by `lib/features/home/presentation/screens/main_screen.dart`.
2. `lib/features/updates/data/datasources/github_release_data_source.dart` — fetches the latest GitHub release.
3. `lib/features/updates/presentation/update_decision.dart` — `isNewerVersion` + `shouldPromptForUpdate`.
4. `lib/features/updates/presentation/update_controller.dart` — drives dialog state (a `ChangeNotifier`).
5. `lib/features/updates/presentation/widgets/update_dialog.dart` — Update now / Skip this version / Later (UPDATE NOW: macOS opens the browser; Windows/Linux confirm, download in-app, launch the installer, and quit).
