import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/formula.dart';
import '../core/theme.dart';

/// Expandable formula: name when collapsed; expression + description when open.
class FormulaCard extends StatelessWidget {
  const FormulaCard({super.key, required this.formula});

  final Formula formula;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.functions_rounded, color: AppColors.primary),
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
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              formula.displayExpression,
              style: text.bodyLarge.weight(FontWeight.w500),
            ),
          ),
          if (formula.description != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(formula.description!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }
}
