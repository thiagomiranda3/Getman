// Barrel for the app's theme extensions. Each `ThemeExtension` lives in its
// own file under `extensions/`; this file re-exports them so the long-standing
// `import 'package:getman/core/theme/app_theme.dart';` keeps resolving every
// symbol (AppLayout / AppPalette / AppShape / AppTypography / AppDecoration /
// AppCopy + the `context.app*` accessors).
export 'package:getman/core/theme/extensions/app_copy.dart';
export 'package:getman/core/theme/extensions/app_decoration.dart';
export 'package:getman/core/theme/extensions/app_layout.dart';
export 'package:getman/core/theme/extensions/app_motion.dart';
export 'package:getman/core/theme/extensions/app_palette.dart';
export 'package:getman/core/theme/extensions/app_shape.dart';
export 'package:getman/core/theme/extensions/app_theme_access.dart';
export 'package:getman/core/theme/extensions/app_typography.dart';
