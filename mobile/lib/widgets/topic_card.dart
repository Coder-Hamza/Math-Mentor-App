import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/topic.dart';
import '../core/theme.dart';

class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic, this.onTap});

  final Topic topic;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      topic.title,
                      style: text.titleMedium.weight(FontWeight.w600),
                    ),
                    if (topic.description != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        topic.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              DifficultyBadge(difficulty: topic.difficulty),
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour-coded difficulty pill: easy = green, medium = orange, hard = red.
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  static Color colorFor(Difficulty difficulty) => switch (difficulty) {
    Difficulty.easy => AppColors.easy,
    Difficulty.medium => AppColors.medium,
    Difficulty.hard => AppColors.hard,
  };

  @override
  Widget build(BuildContext context) {
    final Color color = colorFor(difficulty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        difficulty.label,
        style: Theme.of(context).textTheme.labelSmall
            .weight(FontWeight.w600, color: color),
      ),
    );
  }
}
