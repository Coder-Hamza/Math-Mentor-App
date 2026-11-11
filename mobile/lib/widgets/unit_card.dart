import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/unit.dart';
import '../core/theme.dart';

class UnitCard extends StatelessWidget {
  const UnitCard({super.key, required this.unit, this.onTap});

  final Unit unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.primary,
                child: Text(
                  '${unit.unitNumber}',
                  style: text.titleMedium.weight(
                    FontWeight.w600,
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
                      style: text.labelMedium?.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                    Text(
                      unit.title,
                      style: text.titleMedium.weight(FontWeight.w600),
                    ),
                    Text(
                      'Page ${unit.pageNumber}',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.unverified,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.unverified,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
