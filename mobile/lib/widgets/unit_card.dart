import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/unit.dart';
import 'glass_card.dart';
import 'motion.dart';

/// One syllabus unit: gradient number badge, title, page chip, arrow.
class UnitCard extends StatelessWidget {
  const UnitCard({super.key, required this.unit, this.onTap});

  final Unit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GlassPalette p = context.palette;
    return Appear(
      child: TapScale(
        enabled: onTap != null,
        child: GlassCard(
          blur: false, // 12 in a list: fill only (see GlassCard docs)
          padding: const EdgeInsets.all(14),
          onTap: onTap,
          child: Row(
            children: <Widget>[
              GradientCircle(
                size: 46,
                child: Text(
                  '${unit.unitNumber}',
                  style: text.titleMedium.weight(
                    FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Unit ${unit.unitNumber}',
                      style: text.labelMedium?.copyWith(color: p.secondary),
                    ),
                    Text(
                      unit.title,
                      style: text.titleMedium.weight(FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    GlassPill(
                      label: 'Page ${unit.pageNumber}',
                      color: p.textSecondary,
                      icon: Icons.menu_book_rounded,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
