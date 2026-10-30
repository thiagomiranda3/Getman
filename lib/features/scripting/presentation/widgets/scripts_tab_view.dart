// Request-owned JavaScript editors. Controllers follow external config changes
// while offstage; only source edits (not selection changes) update the tab.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/request_scripts.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/branded_tab_bar.dart';
import 'package:getman/features/scripting/domain/entities/script_phase.dart';
import 'package:getman/features/scripting/domain/logic/script_snippets.dart';
import 'package:getman/features/scripting/domain/repositories/script_trust_repository.dart';
import 'package:getman/features/scripting/presentation/widgets/script_help_dialog.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/json_code_editor.dart';
import 'package:getman/features/tabs/presentation/widgets/request_section_index.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

final _javascript = Highlight()..registerLanguage('javascript', langJavascript);

CodeLineEditingController createScriptCodeController() =>
    CodeLineEditingController(
      spanBuilder:
          ({
            required context,
            required index,
            required codeLine,
            required textSpan,
            required style,
          }) {
            final renderer = TextSpanRenderer(
              style,
              Theme.of(context).brightness == Brightness.dark
                  ? atomOneDarkTheme
                  : atomOneLightTheme,
            );
            _javascript
                .highlight(code: codeLine.text, language: 'javascript')
                .render(renderer);
            return renderer.span ?? textSpan;
          },
    );

class ScriptsTabView extends StatefulWidget {
  const ScriptsTabView({required this.tabId, super.key});
  final String tabId;
  @override
  State<ScriptsTabView> createState() => _ScriptsTabViewState();
}

class _ScriptsTabViewState extends State<ScriptsTabView>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabs;
  late final CodeLineEditingController _pre;
  late final CodeLineEditingController _post;
  bool _syncing = false;
  bool _trusted = false;
  int _trustRevision = 0;
  RequestSectionIndex? _sectionIndex;
  ScriptSnippet? _preSnippet;
  ScriptSnippet? _postSnippet;
  RequestScripts? _sourceSnapshot;
  final _pendingLocalSaves = <RequestScripts>{};
  ({String configId, RequestScripts scripts, Future<bool> approval})?
  _lastAuthored;
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _pre = createScriptCodeController();
    _post = createScriptCodeController();
    _sync();
    _pre.addListener(_edit);
    _post.addListener(_edit);
    _sectionIndex = context.read<RequestSectionIndex>();
    _sectionIndex?.addListener(_navigate);
    _navigate();
  }

  void _navigate() {
    final section = _sectionIndex;
    if (section == null ||
        section.value != 4 ||
        section.scriptTabId != widget.tabId) {
      return;
    }
    final post = section.scriptPostResponse;
    final controller = post ? _post : _pre;
    // Recreate-free direct offset is adjacent (two phases only); zero duration
    // also settles immediately while an enclosing request view is offstage.
    _tabs.index = post ? 1 : 0;
    final lines = controller.text.split('\n');
    final line = (section.scriptLine - 1).clamp(0, lines.length - 1);
    controller.selection = CodeLineSelection.collapsed(
      index: line,
      offset: (section.scriptColumn - 1).clamp(0, lines[line].length),
    );
  }

  HttpRequestTabEntity? get _tab =>
      context.read<TabsBloc>().state.tabs.byId(widget.tabId);

  void _sync() {
    final tab = _tab;
    if (tab == null) return;
    final incoming = tab.config.scripts;
    // Older BLoC echoes must not replace the newer text of rapid local edits.
    if (_pendingLocalSaves.remove(incoming) && incoming != _sourceSnapshot) {
      return;
    }
    _sourceSnapshot = incoming;
    _syncing = true;
    if (_pre.text != tab.config.scripts.preRequest) {
      _pre.text = tab.config.scripts.preRequest;
    }
    if (_post.text != tab.config.scripts.postResponse) {
      _post.text = tab.config.scripts.postResponse;
    }
    _syncing = false;
    unawaited(_checkTrust(tab));
  }

  Future<void> _checkTrust(HttpRequestTabEntity tab) async {
    final revision = ++_trustRevision;
    final trusted =
        tab.config.scripts.isEmpty ||
        await context.read<ScriptTrustRepository>().isTrusted(
          tab.config.id,
          tab.config.scripts,
        );
    if (mounted && revision == _trustRevision) {
      setState(() => _trusted = trusted);
    }
  }

  void _edit() {
    if (_syncing) return;
    final tab = _tab;
    if (tab == null) return;
    final scripts = (_sourceSnapshot ?? tab.config.scripts).copyWith(
      preRequest: _pre.text,
      postResponse: _post.text,
    );
    if (scripts != (_sourceSnapshot ?? tab.config.scripts)) _save(scripts);
  }

  void _save(RequestScripts scripts, {bool authored = true}) {
    final tab = _tab;
    if (tab == null) return;
    final previous = _sourceSnapshot ?? tab.config.scripts;
    _sourceSnapshot = scripts;
    _pendingLocalSaves.add(scripts);
    if (authored) {
      final repository = context.read<ScriptTrustRepository>();
      final pending = _lastAuthored;
      // A local edit inherits approval only from its exact displayed
      // predecessor. In particular, editing one phase cannot approve an
      // imported source in the other phase. Chain rapid edits behind the
      // previous approval instead of racing its asynchronous persistence.
      final previousApproval = previous.isEmpty
          ? Future.value(true)
          : pending?.configId == tab.config.id && pending?.scripts == previous
          ? pending!.approval
          : repository.isTrusted(tab.config.id, previous);
      final approval = previousApproval.then((trusted) async {
        if (!trusted) return false;
        await repository.trust(tab.config.id, scripts);
        final current = mounted ? _tab : null;
        if (current?.config.id == tab.config.id &&
            current?.config.scripts == scripts) {
          await _checkTrust(current!);
        }
        return true;
      });
      _lastAuthored = (
        configId: tab.config.id,
        scripts: scripts,
        approval: approval,
      );
    }
    context.read<TabsBloc>().add(
      UpdateTab(tab.copyWith(config: tab.config.copyWith(scripts: scripts))),
    );
  }

  @override
  void didUpdateWidget(ScriptsTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabId != widget.tabId) {
      _sourceSnapshot = null;
      _pendingLocalSaves.clear();
      _lastAuthored = null;
      _sync();
    }
  }

  @override
  void dispose() {
    _trustRevision++;
    _sectionIndex?.removeListener(_navigate);
    _pre
      ..removeListener(_edit)
      ..dispose();
    _post
      ..removeListener(_edit)
      ..dispose();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocConsumer<TabsBloc, TabsState>(
      listenWhen: (a, b) =>
          a.tabs.byId(widget.tabId)?.config.scripts !=
          b.tabs.byId(widget.tabId)?.config.scripts,
      listener: (_, state) => _sync(),
      buildWhen: (a, b) =>
          a.tabs.byId(widget.tabId)?.config.scripts !=
          b.tabs.byId(widget.tabId)?.config.scripts,
      builder: (context, state) {
        final scripts =
            state.tabs.byId(widget.tabId)?.config.scripts ??
            const RequestScripts();
        return Column(
          children: [
            if (!_trusted && !scripts.isEmpty)
              Padding(
                padding: EdgeInsets.all(context.appLayout.inputPadding),
                child: Column(
                  children: [
                    const Text(
                      'Scripts can read request and environment values. '
                      'Review both sources before trusting this exact content.',
                    ),
                    TextButton(
                      onPressed: () async {
                        final tab = _tab;
                        if (tab == null) return;
                        final repository = context
                            .read<ScriptTrustRepository>();
                        final approved = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('REVIEW SCRIPTS'),
                            content: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('PRE-REQUEST'),
                                  Text(
                                    scripts.preRequestEnabled
                                        ? 'ENABLED'
                                        : 'DISABLED',
                                  ),
                                  SelectableText(scripts.preRequest),
                                  const Text('POST-RESPONSE'),
                                  Text(
                                    scripts.postResponseEnabled
                                        ? 'ENABLED'
                                        : 'DISABLED',
                                  ),
                                  SelectableText(scripts.postResponse),
                                ],
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('CANCEL'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('TRUST EXACT CONTENT'),
                              ),
                            ],
                          ),
                        );
                        if (approved == true) {
                          await repository.trust(tab.config.id, scripts);
                          if (mounted) {
                            // Explicit review replaces any earlier failed
                            // automatic approval for this exact snapshot.
                            _lastAuthored = (
                              configId: tab.config.id,
                              scripts: scripts,
                              approval: Future.value(true),
                            );
                            _sync();
                          }
                        }
                      },
                      child: const Text('TRUST SCRIPTS'),
                    ),
                  ],
                ),
              ),
            BrandedTabBar(
              controller: _tabs,
              labels: const ['PRE-REQUEST', 'POST-RESPONSE'],
              isScrollable: true,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _editor(_pre, scripts.preRequestEnabled, true),
                  _editor(_post, scripts.postResponseEnabled, false),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _editor(
    CodeLineEditingController controller,
    bool enabled,
    bool pre,
  ) => Column(
    children: [
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.appLayout.inputPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: DropdownButton<ScriptSnippet>(
                isExpanded: true,
                value:
                    (pre ? _preSnippet : _postSnippet) ??
                    ScriptSnippets.all.firstWhere(
                      (s) =>
                          s.phase ==
                          (pre
                              ? ScriptPhase.preRequest
                              : ScriptPhase.postResponse),
                    ),
                items: [
                  for (final snippet in ScriptSnippets.all.where(
                    (s) =>
                        s.phase ==
                        (pre
                            ? ScriptPhase.preRequest
                            : ScriptPhase.postResponse),
                  ))
                    DropdownMenuItem(
                      value: snippet,
                      child: Text(
                        snippet.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  if (pre) {
                    _preSnippet = value;
                  } else {
                    _postSnippet = value;
                  }
                }),
              ),
            ),
            TextButton(
              onPressed: () {
                final snippet =
                    (pre ? _preSnippet : _postSnippet) ??
                    ScriptSnippets.all.firstWhere(
                      (s) =>
                          s.phase ==
                          (pre
                              ? ScriptPhase.preRequest
                              : ScriptPhase.postResponse),
                    );
                controller.replaceSelection(snippet.source);
              },
              child: const Text('INSERT'),
            ),
          ],
        ),
      ),
      Row(
        children: [
          Switch(
            value: enabled,
            onChanged: (value) {
              final scripts = _tab?.config.scripts;
              if (scripts != null) {
                _save(
                  pre
                      ? scripts.copyWith(preRequestEnabled: value)
                      : scripts.copyWith(postResponseEnabled: value),
                  authored: false,
                );
              }
            },
          ),
          const Text('ENABLED'),
          const Spacer(),
          TextButton(
            onPressed: () => ScriptHelpDialog.show(context),
            child: const Text('HELP'),
          ),
        ],
      ),
      Expanded(
        child: JsonCodeEditor(
          key: ValueKey(pre ? 'script_editor_pre' : 'script_editor_post'),
          controller: controller,
          autofocus: false,
        ),
      ),
    ],
  );
}
