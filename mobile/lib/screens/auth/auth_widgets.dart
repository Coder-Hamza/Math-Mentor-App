import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../splash_screen.dart';
import '../../core/theme.dart';

/// "MathMentor AI" header shared by the login and register screens.
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        const AppLogo(),
        const SizedBox(height: 12),
        Text(
          AppStrings.appName,
          style: text.headlineSmall.weight(
            FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        Text(subtitle, textAlign: TextAlign.center, style: text.bodyMedium),
        const SizedBox(height: 28),
      ],
    );
  }
}

/// Red box for server-side errors (wrong password, email taken, offline...).
class FormErrorBox extends StatelessWidget {
  const FormErrorBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('form-error'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, color: AppColors.failed),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

/// Primary button that shows a spinner and disables itself while [busy].
class SubmitButton extends StatelessWidget {
  const SubmitButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(label),
    );
  }
}
