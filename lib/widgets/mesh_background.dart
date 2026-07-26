import 'package:flutter/material.dart';

/// Deprecated: the animated [AuroraBackground] is now injected globally via
/// `MaterialApp.builder`, so per-screen backgrounds are no longer needed.
///
/// Kept as a no-op (renders nothing) so existing `Positioned.fill(MeshBackground())`
/// call sites keep compiling while the single global aurora shows through the
/// transparent scaffolds.
class MeshBackground extends StatelessWidget {
  const MeshBackground({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
