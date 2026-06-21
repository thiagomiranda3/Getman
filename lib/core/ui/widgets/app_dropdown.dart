import 'package:flutter/material.dart';
import 'package:getman/core/theme/extensions/app_components.dart';
import 'package:getman/core/theme/extensions/app_theme_access.dart';

/// A generic dropdown that adapts a typed [options] list to the
/// [AppComponents.select] component slot and maps the chosen index back to [T].
class AppDropdown<T> extends StatelessWidget {
  const AppDropdown({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.labelOf,
    super.key,
    this.leadingOf,
    this.placeholder,
  });

  final List<T> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;
  final Widget Function(T)? leadingOf;
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexOf(value);
    return context.appComponents.select(
      context,
      AppSelectSpec(
        placeholder: placeholder,
        selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
        items: [
          for (final o in options)
            AppSelectItem(label: labelOf(o), leading: leadingOf?.call(o)),
        ],
        onSelected: (i) => onChanged(options[i]),
      ),
    );
  }
}
