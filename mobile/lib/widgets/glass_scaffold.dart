import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../providers/theme_provider.dart';
import 'glass_card.dart';
import 'gradient_background.dart';

/// Every screen's frame: [GradientBackground] behind a transparent [Scaffold] with
/// a transparent app bar that always ends with the dark/light [ThemeToggleButton].
///
/// Screens shown inside the Home tabs pass `background: false` — the Home screen
/// already paints one background behind all of its tabs.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions = const <Widget>[],
    this.showAppBar = true,
    this.background = true,
    this.bottomNavigationBar,
  });

  final Widget body;
  final String? title;

  /// Custom title (overrides [title]).
  final Widget? titleWidget;
  final List<Widget> actions;
  final bool showAppBar;
  final bool background;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final Widget scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: showAppBar
          ? AppBar(
              title:
                  titleWidget ??
                  (title == null
                      ? null
                      : Text(title!, overflow: TextOverflow.ellipsis)),
              actions: <Widget>[...actions, const ThemeToggleButton()],
            )
          : null,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    );
    return background ? GradientBackground(child: scaffold) : scaffold;
  }
}

/// Sun / moon button that flips the theme (the switch animates over 400 ms).
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeProvider theme = context.watch<ThemeProvider>();
    final bool dark = theme.isDarkMode;
    return IconButton(
      key: const ValueKey<String>('theme-toggle'),
      tooltip: dark ? 'Light mode' : 'Dark mode',
      onPressed: theme.toggleTheme,
      icon: AnimatedSwitcher(
        duration: themeSwitchDuration,
        transitionBuilder: (Widget child, Animation<double> a) =>
            RotationTransition(
              turns: Tween<double>(begin: 0.75, end: 1).animate(a),
              child: FadeTransition(opacity: a, child: child),
            ),
        child: Icon(
          dark ? Icons.light_mode : Icons.dark_mode,
          key: ValueKey<bool>(dark),
        ),
      ),
    );
  }
}

/// Frosted bottom bar: a single blurred strip with a hairline top border.
class GlassBottomBar extends StatelessWidget {
  const GlassBottomBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: GlassCard.fillFor(p, opacity: p.glass.a + 0.06),
        border: Border(top: BorderSide(color: p.glassBorder)),
      ),
      child: child,
    );
    return ClipRect(
      child: context.reduceEffects
          ? bar
          : BackdropFilter.grouped(
              filter: ui.ImageFilter.blur(
                sigmaX: GlassCard.blurSigma,
                sigmaY: GlassCard.blurSigma,
              ),
              child: bar,
            ),
    );
  }
}
