import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/formula.dart';
import 'glass_card.dart';
import 'motion.dart';

/// Monospace font for maths (Android: Droid Sans Mono / Roboto Mono).
const TextStyle mathTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: <String>['RobotoMono', 'Courier'],
);

/// Expandable glass formula card: name when collapsed; expression (monospace,
/// accent colour) and description when open.
class FormulaCard extends StatelessWidget {
  const FormulaCard({super.key, required this.formula});

  final Formula formula;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GlassPalette p = context.palette;
    return Appear(
      child: GlassCard(
        blur: false,
        padding: EdgeInsets.zero,
        child: Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            leading: Icon(Icons.functions_rounded, color: p.accent),
            title: Text(
              formula.name,
              style: text.titleSmall.weight(FontWeight.w600),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.accent.withValues(alpha: 0.3)),
                ),
                child: SelectableText(
                  formula.displayExpression,
                  style: mathTextStyle.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.accent,
                  ),
                ),
              ),
              if (formula.description != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(formula.description!, style: text.bodyMedium),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
