import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// How expensive the Liquid Glass look is allowed to be.
///
/// WHY THIS FILE EXISTS. Blur is the design system's entire cost centre, and it
/// was previously untunable and unmonitored where it mattered: every surface
/// hardcoded its own sigma, and the one auto-degrade mechanism ([GlassQuality])
/// lived inside `liquid_glass_button.dart` where only buttons consulted it. The
/// 66 `GlassContainer`/`GlassSurface` call sites and the full-screen
/// `AuroraBackground` ignored it entirely, so on a GPU-constrained device the
/// safety net tripped and changed nothing visible.
///
/// Both concerns now live here, deliberately together: [GlassBlur] is the
/// design-time dial, [GlassQuality] is the run-time one.

/// The design-time dial for blur cost.
class GlassBlur {
  const GlassBlur._();

  /// THE single tunable. Scales every backdrop blur in the app at once.
  ///
  /// 1.0 is the full intended Liquid Glass look. Lowering it reduces GPU cost
  /// roughly in proportion — blur cost scales with sigma — without touching a
  /// single call site or changing any layout. 0 disables backdrop blur entirely
  /// while leaving the translucent fills, rims and glows intact, which still
  /// reads as glass.
  ///
  /// Kept `const` on purpose: this is a product decision about the app's visual
  /// identity, not something to flip at runtime. Runtime adaptation is
  /// [GlassQuality]'s job.
  static const double intensity = 1.0;

  /// Full-screen blur behind every route, applied to the drifting aurora orbs.
  ///
  /// By far the most expensive single filter in the app: sigma this large over
  /// the whole viewport, recomputed on every frame because the orbs move. Only
  /// used while [GlassQuality] reports healthy performance.
  static const double auroraSigma = 70;

  /// Scale a requested sigma by [intensity].
  ///
  /// Clamped at the top because an ImageFilter sigma beyond ~200 is both
  /// meaningless and pathologically slow.
  static double sigma(double requested) {
    if (requested <= 0) return 0;
    return (requested * intensity).clamp(0.0, 200.0);
  }
}

/// Run-time blur switch. Watches real frame timings and turns backdrop blur off
/// app-wide once the device demonstrably cannot keep up.
///
/// MOVED, NOT REWRITTEN. This was `GlassQuality` in `liquid_glass_button.dart`;
/// the detection logic and thresholds are unchanged. What changed is who listens
/// to it — see [GlassBlur]'s note.
class GlassQuality {
  GlassQuality._();
  static final GlassQuality instance = GlassQuality._();

  /// Start in the degraded state, so the no-blur look can be inspected on a
  /// machine that is fast enough never to trigger the auto-degrade:
  ///
  ///     flutter run --dart-define=MYTRAIN_FORCE_NO_BLUR=true
  ///
  /// Exists because degraded mode is otherwise only reachable by owning a device
  /// slow enough to trip the detector, which made the too-transparent fills hard
  /// to reproduce and verify.
  static const bool forceNoBlur =
      bool.fromEnvironment('MYTRAIN_FORCE_NO_BLUR');

  /// Widgets listen to this to decide whether to run a `BackdropFilter`.
  final ValueNotifier<bool> blurEnabled = ValueNotifier<bool>(!forceNoBlur);

  bool _monitoring = false;
  int _slowFrames = 0;

  /// Manually force blur off (e.g. a user "reduce effects" setting).
  void setBlurEnabled(bool value) => blurEnabled.value = value;

  /// Begin watching frame timings. Idempotent, so every glass widget can call it
  /// without coordinating.
  void ensureMonitoring() {
    if (_monitoring) return;
    // Nothing to detect when the answer is already pinned.
    if (forceNoBlur) return;
    _monitoring = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      // A 60fps frame budget is ~16.7ms; treat >24ms as a dropped frame.
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      if (ms > 24) {
        _slowFrames++;
      } else if (_slowFrames > 0) {
        _slowFrames--;
      }
    }
    // Sustained jank → drop blur once (never auto-re-enable to avoid flapping).
    if (blurEnabled.value && _slowFrames > 12) {
      debugPrint('[GlassQuality] sustained jank detected — disabling backdrop '
          'blur app-wide (aurora falls back to a static gradient)');
      blurEnabled.value = false;
    }
  }

  /// Test hook: restore the initial state.
  @visibleForTesting
  void resetForTest() {
    blurEnabled.value = !forceNoBlur;
    _slowFrames = 0;
  }
}
