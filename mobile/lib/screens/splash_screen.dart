import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/routes.dart';
import '../providers/auth_provider.dart';
import '../widgets/loading_widget.dart';
import '../core/theme.dart';

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
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const AppLogo(size: 96, inverted: true),
            const SizedBox(height: 20),
            Text(
              AppStrings.appName,
              style: text.headlineMedium.weight(
                FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              AppStrings.tagline,
              style: text.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            const LoadingWidget(size: 36, padding: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }
}

/// Simple brand mark: a rounded square with a maths symbol.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.inverted = false});

  final double size;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: inverted ? Colors.white : AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        Icons.calculate_rounded,
        size: size * 0.6,
        color: inverted ? AppColors.primary : AppColors.secondary,
      ),
    );
  }
}
