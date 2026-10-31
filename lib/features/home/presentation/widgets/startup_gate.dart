// Shows the saved theme before opening feature stores or restoring workspace
// access. The initializer starts after the first frame, exactly once; no
// provider/shortcut can send requests before cookies and environments are ready.
// Failures keep the window visible instead of leaving an invisible failed boot.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/theme_registry.dart';
import 'package:getman/features/settings/domain/entities/settings_entity.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({
    required this.settings,
    required this.initialize,
    super.key,
  });

  final SettingsEntity settings;
  final Future<Widget> Function() initialize;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  Widget? _app;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_initialize());
    });
  }

  Future<void> _initialize() async {
    try {
      // Yield the post-frame turn before starting storage work.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      final app = await widget.initialize();
      if (mounted) setState(() => _app = app);
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'startup'),
      );
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_app != null) return _app!;
    final settings = widget.settings;
    return MaterialApp(
      title: 'GETMAN',
      debugShowCheckedModeBanner: false,
      themeAnimationDuration: Duration.zero,
      theme: resolveThemeData(
        settings.themeId,
        settings.isDarkMode ? Brightness.dark : Brightness.light,
        isCompact: settings.isCompactMode,
      ),
      home: Scaffold(
        body: Center(
          child: _failed
              ? const Text('Unable to start Getman. Please restart the app.')
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
