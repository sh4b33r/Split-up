// Motion toolkit: small, reusable animations used across the app.
//
// Everything here checks the system "reduce motion" setting
// (MediaQuery.disableAnimations) and falls back to a static widget.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:get/get.dart';

import '../utils/money.dart';

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

const _easeOut = Curves.easeOutCubic;

extension EnterAnimation on Widget {
  /// Fades and slides the widget in. [index] staggers items in a list.
  Widget enter(BuildContext context, {int index = 0, double dy = 0.06, double dx = 0, Duration? delay}) {
    if (reduceMotion(context)) return this;
    final d = delay ?? Duration(milliseconds: 40 * math.min(index, 10));
    return animate(delay: d)
        .fadeIn(duration: 380.ms, curve: _easeOut)
        .slide(begin: Offset(dx, dy), end: Offset.zero, duration: 420.ms, curve: _easeOut);
  }

  /// A small "pop" for badges, chips and icons that just appeared.
  Widget pop(BuildContext context, {Duration delay = Duration.zero}) {
    if (reduceMotion(context)) return this;
    return animate(delay: delay)
        .fadeIn(duration: 200.ms)
        .scaleXY(begin: 0.6, end: 1, duration: 420.ms, curve: Curves.elasticOut);
  }
}

/// Shrinks its child slightly while pressed, like a physical button.
/// Taps still go to the child's own InkWell / button.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child, this.scale = 0.97});
  final Widget child;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Money that counts up (or down) to its new value.
class MoneyCountUp extends StatefulWidget {
  const MoneyCountUp({
    super.key,
    required this.minor,
    required this.currency,
    this.style,
    this.currencyStyle,
    this.absolute = false,
    this.showCurrency = true,
  });
  final int minor;
  final String currency;
  final TextStyle? style;
  final TextStyle? currencyStyle;

  /// Show the value without a minus sign.
  final bool absolute;
  final bool showCurrency;

  @override
  State<MoneyCountUp> createState() => _MoneyCountUpState();
}

class _MoneyCountUpState extends State<MoneyCountUp> {
  int _from = 0;

  @override
  void didUpdateWidget(MoneyCountUp old) {
    super.didUpdateWidget(old);
    if (old.minor != widget.minor) _from = old.minor;
  }

  Widget _text(int value) {
    final v = widget.absolute ? value.abs() : value;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: Money.number(v, widget.currency), style: widget.style),
          if (widget.showCurrency) TextSpan(text: ' ${widget.currency}', style: widget.currencyStyle ?? widget.style),
        ],
      ),
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      maxLines: 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return _text(widget.minor);
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.minor),
      tween: Tween(begin: _from.toDouble(), end: widget.minor.toDouble()),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutExpo,
      builder: (context, v, _) => _text(v.round()),
    );
  }
}

/// A grey placeholder block with a moving shine, shown while data loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(radius)),
    );
    if (reduceMotion(context)) return box;
    return box
        .animate(onPlay: (c) => c.repeat())
        .shimmer(duration: 1300.ms, color: scheme.surfaceContainerLowest.withValues(alpha: 0.7));
  }
}

/// A list of card-shaped placeholders.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4, this.padding = const EdgeInsets.all(16), this.height = 96});
  final int count;
  final EdgeInsets padding;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => SkeletonCard(height: height),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 96});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: Card(
        child: SizedBox(
          height: height,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Skeleton(width: 44, height: 44, radius: 14),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Skeleton(width: 140, height: 14), SizedBox(height: 10), Skeleton(width: 90, height: 11)],
                  ),
                ),
                Skeleton(width: 64, height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon that gently floats up and down, for empty states.
class FloatingIcon extends StatelessWidget {
  const FloatingIcon({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reduceMotion(context)) return child;
    return child
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: 0, end: -7, duration: 1700.ms, curve: Curves.easeInOut);
  }
}

/// Page transition: the new screen fades in while rising slightly; the old
/// one fades back a little.
class SoftRiseTransition extends CustomTransition {
  @override
  Widget buildTransition(
    BuildContext context,
    Curve? curve,
    Alignment? alignment,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion(context)) return FadeTransition(opacity: animation, child: child);
    final inCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.6).animate(outCurve),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.97).animate(outCurve),
        child: FadeTransition(
          opacity: inCurve,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(inCurve),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A burst of confetti over the whole screen, for "all settled" moments.
class Confetti {
  Confetti._();

  static void burst(BuildContext context) {
    HapticFeedback.mediumImpact();
    if (reduceMotion(context)) return;
    // Get.context sits above the Navigator's overlay, so use the navigator's own.
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ?? Get.key.currentState?.overlay;
    if (overlay == null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(child: _ConfettiLayer(onDone: () => entry.remove())),
    );
    overlay.insert(entry);
  }
}

class _ConfettiLayer extends StatefulWidget {
  const _ConfettiLayer({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_ConfettiLayer> createState() => _ConfettiLayerState();
}

class _Particle {
  _Particle(math.Random r, this.color)
    : x = 0.5 + (r.nextDouble() - 0.5) * 0.3,
      vx = (r.nextDouble() - 0.5) * 1.4,
      vy = -(0.9 + r.nextDouble() * 0.9),
      spin = (r.nextDouble() - 0.5) * 14,
      size = 6 + r.nextDouble() * 6,
      round = r.nextBool();
  final double x, vx, vy, spin, size;
  final bool round;
  final Color color;
}

class _ConfettiLayerState extends State<_ConfettiLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
    ..forward().whenComplete(widget.onDone);
  late final List<_Particle> _particles;

  static const _colors = [
    Color(0xFF12B886),
    Color(0xFFFFC53D),
    Color(0xFF4DABF7),
    Color(0xFFFF6B6B),
    Color(0xFFB197FC),
    Color(0xFF38D9A9),
    Color(0xFFFF922B),
  ];

  @override
  void initState() {
    super.initState();
    final r = math.Random();
    _particles = [for (var i = 0; i < 90; i++) _Particle(r, _colors[i % _colors.length])];
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => CustomPaint(size: Size.infinite, painter: _ConfettiPainter(_particles, _c.value)),
  );
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.particles, this.t);
  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final time = t * 2.2;
    final fade = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);
    for (final p in particles) {
      final x = (p.x + p.vx * time * 0.35) * size.width;
      final y = size.height * 0.42 + (p.vy * time + 0.9 * time * time) * size.height * 0.32;
      paint.color = p.color.withValues(alpha: fade.clamp(0, 1));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * time);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size * 0.42, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}

/// Slowly drifting soft colour blobs, for the sign-in background.
class DriftingBlobs extends StatefulWidget {
  const DriftingBlobs({super.key});

  @override
  State<DriftingBlobs> createState() => _DriftingBlobsState();
}

class _DriftingBlobsState extends State<DriftingBlobs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = [
      scheme.primary.withValues(alpha: dark ? 0.32 : 0.22),
      const Color(0xFF4DABF7).withValues(alpha: dark ? 0.22 : 0.16),
      const Color(0xFFFFC53D).withValues(alpha: dark ? 0.16 : 0.18),
    ];
    final still = reduceMotion(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = still ? 0.0 : _c.value * 2 * math.pi;
        return LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            Widget blob(int i, double cx, double cy, double r) {
              final dx = math.sin(t + i * 2.1) * w * 0.08;
              final dy = math.cos(t * 0.8 + i * 1.3) * h * 0.05;
              return Positioned(
                left: cx * w - r + dx,
                top: cy * h - r + dy,
                child: Container(
                  width: r * 2,
                  height: r * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [colors[i], colors[i].withValues(alpha: 0)]),
                  ),
                ),
              );
            }

            return Stack(
              children: [blob(0, 0.15, 0.08, w * 0.75), blob(1, 0.95, 0.35, w * 0.65), blob(2, 0.3, 0.95, w * 0.7)],
            );
          },
        );
      },
    );
  }
}

/// A circular progress ring that animates to [value] (0..1).
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.color,
    this.size = 64,
    this.stroke = 7,
    this.child,
  });
  final double value;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, track, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track, this.stroke);
  final double v;
  final Color color, track;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, 2 * math.pi, false, p..color = track);
    if (v > 0) canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.track != track;
}
