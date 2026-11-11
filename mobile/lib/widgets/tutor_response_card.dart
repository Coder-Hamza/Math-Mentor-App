import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/theme.dart';
import '../models/formula.dart';
import '../models/tutor_response.dart';
import 'formula_card.dart';
import 'glass_card.dart';
import 'motion.dart';

/// One AI answer on glass: gradient header (topic), verification pill, warning,
/// explanation, numbered steps and formula chips.
class TutorResponseCard extends StatelessWidget {
  const TutorResponseCard({super.key, required this.response});

  final TutorResponse response;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextTheme text = theme.textTheme;
    final GlassPalette p = context.palette;
    final MarkdownStyleSheet markdown = MarkdownStyleSheet.fromTheme(theme)
        .copyWith(
          p: text.bodyMedium,
          strong: text.bodyMedium.weight(FontWeight.w700, color: p.accent),
          code: mathTextStyle.copyWith(
            color: p.accent,
            backgroundColor: p.accent.withValues(alpha: 0.08),
          ),
        );

    return Appear(
      child: GlassCard(
        margin: const EdgeInsets.fromLTRB(16, 6, 40, 6),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _GradientHeader(title: response.topic),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  VerificationBadge(response: response),
                  if (response.warning != null) ...<Widget>[
                    const SizedBox(height: 10),
                    WarningBox(message: response.warning!),
                  ],
                  const SizedBox(height: 12),
                  MarkdownBody(
                    data: response.explanation,
                    styleSheet: markdown,
                  ),
                  if (response.steps.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    Text(
                      'Steps',
                      style: text.titleSmall.weight(FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (int i = 0; i < response.steps.length; i++)
                      _NumberedStep(
                        number: i + 1,
                        text: stripStepPrefix(response.steps[i]),
                        styleSheet: markdown,
                      ),
                  ],
                  if (response.formulasUsed.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      'Formulas used',
                      style: text.titleSmall.weight(FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final String formula in response.formulasUsed)
                          Chip(
                            label: Text(
                              prettifyMath(formula),
                              style: mathTextStyle.copyWith(
                                fontSize: 12,
                                color: p.textPrimary,
                              ),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientHeader extends StatelessWidget {
  const _GradientHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('response-header'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(gradient: context.palette.accentGradient),
      child: Row(
        children: <Widget>[
          const Icon(Icons.smart_toy_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  .weight(FontWeight.w600, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.number,
    required this.text,
    required this.styleSheet,
  });

  final int number;
  final String text;
  final MarkdownStyleSheet styleSheet;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GradientCircle(
            size: 24,
            child: Text('$number', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MarkdownBody(data: text, styleSheet: styleSheet),
          ),
        ],
      ),
    );
  }
}

/// Glass pill: green "SymPy verified", red "Possible mistake found", or grey
/// "Not verified".
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.response});

  final TutorResponse response;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final (
      IconData icon,
      Color color,
      String label,
    ) = switch (response.verificationStatus) {
      VerificationStatus.verified when response.sympyVerified => (
        Icons.check_circle_rounded,
        p.success,
        'SymPy verified',
      ),
      VerificationStatus.failed => (
        Icons.report_problem_rounded,
        p.error,
        'Possible mistake found',
      ),
      _ => (Icons.help_outline_rounded, p.textSecondary, 'Not verified'),
    };
    return GlassPill(
      key: ValueKey<String>('badge-${response.verificationStatus.name}'),
      icon: icon,
      color: color,
      label: label,
    );
  }
}

/// Amber glass notice used when the maths could not be (fully) verified.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.message});

  final String message;

  static Color backgroundFor(GlassPalette p) =>
      p.secondary.withValues(alpha: 0.14);

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundFor(p),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.secondary.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: p.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
