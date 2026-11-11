/// Response of POST /practice/submit.
class PracticeResult {
  const PracticeResult({
    required this.isCorrect,
    required this.correctAnswer,
    required this.explanation,
    required this.pointsEarned,
    required this.newTotalPoints,
    required this.streak,
    required this.encouragement,
    this.alreadySolved = false,
  });

  factory PracticeResult.fromJson(Map<String, dynamic> json) => PracticeResult(
    isCorrect: json['is_correct'] as bool,
    correctAnswer: json['correct_answer'] as String,
    explanation: json['explanation'] as String,
    pointsEarned: json['points_earned'] as int,
    newTotalPoints: json['new_total_points'] as int,
    streak: json['streak'] as int,
    encouragement: json['encouragement'] as String,
    alreadySolved: json['already_solved'] as bool? ?? false,
  );

  final bool isCorrect;
  final String correctAnswer;
  final String explanation;
  final int pointsEarned;
  final int newTotalPoints;
  final int streak;
  final String encouragement;

  /// Solved before: correct again, but no points this time.
  final bool alreadySolved;
}
