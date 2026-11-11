import 'topic.dart';

/// `question_type` of a practice question.
enum QuestionType {
  mcq,
  short,
  long,
  proof;

  static QuestionType fromApi(String? value) => switch (value) {
    'mcq' => QuestionType.mcq,
    'long' => QuestionType.long,
    'proof' => QuestionType.proof,
    _ => QuestionType.short,
  };
}

/// A practice question as the backend sends it BEFORE answering (no answer key).
class PracticeQuestion {
  const PracticeQuestion({
    required this.id,
    required this.topicId,
    required this.topicTitle,
    required this.unitId,
    required this.unitNumber,
    required this.unitTitle,
    required this.questionText,
    required this.difficulty,
    required this.questionType,
    this.options,
  });

  factory PracticeQuestion.fromJson(Map<String, dynamic> json) =>
      PracticeQuestion(
        id: json['id'] as int,
        topicId: json['topic_id'] as int,
        topicTitle: json['topic_title'] as String,
        unitId: json['unit_id'] as int,
        unitNumber: json['unit_number'] as int,
        unitTitle: json['unit_title'] as String,
        questionText: json['question_text'] as String,
        difficulty: Difficulty.fromApi(json['difficulty'] as String?),
        questionType: QuestionType.fromApi(json['question_type'] as String?),
        options: (json['options'] as List<dynamic>?)?.cast<String>(),
      );

  final int id;
  final int topicId;
  final String topicTitle;
  final int unitId;
  final int unitNumber;
  final String unitTitle;
  final String questionText;
  final Difficulty difficulty;
  final QuestionType questionType;

  /// The four choices of an MCQ; null for other question types.
  final List<String>? options;

  bool get isMcq => questionType == QuestionType.mcq && options != null;
}

/// Option letters shown on MCQ buttons.
const List<String> optionLetters = <String>['A', 'B', 'C', 'D'];
