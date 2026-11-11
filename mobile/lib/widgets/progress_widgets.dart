import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/progress.dart';

/// Progress bar colour: red below 40%, orange from 40% to 70%, green above 70%.
Color progressColor(double percent) {
  if (percent < 40) {
    return AppColors.hard;
  }
  if (percent <= 70) {
    return AppColors.medium;
  }
  return AppColors.easy;
}

/// "45.0" -> "45", "66.7" -> "66.7".
String formatPercent(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// Totals at the top of the Progress screen.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.summary});

  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('stats-card'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                _Stat(
                  key: const ValueKey<String>('stat-points'),
                  label: 'Total Points',
                  value: '🏆 ${summary.totalPoints}',
                ),
                _Stat(
                  key: const ValueKey<String>('stat-accuracy'),
                  label: 'Accuracy',
                  value: '${formatPercent(summary.accuracyPercent)}%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                _Stat(
                  key: const ValueKey<String>('stat-streak'),
                  label: 'Current Streak',
                  value: '🔥 ${summary.currentStreak}',
                ),
                _Stat(
                  key: const ValueKey<String>('stat-attempted'),
                  label: 'Questions Attempted',
                  value: '${summary.totalAttempted}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: text.headlineSmall.weight(
              FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.unverified),
          ),
        ],
      ),
    );
  }
}

/// One unit: title, colour-coded progress bar and percentage.
class UnitProgressRow extends StatelessWidget {
  const UnitProgressRow({super.key, required this.progress});

  final UnitProgress progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double percent = progress.progressPercent.clamp(0, 100).toDouble();
    final Color color = progressColor(percent);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Unit ${progress.unitNumber}: ${progress.unitTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium.weight(FontWeight.w600),
                ),
              ),
              Text(
                '${formatPercent(percent)}%',
                style: text.bodyMedium.weight(FontWeight.w700, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${progress.topicsAttempted}/${progress.topicsTotal} topics practised',
            style: text.bodySmall?.copyWith(color: AppColors.unverified),
          ),
        ],
      ),
    );
  }
}

/// A topic with accuracy below 60%, highlighted in red, with a practice button.
class WeakTopicCard extends StatelessWidget {
  const WeakTopicCard({
    super.key,
    required this.topic,
    required this.onPractice,
  });

  final WeakTopic topic;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      color: AppColors.errorBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.failed),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    topic.topicTitle,
                    style: text.titleSmall.weight(FontWeight.w600),
                  ),
                  Text(
                    'Unit ${topic.unitNumber} · ${formatPercent(topic.accuracyPercent)}% '
                    '(${topic.correct}/${topic.attempts} sahi)',
                    style: text.bodySmall?.copyWith(color: AppColors.failed),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                backgroundColor: AppColors.failed,
              ),
              onPressed: onPractice,
              child: const Text('Practice karein'),
            ),
          ],
        ),
      ),
    );
  }
}
