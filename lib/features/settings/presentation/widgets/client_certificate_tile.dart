import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:getman/features/settings/presentation/bloc/settings_event.dart';
import 'package:getman/features/settings/presentation/bloc/settings_state.dart';

/// Settings control for a client certificate (mutual TLS). Picks a PEM cert +
/// PEM key file and an optional passphrase; the native Dio adapter builds a
/// SecurityContext from these. Desktop/mobile only — browsers own TLS, so the
/// web build shows a notice instead.
class ClientCertificateTile extends StatefulWidget {
  const ClientCertificateTile({super.key});

  @override
  State<ClientCertificateTile> createState() => _ClientCertificateTileState();
}

class _ClientCertificateTileState extends State<ClientCertificateTile> {
  late final TextEditingController _passphraseController;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsBloc>().state.settings;
    _passphraseController = TextEditingController(
      text: s.clientCertPassphrase ?? '',
    );
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  Future<void> _pick(BuildContext context, {required bool isCert}) async {
    final settings = context.read<SettingsBloc>();
    final current = settings.state.settings;
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: isCert
          ? 'Choose certificate (PEM)'
          : 'Choose private key (PEM)',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    settings.add(
      UpdateClientCertificate(
        certPath: isCert ? path : current.clientCertPath,
        keyPath: isCert ? current.clientKeyPath : path,
        passphrase: current.clientCertPassphrase,
      ),
    );
  }

  void _clear(BuildContext context) {
    _passphraseController.clear();
    context.read<SettingsBloc>().add(const UpdateClientCertificate());
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final theme = Theme.of(context);

    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (p, n) =>
          p.settings.clientCertPath != n.settings.clientCertPath ||
          p.settings.clientKeyPath != n.settings.clientKeyPath,
      builder: (context, state) {
        final certPath = state.settings.clientCertPath;
        final keyPath = state.settings.clientKeyPath;
        final hasAny = certPath != null || keyPath != null;

        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: layout.inputPadding,
            vertical: layout.tabSpacing,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: layout.iconSize),
                  SizedBox(width: layout.tabSpacing),
                  Text(
                    'CLIENT CERTIFICATE (mTLS)',
                    style: TextStyle(
                      fontSize: layout.fontSizeNormal,
                      fontWeight: context.appTypography.titleWeight,
                    ),
                  ),
                ],
              ),
              SizedBox(height: layout.tabSpacing),
              if (kIsWeb)
                Text(
                  'Available in the desktop/mobile app.',
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                )
              else ...[
                Text(
                  certPath == null
                      ? 'Cert: not set'
                      : 'Cert: ${_fileName(certPath)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                Text(
                  keyPath == null
                      ? 'Key: not set'
                      : 'Key: ${_fileName(keyPath)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: layout.fontSizeSmall,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                SizedBox(height: layout.tabSpacing),
                TextField(
                  controller: _passphraseController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'KEY PASSPHRASE (optional)',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: layout.inputPadding,
                      vertical: layout.inputPaddingVertical,
                    ),
                  ),
                  onChanged: (val) {
                    final trimmed = val.trim();
                    context.read<SettingsBloc>().add(
                      UpdateClientCertificate(
                        certPath: certPath,
                        keyPath: keyPath,
                        passphrase: trimmed.isEmpty ? null : trimmed,
                      ),
                    );
                  },
                ),
                SizedBox(height: layout.tabSpacing),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _pick(context, isCert: true),
                      child: const Text('CHOOSE CERT'),
                    ),
                    TextButton(
                      onPressed: () => _pick(context, isCert: false),
                      child: const Text('CHOOSE KEY'),
                    ),
                    if (hasAny)
                      TextButton(
                        onPressed: () => _clear(context),
                        child: const Text('CLEAR'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
