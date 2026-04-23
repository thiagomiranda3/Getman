import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:getman/core/navigation/intents.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/name_prompt_dialog.dart';
import 'package:getman/core/ui/widgets/splitter.dart';
import 'package:getman/core/utils/json_utils.dart';
import 'package:getman/features/collections/domain/logic/collections_tree_helper.dart';
import 'package:getman/features/collections/presentation/bloc/collections_bloc.dart';
import 'package:getman/features/collections/presentation/bloc/collections_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/request_config_section.dart';
import 'package:getman/features/tabs/presentation/widgets/response_section.dart';
import 'package:getman/features/tabs/presentation/widgets/url_bar.dart';

const double _splitMin = 0.1;
const double _splitMax = 0.9;
const int _splitFlexUnits = 1000;

int _ratioToFlex(double ratio) => (ratio.clamp(_splitMin, _splitMax) * _splitFlexUnits).toInt();

class RequestView extends StatefulWidget {
  final String tabId;
  const RequestView({super.key, required this.tabId});

  @override
  State<RequestView> createState() => _RequestViewState();
}

class _RequestViewState extends State<RequestView> {
  late final CodeLineEditingController _bodyController;
  late final CodeLineEditingController _responseController;
  double? _localSplitRatio;

  @override
  void initState() {
    super.initState();
    _bodyController = CodeLineEditingController();
    _responseController = CodeLineEditingController();
    _bodyController.addListener(_onBodyChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tab = context.read<TabsBloc>().state.tabs.byId(widget.tabId);
    if (tab != null && _bodyController.text != tab.config.body) {
      _bodyController.text = tab.config.body;
    }
  }

  void _onBodyChanged() {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;
    final newText = _bodyController.text;
    if (tab.config.body == newText) return;

    tabsBloc.add(UpdateTab(
      tab.copyWith(config: tab.config.copyWith(body: newText)),
    ));
  }

  @override
  void dispose() {
    _bodyController.removeListener(_onBodyChanged);
    _bodyController.dispose();
    _responseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        final layout = context.appLayout;

        return BlocConsumer<TabsBloc, TabsState>(
          listenWhen: (prev, next) {
            final p = prev.tabs.byId(widget.tabId);
            final n = next.tabs.byId(widget.tabId);
            return p?.config.body != n?.config.body;
          },
          listener: (context, state) {
            final tab = state.tabs.byId(widget.tabId);
            if (tab != null && _bodyController.text != tab.config.body) {
              _bodyController.text = tab.config.body;
            }
          },
          buildWhen: (prev, next) {
            if (prev.isLoading != next.isLoading) return true;
            final prevExists = prev.tabs.any((t) => t.tabId == widget.tabId);
            final nextExists = next.tabs.any((t) => t.tabId == widget.tabId);
            return prevExists != nextExists;
          },
          builder: (context, tabsState) {
            if (tabsState.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final tab = tabsState.tabs.byId(widget.tabId);
            if (tab == null) return const SizedBox.shrink();

            return Actions(
              actions: <Type, Action<Intent>>{
                SaveRequestIntent: CallbackAction<SaveRequestIntent>(
                  onInvoke: (_) => _handleSave(context),
                ),
                BeautifyJsonIntent: CallbackAction<BeautifyJsonIntent>(
                  onInvoke: (_) async {
                    final prettified = await JsonUtils.prettify(_bodyController.text);
                    _bodyController.text = prettified;
                    return null;
                  },
                ),
              },
              child: Focus(
                autofocus: true,
                child: Padding(
                    padding: EdgeInsets.all(layout.pagePadding),
                    child: Column(
                      children: [
                        UrlBar(tabId: widget.tabId, onSave: () => _handleSave(context)),
                        SizedBox(height: layout.sectionSpacing),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final totalSize = settings.isVerticalLayout ? constraints.maxHeight : constraints.maxWidth;
                              final currentRatio = _localSplitRatio ?? settings.splitRatio;

                              return Flex(
                                direction: settings.isVerticalLayout ? Axis.vertical : Axis.horizontal,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Flexible(
                                    flex: _ratioToFlex(currentRatio),
                                    child: RequestConfigSection(tabId: widget.tabId, bodyController: _bodyController),
                                  ),
                                  Splitter(
                                    isVertical: settings.isVerticalLayout,
                                    onUpdate: (delta) {
                                      setState(() {
                                        final base = _localSplitRatio ?? settings.splitRatio;
                                        _localSplitRatio = (base + delta / totalSize).clamp(_splitMin, _splitMax);
                                      });
                                    },
                                    onEnd: () {
                                      final committed = _localSplitRatio;
                                      if (committed == null) return;
                                      context.read<SettingsBloc>().add(UpdateSplitRatio(committed));
                                      setState(() => _localSplitRatio = null);
                                    },
                                  ),
                                  Flexible(
                                    flex: _ratioToFlex(1 - currentRatio),
                                    child: ResponseSection(tabId: widget.tabId, responseController: _responseController),
                                  ),
                                ],
                              );
                            }
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
          },
        );
      },
    );
  }

  void _handleSave(BuildContext context) {
    final tabsBloc = context.read<TabsBloc>();
    final tab = tabsBloc.state.tabs.byId(widget.tabId);
    if (tab == null) return;

    final collectionsBloc = context.read<CollectionsBloc>();
    final theme = Theme.of(context);
    final layout = context.appLayout;

    final savedNode = tab.collectionNodeId == null
        ? null
        : CollectionsTreeHelper.findNode(collectionsBloc.state.collections, tab.collectionNodeId!);

    if (savedNode != null) {
      collectionsBloc.add(UpdateNodeRequest(
        tab.collectionNodeId!,
        tab.config.copyWith(),
      ));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: theme.primaryColor,
          elevation: 0,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.appShape.panelRadius),
            side: BorderSide(color: theme.dividerColor, width: layout.borderThick),
          ),
          content: Text('REQUEST UPDATED!', style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: context.appLayout.fontSizeNormal, fontWeight: context.appTypography.displayWeight)),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    if (tab.collectionNodeId != null) {
      // Node was deleted while the tab was open — drop the stale link
      // (copyWith's sentinel pattern lets `null` actually clear the fields).
      tabsBloc.add(UpdateTab(
        tab.copyWith(collectionNodeId: null, collectionName: null),
      ));
    }
    _showSaveDialog(context, tab);
  }

  void _showSaveDialog(BuildContext context, HttpRequestTabEntity tab) {
    final collectionsBloc = context.read<CollectionsBloc>();
    final tabsBloc = context.read<TabsBloc>();
    NamePromptDialog.show(
      context,
      title: 'SAVE TO COLLECTION',
      initialText: 'NEW REQUEST',
      hintText: 'REQUEST NAME',
      onConfirm: (name) {
        collectionsBloc.add(SaveRequestToCollection(name, tab.config.copyWith()));
        tabsBloc.add(UpdateTab(tab.copyWith(collectionName: name)));
      },
    );
  }
}
