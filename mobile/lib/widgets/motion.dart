import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Cards fade in and slide up a little (200 ms) when they first appear.
/// Skipped when the OS asks for reduced motion.
///
/// A plain [AnimationController] rather than flutter_animate: flutter_animate
/// schedules a `Future.delayed` per widget even with no delay, which is wasteful
/// for dozens of list cards (flutter_animate is used for one-off effects such as
/// the splash title).
class Appear extends StatefulWidget {
  const Appear({super.key, required this.child});

  final Widget child;

  static const Duration duration = Duration(milliseconds: 200);

  @override
  State<Appear> createState() => _AppearState();
}

class _AppearState extends State<Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Appear.duration,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(_curve);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceEffects) {
      _controller.value = 1;
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
