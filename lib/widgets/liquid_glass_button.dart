import 'dart:ui' show ImageFilter, ColorFilter, FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// ---------------------------------------------------------------------------
/// Liquid Glass — a reusable button component replicating Apple's iOS 26
/// "Liquid Glass" material (Flutter doesn't provide this, so it's hand-built).
///
/// Three variants live here:
///   • [LiquidGlassButton]         — primary action (large, tinted glass)
///   • [LiquidGlassButton.icon]    — circular icon button (small, light glass)
///   • [LiquidGlassSegmented]      — glass pill with a sliding glass "thumb"
///
/// Every variant shares the same glass recipe: a backdrop blur + vibrancy
/// (saturation/brightness boost), a near-clear tint, a specular top-edge rim,
/// a soft floating shadow, and Apple's continuous-corner (squircle) shape.
///
/// Performance: [BackdropFilter] is expensive, so [GlassQuality] watches frame
/// timings and disables blur app-wide under sustained jank (e.g. on low-end
/// Android), falling back to a more opaque translucent fill that still reads as
/// glass. Blur is only used on small/standalone surfaces — never stacked over
/// large areas.
/// ---------------------------------------------------------------------------

/// Global blur-quality switch. Monitors frame timings and flips [blurEnabled]
/// off if the app is dropping frames, so glass degrades gracefully.
class GlassQuality {
  GlassQuality._();
  static final GlassQuality instance = GlassQuality._();

  /// Widgets listen to this to decide whether to run a [BackdropFilter].
  final ValueNotifier<bool> blurEnabled = ValueNotifier<bool>(true);

  bool _monitoring = false;
  int _slowFrames = 0;

  /// Manually force blur off (e.g. a user "reduce effects" setting).
  void setBlurEnabled(bool value) => blurEnabled.value = value;

  void ensureMonitoring() {
    if (_monitoring) return;
    _monitoring = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
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
      blurEnabled.value = false;
    }
  }
}

/// Blur + saturation/brightness boost = the iOS "vibrancy" look.
ImageFilter _glassBlur(double sigma) {
  const double s = 1.45; // saturation multiplier
  final double b = AppColors.palette.isDark ? 12 : 3; // brightness lift
  const double lr = 0.2126, lg = 0.7152, lb = 0.0722; // Rec709 luminance
  final matrix = <double>[
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, b,
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, b,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, b,
    0, 0, 0, 1, 0,
  ];
  return ImageFilter.compose(
    outer: ColorFilter.matrix(matrix),
    inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
  );
}

// ===========================================================================
// Shared glass panel (visual only — no gesture handling)
// ===========================================================================
class _LiquidGlassPanel extends StatelessWidget {
  const _LiquidGlassPanel({
    required this.shape,
    required this.blurSigma,
    required this.child,
    this.tint,
    this.tintStrength = 0.82,
    this.shadows,
    this.overlay,
  });

  final ShapeBorder shape;
  final double blurSigma;

  /// null → neutral (near-clear) glass; else a colored glass.
  final Color? tint;
  final double tintStrength;
  final List<BoxShadow>? shadows;

  /// Content painted fully opaque on top of the glass (never blurred).
  final Widget child;

  /// Optional layer between the fill and the content (e.g. the press glow),
  /// clipped to the shape.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    GlassQuality.instance.ensureMonitoring();

    return ValueListenableBuilder<bool>(
      valueListenable: GlassQuality.instance.blurEnabled,
      builder: (context, blurAllowed, _) {
        final useBlur = blurAllowed && blurSigma > 0;

        final inner = Stack(
          children: [
            Positioned.fill(child: _fill(useBlur)),
            if (overlay != null)
              Positioned.fill(child: IgnorePointer(child: overlay!)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _RimPainter(shape)),
              ),
            ),
            child,
          ],
        );

        // Dynamic adaptation: BackdropFilter re-samples whatever is painted
        // behind it every frame, so the glass automatically picks up changes in
        // the background as the user scrolls (the blur adapts for free). We
        // intentionally do NOT run per-frame color-sampling of the backdrop to
        // retint the fill — that's expensive. The near-clear fill + vibrancy is
        // a deliberate, cheap approximation. If richer adaptation is ever
        // needed, drive [tint]/opacity from a ScrollController offset instead.
        final clipped = ClipPath(
          clipper: ShapeBorderClipper(shape: shape),
          child: useBlur
              ? BackdropFilter(filter: _glassBlur(blurSigma), child: inner)
              : inner,
        );

        return DecoratedBox(
          decoration: ShapeDecoration(shape: shape, shadows: shadows),
          child: clipped,
        );
      },
    );
  }

  Widget _fill(bool useBlur) {
    if (tint == null) {
      // Near-clear over blur; a more opaque surface when blur is unavailable
      // so content stays legible.
      final color = useBlur
          ? AppColors.glassFill
          : AppColors.surfaceElevated.withValues(alpha: 0.92);
      return ColoredBox(color: color);
    }
    final hi = (useBlur ? tintStrength + 0.06 : tintStrength + 0.15).clamp(0.0, 1.0);
    final lo = (useBlur ? tintStrength - 0.14 : tintStrength).clamp(0.0, 1.0);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint!.withValues(alpha: hi), tint!.withValues(alpha: lo)],
        ),
      ),
    );
  }
}

/// Specular rim: bright hairline along the top edge fading toward the bottom.
class _RimPainter extends CustomPainter {
  _RimPainter(this.shape);
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(0.8));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.glassHighlight, AppColors.glassStroke],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.shape != shape;
}

/// Soft radial "glow on touch", centered at the tap point.
class _GlowPainter extends CustomPainter {
  _GlowPainter({required this.center, required this.t, required this.color});
  final Offset center;
  final double t; // 0..1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final radius = size.longestSide * (0.55 + 0.35 * t);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.45 * t),
            color.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.t != t || old.center != center || old.color != color;
}

enum _Variant { primary, icon }

/// A tactile Liquid Glass button.
///
/// Use the default constructor for a primary action, or [LiquidGlassButton.icon]
/// for a circular icon button.
class LiquidGlassButton extends StatefulWidget {
  /// Primary action button — larger, tinted glass, indigo-tinted glow.
  const LiquidGlassButton({
    super.key,
    required Widget this.child,
    this.onPressed,
    this.tint,
    this.glowColor,
    this.blurSigma = 18,
    this.cornerRadius = 24,
    this.padding = const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
    this.expand = false,
    this.enabled = true,
    this.pressedScale = 0.965,
    this.semanticLabel,
  })  : _variant = _Variant.primary,
        icon = null,
        iconChild = null,
        size = 0,
        iconSize = 0,
        iconColor = null,
        filled = true;

  /// Circular icon button — smaller, lighter glass, neutral glow.
  ///
  /// Set [filled] false for a bare icon (e.g. a back button) with no glass.
  /// Pass [iconChild] to supply a self-animating icon (e.g. [AnimatedRotation]).
  const LiquidGlassButton.icon({
    super.key,
    this.onPressed,
    this.icon,
    this.iconChild,
    this.size = 44,
    this.iconSize = 20,
    this.iconColor,
    this.tint,
    this.glowColor,
    this.blurSigma = 14,
    this.filled = true,
    this.enabled = true,
    this.pressedScale = 0.94,
    this.semanticLabel,
  })  : _variant = _Variant.icon,
        child = null,
        cornerRadius = 0,
        padding = EdgeInsets.zero,
        expand = false,
        assert(icon != null || iconChild != null);

  final _Variant _variant;
  final VoidCallback? onPressed;
  final Color? tint;
  final Color? glowColor;
  final double blurSigma;
  final bool enabled;
  final double pressedScale;
  final String? semanticLabel;

  // Primary
  final Widget? child;
  final double cornerRadius;
  final EdgeInsetsGeometry padding;
  final bool expand;

  // Icon
  final IconData? icon;
  final Widget? iconChild;
  final double size;
  final double iconSize;
  final Color? iconColor;
  final bool filled;

  @override
  State<LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<LiquidGlassButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  bool _pressed = false;
  Offset _tapLocal = Offset.zero;

  bool get _interactive => widget.enabled && widget.onPressed != null;

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  void _onDown(TapDownDetails d) {
    _tapLocal = d.localPosition;
    setState(() => _pressed = true);
    _glow.forward();
    HapticFeedback.lightImpact();
  }

  void _onUp(TapUpDetails d) {
    setState(() => _pressed = false);
    _glow.reverse(); // glow fades out over ~260ms
    widget.onPressed?.call();
  }

  void _onCancel() {
    setState(() => _pressed = false);
    _glow.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final core = widget._variant == _Variant.icon
        ? _buildIcon()
        : _buildPrimary();

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive ? _onDown : null,
        onTapUp: _interactive ? _onUp : null,
        onTapCancel: _interactive ? _onCancel : null,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack, // springy release
          child: Opacity(
            opacity: widget.enabled ? 1.0 : 0.55,
            child: core,
          ),
        ),
      ),
    );
  }

  Widget _glowOverlay(Color color) {
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, _) => CustomPaint(
        painter: _GlowPainter(center: _tapLocal, t: _glow.value, color: color),
      ),
    );
  }

  Widget _buildPrimary() {
    final tint = widget.tint;
    final glow = widget.glowColor ?? widget.tint ?? AppColors.accent;

    final content = widget.expand
        ? SizedBox(
            width: double.infinity,
            child: Padding(
              padding: widget.padding,
              child: Center(child: widget.child),
            ),
          )
        : Padding(padding: widget.padding, child: widget.child);

    return _LiquidGlassPanel(
      shape: ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(widget.cornerRadius),
      ),
      blurSigma: widget.blurSigma,
      tint: tint,
      tintStrength: 0.86,
      shadows: AppColors.floatingShadow(
        blur: 26,
        y: 12,
        opacity: 0.30,
        spread: -6,
      ),
      overlay: _glowOverlay(glow),
      child: content,
    );
  }

  Widget _buildIcon() {
    final glyph = SizedBox(
      width: widget.size,
      height: widget.size,
      child: Center(
        child: widget.iconChild ??
            Icon(
              widget.icon,
              size: widget.iconSize,
              color: widget.iconColor ?? AppColors.textPrimary,
            ),
      ),
    );

    // Bare icon (e.g. back button): press feedback only, no glass surface.
    if (!widget.filled) return glyph;

    final glow = widget.glowColor ?? AppColors.accent;

    return _LiquidGlassPanel(
      shape: const CircleBorder(),
      blurSigma: widget.blurSigma,
      tint: widget.tint, // null → light neutral glass
      tintStrength: 0.5,
      shadows: AppColors.floatingShadow(
        blur: 14,
        y: 5,
        opacity: 0.20,
        spread: -3,
      ),
      overlay: _glowOverlay(glow),
      child: glyph,
    );
  }
}

// ===========================================================================
// Segmented / toggle variant — a glass pill with a sliding glass thumb
// ===========================================================================
class LiquidGlassSegmented extends StatelessWidget {
  const LiquidGlassSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.height = 46,
    this.thumbTint,
    this.blurSigma = 12,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final double height;

  /// Tint of the sliding thumb (defaults to the brand accent).
  final Color? thumbTint;
  final double blurSigma;

  static const double _pad = 4;

  @override
  Widget build(BuildContext context) {
    final tint = thumbTint ?? AppColors.accent;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = labels.length;
          final trackWidth = constraints.maxWidth;
          final thumbWidth = (trackWidth - _pad * 2) / n;

          return Stack(
            children: [
              // Track: translucent glass-lite pill (no backdrop blur here, so
              // we don't stack a blur under the thumb's blur).
              Positioned.fill(
                child: _LiquidGlassPanel(
                  shape: const StadiumBorder(),
                  blurSigma: 0,
                  child: const SizedBox.expand(),
                ),
              ),
              // Sliding glass thumb — real blur + rim + accent tint.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: _pad + selectedIndex * thumbWidth,
                top: _pad,
                bottom: _pad,
                width: thumbWidth,
                child: _LiquidGlassPanel(
                  shape: const StadiumBorder(),
                  blurSigma: blurSigma,
                  tint: tint,
                  tintStrength: 0.82,
                  shadows: AppColors.glow(tint, opacity: 0.32, blur: 12),
                  child: const SizedBox.expand(),
                ),
              ),
              // Labels on top (always crisp).
              Row(
                children: [
                  for (int i = 0; i < n; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == selectedIndex) return;
                          HapticFeedback.selectionClick();
                          onChanged(i);
                        },
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: i == selectedIndex
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
