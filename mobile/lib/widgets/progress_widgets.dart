import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/progress.dart';
import 'glass_card.dart';
import 'motion.dart';

/// Percentage colour: red below 40%, amber from 40% to 70%, green above 70%.
Color progressColor(double percent, GlassPalette p) {
  if (percent < 40) {
    return p.error;
  }
  if (percent <= 70) {
    return p.secondary;
  }
  return p.success;
}

/// "45.0" -> "45", "66.7" -> "66.7".
String formatPercent(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

/// Totals at the top of the Progress screen: four glass tiles in a 2 x 2 grid.
class StatsCard extends StatelessWidget {
  const StatsCard({super.key, required this.summary});

  final ProgressSummary summary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey<String>('stats-card'),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _Stat(
                valueKey: const ValueKey<String>('stat-points'),
                emoji: '🏆',
                label: 'Points',
                value: '${summary.totalPoints}',
              ),
              _Stat(
                valueKey: const ValueKey<String>('stat-accuracy'),
                emoji: '📊',
                label: 'Accuracy',
                value: '${formatPercent(summary.accuracyPercent)}%',
              ),
            ],
          ),
          Row(
            children: <Widget>[
              _Stat(
                valueKey: const ValueKey<String>('stat-streak'),
                emoji: '🔥',
                label: 'Streak',
                value: '${summary.currentStreak}',
              ),
              _Stat(
                valueKey: const ValueKey<String>('stat-attempted'),
                emoji: '📝',
                label: 'Attempted',
                value: '${summary.totalAttempted}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.valueKey,
    required this.emoji,
    required this.label,
    required this.value,
  });

  final Key valueKey;
  final String emoji;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Expanded(
      child: Appear(
        child: GlassCard(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: <Widget>[
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              GradientText(value, key: valueKey, style: text.headlineSmall),
              Text(label, textAlign: TextAlign.center, style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded bar filled with a red -> amber -> green gradient up to [value]; the
/// colour at the tip therefore matches the percentage.
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({super.key, required this.value, this.height = 8});

  /// 0.0 - 1.0
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    final double v = value.clamp(0, 1).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: p.glass),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double full = box.maxWidth;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: v,
                      child: Container(
                        width: full,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[p.error, p.secondary, p.success],
                            stops: const <double>[0.2, 0.55, 0.9],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One unit: title, gradient progress bar and percentage.
class UnitProgressRow extends StatelessWidget {
  const UnitProgressRow({super.key, required this.progress});

  final UnitProgress progress;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final double percent = progress.progressPercent.clamp(0, 100).toDouble();
    final Color color = progressColor(percent, context.palette);
    return GlassCard(
      blur: false,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
          GradientProgressBar(value: percent / 100),
          const SizedBox(height: 4),
          Text(
            '${progress.topicsAttempted}/${progress.topicsTotal} topics practised',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A topic with accuracy below 60%, on red-tinted glass, with a practice button.
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
    final GlassPalette p = context.palette;
    return Appear(
      child: GlassCard(
        blur: false,
        tint: p.error,
        borderColor: p.error,
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
                    style: text.bodySmall?.copyWith(color: p.error),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TapScale(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  backgroundColor: p.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: onPractice,
                child: const Text('Practice karein'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
