import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/api_exception.dart';
import 'glass_card.dart';

/// Friendly error with an icon and (when it makes sense) a retry button.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final ApiException error;
  final VoidCallback? onRetry;
  final bool compact;

  IconData get _icon => switch (error.type) {
    ApiErrorType.noInternet => Icons.wifi_off_rounded,
    ApiErrorType.serverDown => Icons.cloud_off_rounded,
    ApiErrorType.timeout => Icons.hourglass_bottom_rounded,
    ApiErrorType.aiUnavailable ||
    ApiErrorType.aiBusy => Icons.smart_toy_outlined,
    _ => Icons.error_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final Widget retry = onRetry != null && error.isRetryable
        ? Padding(
            padding: EdgeInsets.only(top: compact ? 8 : 16),
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text(AppStrings.retry),
            ),
          )
        : const SizedBox.shrink();

    if (compact) {
      return GlassCard(
        key: const ValueKey<String>('error-compact'),
        blur: false,
        tint: p.error,
        borderColor: p.error.withValues(alpha: 0.6),
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_icon, color: p.error),
                const SizedBox(width: 8),
                Expanded(child: Text(error.userMessage)),
              ],
            ),
            retry,
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_icon, size: 56, color: p.textSecondary),
            const SizedBox(height: 12),
            Text(
              error.userMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            retry,
          ],
        ),
      ),
    );
  }
}
