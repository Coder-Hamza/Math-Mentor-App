import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Frosted-glass surface: translucent fill, gradient hairline border, soft shadow
/// and (optionally) a backdrop blur.
///
/// Performance: blur is the expensive part, so
/// * it uses [BackdropFilter.grouped], which shares one backdrop read with every other
///   glass surface under the same [BackdropGroup] (one per [GradientBackground]);
/// * long lists pass `blur: false` — over the already-soft background the fill alone
///   reads as glass;
/// * it is switched off entirely when the OS asks for reduced motion/effects
///   ([PaletteContext.reduceEffects]), the low-end fallback.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.borderRadius = 20,
    this.opacity,
    this.blur = true,
    this.tint,
    this.borderColor,
    this.glowColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  /// Overrides the palette's glass opacity (0-1).
  final double? opacity;
  final bool blur;

  /// Colours the glass, e.g. red for weak topics, green for a correct answer.
  final Color? tint;
  final Color? borderColor;

  /// Coloured outer glow instead of the neutral shadow.
  final Color? glowColor;
  final VoidCallback? onTap;

  static const double blurSigma = 10;

  /// The fill this card paints (exposed for tests).
  static Color fillFor(GlassPalette p, {Color? tint, double? opacity}) {
    final Color base = opacity == null
        ? p.glass
        : p.glass.withValues(alpha: opacity);
    return tint == null
        ? base
        : Color.alphaBlend(tint.withValues(alpha: 0.16), base);
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final BorderRadius radius = BorderRadius.circular(borderRadius);

    // A transparent Material inside the fill, so ripples (InkWell, ListTile,
    // ExpansionTile) draw on top of the glass instead of hidden underneath it.
    final Widget padded = Padding(padding: padding, child: child);
    final Widget content = Material(
      type: MaterialType.transparency,
      child: onTap == null
          ? padded
          : InkWell(onTap: onTap, borderRadius: radius, child: padded),
    );

    final Widget surface = CustomPaint(
      foregroundPainter: _GradientBorderPainter(
        radius: borderRadius,
        colors: borderColor == null
            ? <Color>[p.glassBorder, p.glassBorder.withValues(alpha: 0.04)]
            : <Color>[borderColor!, borderColor!.withValues(alpha: 0.35)],
        width: borderColor == null ? 1 : 1.5,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: fillFor(p, tint: tint, opacity: opacity),
        ),
        child: content,
      ),
    );

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glowColor?.withValues(alpha: 0.35) ?? p.shadow,
              blurRadius: glowColor == null ? 18 : 24,
              offset: glowColor == null ? const Offset(0, 6) : Offset.zero,
              // Only outside the card: through translucent glass a normal
              // shadow would grey the interior.
              blurStyle: BlurStyle.outer,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: blur && !context.reduceEffects
              ? BackdropFilter.grouped(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma,
                    sigmaY: blurSigma,
                  ),
                  child: surface,
                )
              : surface,
        ),
      ),
    );
  }
}

/// Hairline border that fades from top-left to bottom-right, like light on glass.
class _GradientBorderPainter extends CustomPainter {
  const _GradientBorderPainter({
    required this.radius,
    required this.colors,
    required this.width,
  });

  final double radius;
  final List<Color> colors;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(width / 2),
        Radius.circular(radius - width / 2),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GradientBorderPainter old) =>
      old.radius != radius || old.width != width || old.colors != colors;
}

/// Small translucent pill: difficulty, verification, points, chips.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.textKey,
  });

  final String label;
  final Color color;
  final IconData? icon;

  /// Key for the label [Text] (tests look texts up by key).
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            key: textKey,
            style: Theme.of(context).textTheme.labelMedium
                .weight(FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Text painted with the accent -> purple gradient (via [ShaderMask]).
class GradientText extends StatelessWidget {
  const GradientText(
    this.text, {
    super.key,
    this.style,
    this.gradient,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final Gradient? gradient;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final Gradient g = gradient ?? context.palette.accentGradient;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect bounds) =>
          g.createShader(Offset.zero & bounds.size),
      child: Text(
        text,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
        // srcIn keeps only the gradient where the glyphs are; colour must be opaque.
        style: (style ?? const TextStyle()).copyWith(color: Colors.white),
      ),
    );
  }
}

/// Shrinks its child to 95% while pressed (100 ms), for a tactile feel.
class TapScale extends StatefulWidget {
  const TapScale({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<TapScale> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (widget.enabled && pressed != _pressed) {
      setState(() => _pressed = pressed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Full-width electric blue -> purple button with a soft glow.
///
/// Built on a transparent [FilledButton], so semantics, focus, disabled state and
/// ripple all behave like a normal Material button.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
    this.glow = true,
    this.height = 52,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final bool glow;
  final double height;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final bool enabled = onPressed != null;
    final BorderRadius radius = BorderRadius.circular(16);
    final ButtonStyle style = FilledButton.styleFrom(
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white70,
      shadowColor: Colors.transparent,
      minimumSize: Size.fromHeight(height),
      shape: RoundedRectangleBorder(borderRadius: radius),
      textStyle: const TextStyle(
        fontFamily: appFontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    );
    return TapScale(
      enabled: enabled,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: p.accentGradient,
            borderRadius: radius,
            boxShadow: glow && enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: p.accent.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: icon == null
              ? FilledButton(onPressed: onPressed, style: style, child: child)
              : FilledButton.icon(
                  onPressed: onPressed,
                  style: style,
                  icon: icon,
                  label: child,
                ),
        ),
      ),
    );
  }
}

/// Circle filled with the accent gradient (unit numbers, step numbers).
class GradientCircle extends StatelessWidget {
  const GradientCircle({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: context.palette.accentGradient,
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        child: child,
      ),
    );
  }
}

/// Section heading in gradient text, with an optional leading icon.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 20, color: context.palette.accent),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GradientText(
              title,
              style: Theme.of(context).textTheme.titleMedium
                  .weight(FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
