import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/routes.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_background.dart';
import '../widgets/loading_widget.dart';

/// Checks the stored session, then goes to Home (valid token) or Login.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final AuthProvider auth = context.read<AuthProvider>();
    await auth.bootstrap();
    if (!mounted) {
      return;
    }
    final String next = auth.status == AuthStatus.authenticated
        ? Routes.home
        : Routes.login;
    await Navigator.of(context).pushReplacementNamed(next);
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool still = context.reduceEffects;
    Widget title = GradientText(
      AppStrings.appName,
      style: text.headlineMedium.weight(FontWeight.w700),
    );
    if (!still) {
      title = title
          .animate()
          .fadeIn(duration: 500.ms)
          .scaleXY(begin: 0.9, end: 1, duration: 500.ms, curve: Curves.easeOut)
          .shimmer(duration: 1400.ms, color: Colors.white);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const FloatingMathSymbols(),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const GlassCard(
                    key: ValueKey<String>('splash-logo-card'),
                    margin: EdgeInsets.zero,
                    padding: EdgeInsets.all(20),
                    borderRadius: 32,
                    child: AppLogo(size: 88),
                  ),
                  const SizedBox(height: 24),
                  title,
                  Text(
                    AppStrings.tagline,
                    style: text.bodyMedium?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  const LoadingWidget(size: 40, padding: EdgeInsets.zero),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brand mark: a gradient rounded square with a calculator glyph.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: p.accentGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: p.accent.withValues(alpha: 0.4),
            blurRadius: size * 0.3,
          ),
        ],
      ),
      child: Icon(
        Icons.calculate_rounded,
        size: size * 0.6,
        color: Colors.white,
      ),
    );
  }
}

/// Faint maths symbols bobbing gently behind the splash content. Purely
/// decorative (excluded from semantics); still when the OS asks for less motion.
class FloatingMathSymbols extends StatefulWidget {
  const FloatingMathSymbols({super.key});

  static const List<String> symbols = <String>[
    '+',
    '−',
    '×',
    '÷',
    '∑',
    '∫',
    'π',
  ];

  @override
  State<FloatingMathSymbols> createState() => _FloatingMathSymbolsState();
}

class _FloatingMathSymbolsState extends State<FloatingMathSymbols>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );

  // (x, y) as fractions of the screen, and font size, for each symbol.
  static const List<(double, double, double)> _layout =
      <(double, double, double)>[
        (0.12, 0.14, 44),
        (0.80, 0.22, 36),
        (0.20, 0.70, 40),
        (0.72, 0.78, 48),
        (0.48, 0.10, 34),
        (0.88, 0.52, 42),
        (0.08, 0.44, 38),
      ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceEffects) {
      _controller.stop();
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
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints box) =>
              AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, _) => Stack(
                  children: <Widget>[
                    for (int i = 0; i < FloatingMathSymbols.symbols.length; i++)
                      Positioned(
                        left: box.maxWidth * _layout[i].$1,
                        top:
                            box.maxHeight * _layout[i].$2 +
                            math.sin(
                                  (_controller.value + i / 7) * 2 * math.pi,
                                ) *
                                10,
                        child: Text(
                          FloatingMathSymbols.symbols[i],
                          style: TextStyle(
                            fontSize: _layout[i].$3,
                            fontWeight: FontWeight.w300,
                            color: (i.isEven ? p.accent : p.secondary)
                                .withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
        ),
      ),
    );
  }
}
