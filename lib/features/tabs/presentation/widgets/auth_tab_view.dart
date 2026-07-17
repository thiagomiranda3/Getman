import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/domain/entities/auth_config.dart';
import 'package:getman/core/domain/entities/request_config_entity.dart'
    show HttpRequestConfigEntity;
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/tab_variable_context_builder.dart';
import 'package:getman/core/ui/widgets/variable_highlight_controller.dart';
import 'package:getman/core/ui/widgets/variable_text_field.dart';
import 'package:getman/core/utils/equality.dart';
import 'package:getman/core/utils/layered_variable_context.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_event.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';

/// AUTH tab — a fixed-field form over [HttpRequestConfigEntity.auth]. Holds its
/// own controllers and suppresses echoes of its own emissions (same pattern as
/// `KeyValueListEditor`) so typing never loses focus across the bloc
/// round-trip. Field values may contain `{{env vars}}`; they resolve at send
/// time.
class AuthTabView extends StatefulWidget {
  const AuthTabView({required this.tabId, super.key});
  final String tabId;

  @override
  State<AuthTabView> createState() => _AuthTabViewState();
}

class _AuthTabViewState extends State<AuthTabView> {
  static const Map<AuthType, String> _labels = {
    AuthType.none: 'NO AUTH',
    AuthType.inherit: 'INHERIT FROM PARENT',
    AuthType.bearer: 'BEARER TOKEN',
    AuthType.basic: 'BASIC AUTH',
    AuthType.apiKey: 'API KEY',
  };

  late AuthType _type;
  late ApiKeyLocation _apiKeyLocation;
  late final VariableHighlightController _token;
  late final VariableHighlightController _username;
  late final VariableHighlightController _password;
  late final VariableHighlightController _apiKeyName;
  late final VariableHighlightController _apiKeyValue;
  late final FocusNode _tokenFocus;
  late final FocusNode _usernameFocus;
  late final FocusNode _passwordFocus;
  late final FocusNode _apiKeyNameFocus;
  late final FocusNode _apiKeyValueFocus;

  Map<String, String>? _lastEmitted;

  @override
  void initState() {
    super.initState();
    final auth = _currentAuth();
    _type = auth.type;
    _apiKeyLocation = auth.apiKeyLocation;
    _token = VariableHighlightController(text: auth.token);
    _username = VariableHighlightController(text: auth.username);
    _password = VariableHighlightController(text: auth.password);
    _apiKeyName = VariableHighlightController(text: auth.apiKeyName);
    _apiKeyValue = VariableHighlightController(text: auth.apiKeyValue);
    _tokenFocus = FocusNode();
    _usernameFocus = FocusNode();
    _passwordFocus = FocusNode();
    _apiKeyNameFocus = FocusNode();
    _apiKeyValueFocus = FocusNode();
  }

  AuthConfig _currentAuth() =>
      context
          .read<TabsBloc>()
          .state
          .tabs
          .byId(widget.tabId)
          ?.config
          .authConfig ??
      AuthConfig.none;

  @override
  void dispose() {
    _token.dispose();
    _username.dispose();
    _password.dispose();
    _apiKeyName.dispose();
    _apiKeyValue.dispose();
    _tokenFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _apiKeyNameFocus.dispose();
    _apiKeyValueFocus.dispose();
    super.dispose();
  }

  void _syncFrom(AuthConfig auth) {
    _type = auth.type;
    _apiKeyLocation = auth.apiKeyLocation;
    _setIfChanged(_token, auth.token);
    _setIfChanged(_username, auth.username);
    _setIfChanged(_password, auth.password);
    _setIfChanged(_apiKeyName, auth.apiKeyName);
    _setIfChanged(_apiKeyValue, auth.apiKeyValue);
  }

  void _setIfChanged(TextEditingController c, String value) {
    if (c.text != value) c.text = value;
  }

  AuthConfig _build() => AuthConfig(
    type: _type,
    token: _token.text,
    username: _username.text,
    password: _password.text,
    apiKeyName: _apiKeyName.text,
    apiKeyValue: _apiKeyValue.text,
    apiKeyLocation: _apiKeyLocation,
  );

  void _emit() {
    final bloc = context.read<TabsBloc>();
    final current = bloc.state.tabs.byId(widget.tabId);
    if (current == null) return;
    final map = _build().toMap();
    _lastEmitted = map;
    bloc.add(
      UpdateTab(current.copyWith(config: current.config.copyWith(auth: map))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;

    return BlocListener<TabsBloc, TabsState>(
      listenWhen: (prev, next) => !stringMapEquality.equals(
        prev.tabs.byId(widget.tabId)?.config.auth,
        next.tabs.byId(widget.tabId)?.config.auth,
      ),
      listener: (context, state) {
        final auth = state.tabs.byId(widget.tabId)?.config.auth ?? const {};
        // Ignore the echo of our own emission — it would reset controllers
        // mid-type and steal focus.
        if (_lastEmitted != null &&
            stringMapEquality.equals(auth, _lastEmitted)) {
          return;
        }
        setState(() {
          _syncFrom(AuthConfig.fromMap(auth));
          // Clear so a LATER external change equal to this stale value isn't
          // wrongly suppressed as if it were an echo of our own emission.
          _lastEmitted = null;
        });
      },
      child: TabVariableContextBuilder(
        tabId: widget.tabId,
        builder: (context, varContext) => ListView(
          padding: EdgeInsets.all(layout.pagePadding),
          children: [
            _label(context, 'AUTH TYPE'),
            SizedBox(height: layout.tabSpacing),
            DropdownButton<AuthType>(
              key: const ValueKey('auth_type_dropdown'),
              value: _type,
              isExpanded: true,
              items: [
                for (final t in AuthType.values)
                  DropdownMenuItem(value: t, child: Text(_labels[t]!)),
              ],
              onChanged: (next) {
                if (next == null) return;
                setState(() => _type = next);
                _emit();
              },
            ),
            SizedBox(height: layout.sectionSpacing),
            ..._fieldsFor(context, varContext),
          ],
        ),
      ),
    );
  }

  List<Widget> _fieldsFor(
    BuildContext context,
    LayeredVariableContext varContext,
  ) {
    switch (_type) {
      case AuthType.none:
        return [_hint(context, 'This request is sent without authentication.')];
      case AuthType.inherit:
        return [_hint(context, 'Inherits auth from the parent collection.')];
      case AuthType.bearer:
        return [_field(context, 'TOKEN', _token, _tokenFocus, varContext)];
      case AuthType.basic:
        return [
          _field(context, 'USERNAME', _username, _usernameFocus, varContext),
          _field(
            context,
            'PASSWORD',
            _password,
            _passwordFocus,
            varContext,
            obscure: true,
          ),
        ];
      case AuthType.apiKey:
        return [
          _field(context, 'KEY', _apiKeyName, _apiKeyNameFocus, varContext),
          _field(context, 'VALUE', _apiKeyValue, _apiKeyValueFocus, varContext),
          _label(context, 'ADD TO'),
          SizedBox(height: context.appLayout.tabSpacing),
          DropdownButton<ApiKeyLocation>(
            value: _apiKeyLocation,
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: ApiKeyLocation.header,
                child: Text('HEADER'),
              ),
              DropdownMenuItem(
                value: ApiKeyLocation.query,
                child: Text('QUERY PARAM'),
              ),
            ],
            onChanged: (next) {
              if (next == null) return;
              setState(() => _apiKeyLocation = next);
              _emit();
            },
          ),
        ];
    }
  }

  Widget _label(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: context.appLayout.fontSizeSmall,
      fontWeight: context.appTypography.titleWeight,
      color: Theme.of(context).colorScheme.onSurface,
    ),
  );

  Widget _hint(BuildContext context, String text) => Text(
    text,
    style: TextStyle(
      fontSize: context.appLayout.fontSizeNormal,
      fontWeight: context.appTypography.bodyWeight,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
    ),
  );

  Widget _field(
    BuildContext context,
    String label,
    VariableHighlightController controller,
    FocusNode focusNode,
    LayeredVariableContext variables, {
    bool obscure = false,
  }) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.only(bottom: layout.sectionSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, label),
          SizedBox(height: layout.tabSpacing),
          VariableTextField(
            fieldKey: ValueKey('auth_field_$label'),
            variables: variables,
            controller: controller,
            focusNode: focusNode,
            obscureText: obscure,
            onChanged: (_) => _emit(),
            style: TextStyle(
              fontSize: layout.fontSizeNormal,
              fontWeight: context.appTypography.titleWeight,
            ),
            decoration: InputDecoration(
              hintText: label,
              isDense: true,
              contentPadding: EdgeInsets.all(layout.isCompact ? 8 : 12),
            ),
          ),
        ],
      ),
    );
  }
}
