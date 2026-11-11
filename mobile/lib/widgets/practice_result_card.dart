import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/practice_result.dart';
import 'glass_card.dart';
import 'motion.dart';

/// Shown after a practice answer is graded: right/wrong (green or red glow), the
/// correct answer, the explanation, points and an Urdu/English encouragement.
class PracticeResultCard extends StatelessWidget {
  const PracticeResultCard({super.key, required this.result});

  final PracticeResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GlassPalette p = context.palette;
    final bool correct = result.isCorrect;
    final Color color = correct ? p.success : p.error;

    return Appear(
      child: GlassCard(
        key: const ValueKey<String>('result-card'),
        tint: color,
        borderColor: color,
        glowColor: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  correct ? '✅' : '❌',
                  key: ValueKey<String>(
                    correct ? 'result-correct' : 'result-wrong',
                  ),
                  style: const TextStyle(fontSize: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    correct ? 'Sahi jawab!' : 'Ghalat jawab',
                    style: text.titleLarge.weight(
                      FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                PointsPill(points: result.pointsEarned),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.encouragement,
              style: text.titleSmall.weight(FontWeight.w600),
            ),
            if (result.streak >= 2) ...<Widget>[
              const SizedBox(height: 4),
              Text('🔥 Streak: ${result.streak}', style: text.bodyMedium),
            ],
            if (result.alreadySolved && correct) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Yeh sawaal pehle hi solve ho chuka hai, is dafa points nahi.',
                style: text.bodySmall,
              ),
            ],
            const Divider(height: 24),
            Text('Sahi jawab', style: text.labelLarge),
            const SizedBox(height: 2),
            Text(
              result.correctAnswer,
              key: const ValueKey<String>('correct-answer'),
              style: text.titleMedium.weight(FontWeight.w600, color: p.success),
            ),
            const SizedBox(height: 12),
            Text('Explanation', style: text.labelLarge),
            const SizedBox(height: 2),
            Text(result.explanation, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Amber glass pill: "+20 pts".
class PointsPill extends StatelessWidget {
  const PointsPill({super.key, required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return GlassPill(
      label: '+$points pts',
      color: context.palette.secondary,
      icon: Icons.star_rounded,
      textKey: const ValueKey<String>('points-earned'),
    );
  }
}
