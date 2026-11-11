import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Loading indicator: a glass pill with an accent gradient sweeping across it,
/// plus an optional message. With reduced motion the gradient stands still.
class LoadingWidget extends StatelessWidget {
  const LoadingWidget({
    super.key,
    this.message,
    this.size = 44,
    this.padding = const EdgeInsets.all(24),
  });

  final String? message;

  /// Height of the shimmer bar is `size / 4`, width `size * 3`.
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShimmerBar(width: size * 3, height: size / 4),
            if (message != null) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: context.palette.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Rounded bar with a moving accent -> purple highlight (repeats every 1.2 s).
class ShimmerBar extends StatefulWidget {
  const ShimmerBar({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<ShimmerBar> createState() => _ShimmerBarState();
}

class _ShimmerBarState extends State<ShimmerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceEffects) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, _) {
            final double x = _controller.value * 3 - 1.5; // -1.5 .. 1.5
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.height),
                border: Border.all(color: p.glassBorder),
                gradient: LinearGradient(
                  begin: Alignment(x - 1, 0),
                  end: Alignment(x + 1, 0),
                  colors: <Color>[p.glass, p.accent, p.gradientEnd, p.glass],
                  stops: const <double>[0, 0.4, 0.6, 1],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
