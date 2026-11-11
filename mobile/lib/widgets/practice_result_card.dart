import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/practice_result.dart';

/// Shown after a practice answer is graded: right/wrong, the correct answer,
/// the explanation, points and an Urdu/English encouragement.
class PracticeResultCard extends StatelessWidget {
  const PracticeResultCard({super.key, required this.result});

  final PracticeResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool correct = result.isCorrect;
    final Color color = correct ? AppColors.verified : AppColors.failed;

    return Card(
      key: const ValueKey<String>('result-card'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                _PointsPill(points: result.pointsEarned),
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
                style: text.bodySmall?.copyWith(color: AppColors.unverified),
              ),
            ],
            const Divider(height: 24),
            Text('Sahi jawab', style: text.labelLarge),
            const SizedBox(height: 2),
            Text(
              result.correctAnswer,
              key: const ValueKey<String>('correct-answer'),
              style: text.titleMedium.weight(
                FontWeight.w600,
                color: AppColors.verified,
              ),
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

class _PointsPill extends StatelessWidget {
  const _PointsPill({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '+$points points',
        key: const ValueKey<String>('points-earned'),
        style: Theme.of(context).textTheme.labelLarge.weight(FontWeight.w700),
      ),
    );
  }
}
