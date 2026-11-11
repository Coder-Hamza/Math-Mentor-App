import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Screen background: the palette's vertical gradient plus three soft "glass orbs"
/// (accent top-right, secondary bottom-left, a faint glow in the centre).
///
/// The orbs are radial gradients, not real blurs: they look the same as a circle
/// blurred by 60-80 px but cost almost nothing to paint. They drift into place
/// once when the screen opens (1.2 s) and then stay still, so an idle screen never
/// repaints — important because every glass card above re-blurs whatever moves
/// behind it. Colours follow the theme switch through [GlassPalette.lerp].
///
/// Also provides the [BackdropGroup] that every [GlassCard] on the screen shares.
class GradientBackground extends StatefulWidget {
  const GradientBackground({super.key, required this.child});

  final Widget child;

  static const Duration entryDuration = Duration(milliseconds: 1200);

  @override
  State<GradientBackground> createState() => _GradientBackgroundState();
}

class _GradientBackgroundState extends State<GradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
    vsync: this,
    duration: GradientBackground.entryDuration,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _entry,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceEffects) {
      _entry.value = 1;
    } else if (_entry.isDismissed) {
      _entry.forward();
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      key: const ValueKey<String>('gradient-background'),
      decoration: BoxDecoration(gradient: p.backgroundGradient),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _t,
              builder: (BuildContext context, _) => CustomPaint(
                painter: _OrbsPainter(
                  progress: _t.value,
                  accent: p.accent,
                  secondary: p.secondary,
                  glow: p.gradientEnd,
                  strength: dark ? 1 : 0.7,
                ),
              ),
            ),
          ),
          BackdropGroup(child: widget.child),
        ],
      ),
    );
  }
}

class _OrbsPainter extends CustomPainter {
  const _OrbsPainter({
    required this.progress,
    required this.accent,
    required this.secondary,
    required this.glow,
    required this.strength,
  });

  final double progress;
  final Color accent;
  final Color secondary;
  final Color glow;
  final double strength;

  void _orb(
    Canvas canvas,
    Offset centre,
    double radius,
    Color color,
    double alpha,
  ) {
    final double a = alpha * strength * progress;
    final Rect rect = Rect.fromCircle(center: centre, radius: radius);
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: a),
            color.withValues(alpha: a * 0.4),
            color.withValues(alpha: 0),
          ],
          stops: const <double>[0, 0.45, 1],
        ).createShader(rect),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double drift = (1 - progress) * 40;
    // Top right: accent orb (~blur 60).
    _orb(
      canvas,
      Offset(size.width * 0.9 + drift, size.height * 0.1 - drift),
      size.width * 0.55,
      accent,
      0.38,
    );
    // Bottom left: secondary orb (~blur 80).
    _orb(
      canvas,
      Offset(size.width * 0.05 - drift, size.height * 0.88 + drift),
      size.width * 0.65,
      secondary,
      0.26,
    );
    // Centre: subtle purple glow.
    _orb(
      canvas,
      Offset(size.width * 0.5, size.height * 0.48),
      size.width * 0.6,
      glow,
      0.12,
    );
  }

  @override
  bool shouldRepaint(_OrbsPainter old) =>
      old.progress != progress ||
      old.accent != accent ||
      old.secondary != secondary ||
      old.glow != glow ||
      old.strength != strength;
}
