import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/topic.dart';
import 'glass_card.dart';
import 'motion.dart';

class TopicCard extends StatelessWidget {
  const TopicCard({super.key, required this.topic, this.onTap});

  final Topic topic;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Appear(
      child: TapScale(
        enabled: onTap != null,
        child: GlassCard(
          blur: false,
          padding: const EdgeInsets.all(14),
          onTap: onTap,
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
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.palette.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass difficulty chip: easy = green, medium = amber, hard = red.
class DifficultyBadge extends StatelessWidget {
  const DifficultyBadge({super.key, required this.difficulty});

  final Difficulty difficulty;

  static Color colorFor(Difficulty difficulty, GlassPalette p) =>
      switch (difficulty) {
        Difficulty.easy => p.success,
        Difficulty.medium => p.secondary,
        Difficulty.hard => p.error,
      };

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      label: difficulty.label,
      color: colorFor(difficulty, context.palette),
    );
  }
}
