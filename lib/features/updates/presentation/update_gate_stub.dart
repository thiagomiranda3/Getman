import 'package:flutter/widgets.dart';

/// Web (and any non-`dart:io`) build: the updater is unavailable, so the gate
/// is a no-op. The real implementation lives in `update_gate_io.dart`.
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
