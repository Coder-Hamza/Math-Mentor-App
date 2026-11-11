/// Response of GET /progress/.
class ProgressSummary {
  const ProgressSummary({
    required this.totalPoints,
    required this.totalAttempted,
    required this.totalCorrect,
    required this.accuracyPercent,
    required this.currentStreak,
    required this.units,
  });

  factory ProgressSummary.fromJson(Map<String, dynamic> json) =>
      ProgressSummary(
        totalPoints: json['total_points'] as int,
        totalAttempted: json['total_attempted'] as int,
        totalCorrect: json['total_correct'] as int,
        accuracyPercent: (json['accuracy_percent'] as num).toDouble(),
        currentStreak: json['current_streak'] as int,
        units: (json['units_progress'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(UnitProgress.fromJson)
            .toList(),
      );

  final int totalPoints;
  final int totalAttempted;
  final int totalCorrect;
  final double accuracyPercent;
  final int currentStreak;
  final List<UnitProgress> units;
}

class UnitProgress {
  const UnitProgress({
    required this.unitId,
    required this.unitNumber,
    required this.unitTitle,
    required this.topicsAttempted,
    required this.topicsTotal,
    required this.avgScore,
    required this.progressPercent,
  });

  factory UnitProgress.fromJson(Map<String, dynamic> json) => UnitProgress(
    unitId: json['unit_id'] as int,
    unitNumber: json['unit_number'] as int,
    unitTitle: json['unit_title'] as String,
    topicsAttempted: json['topics_attempted'] as int,
    topicsTotal: json['topics_total'] as int,
    avgScore: (json['avg_score'] as num).toDouble(),
    progressPercent: (json['progress_percent'] as num).toDouble(),
  );

  final int unitId;
  final int unitNumber;
  final String unitTitle;
  final int topicsAttempted;
  final int topicsTotal;
  final double avgScore;

  /// 0-100.
  final double progressPercent;
}

/// A topic where the student's accuracy is below 60%.
class WeakTopic {
  const WeakTopic({
    required this.topicId,
    required this.topicTitle,
    required this.unitId,
    required this.unitNumber,
    required this.unitTitle,
    required this.attempts,
    required this.correct,
    required this.accuracyPercent,
  });

  factory WeakTopic.fromJson(Map<String, dynamic> json) => WeakTopic(
    topicId: json['topic_id'] as int,
    topicTitle: json['topic_title'] as String,
    unitId: json['unit_id'] as int,
    unitNumber: json['unit_number'] as int,
    unitTitle: json['unit_title'] as String,
    attempts: json['attempts'] as int,
    correct: json['correct'] as int,
    accuracyPercent: (json['accuracy_percent'] as num).toDouble(),
  );

  final int topicId;
  final String topicTitle;
  final int unitId;
  final int unitNumber;
  final String unitTitle;
  final int attempts;
  final int correct;
  final double accuracyPercent;
}
