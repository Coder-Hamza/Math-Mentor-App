import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../core/constants.dart';
import '../models/formula.dart';
import '../models/tutor_response.dart';
import '../core/theme.dart';

/// One AI answer: verification badge, warning, explanation, numbered steps, formulas.
class TutorResponseCard extends StatelessWidget {
  const TutorResponseCard({super.key, required this.response});

  final TutorResponse response;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final MarkdownStyleSheet markdown = MarkdownStyleSheet.fromTheme(
      Theme.of(context),
    ).copyWith(p: text.bodyMedium);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 6, 40, 6),
      child: Padding(
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
            MarkdownBody(data: response.explanation, styleSheet: markdown),
            if (response.steps.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              Text('Steps', style: text.titleSmall.weight(FontWeight.w600)),
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
                      label: Text(prettifyMath(formula)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
          ],
        ),
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
          CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.primary,
            child: Text(
              '$number',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
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

/// Green check when SymPy verified the maths; otherwise a neutral or red label.
class VerificationBadge extends StatelessWidget {
  const VerificationBadge({super.key, required this.response});

  final TutorResponse response;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      Color color,
      String label,
    ) = switch (response.verificationStatus) {
      VerificationStatus.verified when response.sympyVerified => (
        Icons.verified_rounded,
        AppColors.verified,
        'SymPy verified',
      ),
      VerificationStatus.failed => (
        Icons.report_problem_rounded,
        AppColors.failed,
        'Possible mistake found',
      ),
      _ => (Icons.help_outline_rounded, AppColors.unverified, 'Not verified'),
    };
    return Row(
      key: ValueKey<String>('badge-${response.verificationStatus.name}'),
      children: <Widget>[
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              .weight(FontWeight.w600, color: color),
        ),
      ],
    );
  }
}

/// Yellow notice used when the maths could not be (fully) verified.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.warningBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.warning_amber_rounded, color: AppColors.secondary),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
