import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/network/cookie_store.dart';
import 'package:getman/core/network/network_cookie.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/ui/widgets/app_snack_bar.dart';
import 'package:getman/core/ui/widgets/confirm_dialog.dart';
import 'package:getman/core/ui/widgets/responsive_dialog.dart';

/// Lists every stored cookie grouped by domain and lets the user inspect and
/// delete individual cookies (or clear the whole jar). Reads the live
/// [CookieStore] snapshot; re-reads on each mutation.
class CookieManagerDialog extends StatefulWidget {
  const CookieManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    final store = context.read<CookieStore>();
    return showResponsiveDialog<void>(
      context,
      builder: (_) => RepositoryProvider.value(
        value: store,
        child: const CookieManagerDialog(),
      ),
    );
  }

  @override
  State<CookieManagerDialog> createState() => _CookieManagerDialogState();
}

class _CookieManagerDialogState extends State<CookieManagerDialog> {
  /// Cookies grouped by domain, domains sorted, cookies sorted by name/path.
  Map<String, List<NetworkCookie>> _grouped() {
    final store = context.read<CookieStore>();
    final groups = <String, List<NetworkCookie>>{};
    for (final c in store.all()) {
      groups.putIfAbsent(c.domain, () => []).add(c);
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.path.compareTo(b.path);
      });
    }
    return {
      for (final key in groups.keys.toList()..sort()) key: groups[key]!,
    };
  }

  Future<void> _delete(NetworkCookie cookie) async {
    final messenger = ScaffoldMessenger.of(context);
    final store = context.read<CookieStore>();
    await store.remove(cookie);
    if (!mounted) return;
    showAppSnackBarVia(messenger, 'Deleted ${cookie.name}');
    setState(() {});
  }

  void _confirmDelete(NetworkCookie cookie) {
    ConfirmDialog.show(
      context,
      title: 'Delete cookie?',
      message: 'Removes ${cookie.name} for ${cookie.domain}. This cannot be undone.',
      confirmLabel: 'DELETE',
      onConfirm: () => _delete(cookie),
    );
  }

  void _confirmClear() {
    final store = context.read<CookieStore>();
    ConfirmDialog.show(
      context,
      title: 'Clear cookies?',
      message: 'Removes every stored cookie from the jar. This cannot be undone.',
      confirmLabel: 'CLEAR',
      onConfirm: () async {
        final messenger = ScaffoldMessenger.of(context);
        await store.clear();
        if (!mounted) return;
        showAppSnackBarVia(messenger, 'Cookie jar cleared');
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    final grouped = _grouped();
    final isEmpty = grouped.isEmpty;

    return ResponsiveDialogScaffold(
      title: const Text('COOKIES'),
      content: SizedBox(
        width: layout.dialogWidth,
        height: 420,
        child: isEmpty ? _buildEmpty(context) : _buildList(context, grouped),
      ),
      actions: [
        if (!isEmpty)
          TextButton(
            onPressed: _confirmClear,
            child: Text(
              'CLEAR ALL',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: context.appTypography.titleWeight,
              ),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('DONE'),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    return Center(
      child: Text(
        'NO COOKIES STORED',
        style: TextStyle(
          fontSize: layout.fontSizeNormal,
          fontWeight: context.appTypography.displayWeight,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, Map<String, List<NetworkCookie>> grouped) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final entries = grouped.entries.toList();

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final domain = entries[index].key;
        final cookies = entries[index].value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(top: layout.tabSpacing, bottom: layout.tabSpacing / 2),
              child: Text(
                domain.toUpperCase(),
                style: TextStyle(
                  fontSize: layout.fontSizeSmall,
                  fontWeight: context.appTypography.displayWeight,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
            for (final c in cookies) _cookieTile(context, c),
          ],
        );
      },
    );
  }

  Widget _cookieTile(BuildContext context, NetworkCookie cookie) {
    final theme = Theme.of(context);
    final layout = context.appLayout;
    final flags = <String>[
      'path=${cookie.path}',
      if (cookie.secure) 'Secure',
      if (cookie.httpOnly) 'HttpOnly',
      if (cookie.expiresEpochMs == null) 'session',
    ].join(' · ');

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '${cookie.name} = ${cookie.value}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: context.appTypography.titleWeight,
          fontSize: layout.fontSizeNormal,
          color: theme.primaryColor,
        ),
      ),
      subtitle: Text(
        flags,
        style: TextStyle(
          fontSize: layout.fontSizeSmall,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, size: layout.iconSize, color: theme.colorScheme.error),
        tooltip: 'Delete cookie',
        onPressed: () => _confirmDelete(cookie),
      ),
    );
  }
}
