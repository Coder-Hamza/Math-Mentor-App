import 'topic.dart';

/// One step of a textbook-pattern solution (Qadam).
class SolverStep {
  const SolverStep({
    required this.stepNumber,
    required this.title,
    required this.explanation,
    this.formulaUsed,
    this.calculation,
  });

  factory SolverStep.fromJson(Map<String, dynamic> json) => SolverStep(
    stepNumber: json['step_number'] as int,
    title: json['title'] as String,
    explanation: json['explanation'] as String,
    formulaUsed: _nonEmpty(json['formula_used']),
    calculation: _nonEmpty(json['calculation']),
  );

  final int stepNumber;
  final String title;
  final String explanation;
  final String? formulaUsed;
  final String? calculation;
}

/// Response of POST /solver/solve.
class SolverResult {
  const SolverResult({
    required this.question,
    required this.chapter,
    required this.solution,
    required this.steps,
    required this.methodUsed,
    required this.formulasApplied,
    required this.keyConcepts,
    required this.answerVerified,
    required this.ourAnswer,
    required this.sympyVerified,
    required this.difficulty,
    required this.proTip,
    this.bookAnswer,
    this.warning,
  });

  factory SolverResult.fromJson(Map<String, dynamic> json) => SolverResult(
    question: json['question'] as String,
    chapter: json['chapter'] as String,
    solution: json['solution'] as String,
    steps: (json['steps'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(SolverStep.fromJson)
        .toList(),
    methodUsed: json['method_used'] as String,
    formulasApplied: (json['formulas_applied'] as List<dynamic>).cast<String>(),
    keyConcepts: (json['key_concepts'] as List<dynamic>).cast<String>(),
    answerVerified: json['answer_verified'] as bool,
    bookAnswer: _nonEmpty(json['book_answer']),
    ourAnswer: json['our_answer'] as String,
    sympyVerified: json['sympy_verified'] as bool,
    difficulty: Difficulty.fromApi(json['difficulty_level'] as String?),
    proTip: json['pro_tip'] as String,
    warning: _nonEmpty(json['warning']),
  );

  final String question;
  final String chapter;

  /// The whole solution as text in the textbook pattern (Sawal ... Exam Tip).
  final String solution;
  final List<SolverStep> steps;
  final String methodUsed;
  final List<String> formulasApplied;
  final List<String> keyConcepts;

  /// True only when a book answer was given and our answer matches it.
  final bool answerVerified;
  final String? bookAnswer;
  final String ourAnswer;
  final bool sympyVerified;
  final Difficulty difficulty;
  final String proTip;
  final String? warning;

  /// Gemini did not return the structured format: only [solution] text is available.
  bool get isStructured => steps.isNotEmpty;
}

String? _nonEmpty(Object? value) {
  final String? text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}
