enum VerificationStatus {
  verified,
  failed,
  unverifiable;

  static VerificationStatus fromApi(String? value) => switch (value) {
    'verified' => VerificationStatus.verified,
    'failed' => VerificationStatus.failed,
    _ => VerificationStatus.unverifiable,
  };
}

/// Language the tutor answers in (`language` field of POST /tutor/ask).
enum TutorLanguage {
  urduEnglish('urdu_english', 'Urdu + English'),
  english('english', 'English');

  const TutorLanguage(this.apiValue, this.label);

  final String apiValue;
  final String label;
}

class TutorResponse {
  const TutorResponse({
    required this.question,
    required this.explanation,
    required this.steps,
    required this.formulasUsed,
    required this.sympyVerified,
    required this.verificationConfidence,
    required this.verificationStatus,
    required this.topic,
    required this.unit,
    this.warning,
  });

  factory TutorResponse.fromJson(Map<String, dynamic> json) => TutorResponse(
    question: json['question'] as String,
    explanation: json['explanation'] as String,
    steps: _strings(json['steps']),
    formulasUsed: _strings(json['formulas_used']),
    sympyVerified: json['sympy_verified'] as bool? ?? false,
    verificationConfidence:
        (json['verification_confidence'] as num?)?.toDouble() ?? 0,
    verificationStatus: VerificationStatus.fromApi(
      json['verification_status'] as String?,
    ),
    topic: json['topic'] as String? ?? '',
    unit: json['unit'] as String? ?? '',
    warning: json['warning'] as String?,
  );

  final String question;
  final String explanation;
  final List<String> steps;
  final List<String> formulasUsed;
  final bool sympyVerified;
  final double verificationConfidence;
  final VerificationStatus verificationStatus;
  final String topic;
  final String unit;
  final String? warning;

  static List<String> _strings(Object? value) => value is List
      ? value.map((Object? e) => '$e').toList()
      : const <String>[];
}

/// Removes a leading "Step 3:" style prefix — the UI already numbers steps.
String stripStepPrefix(String step) => step.replaceFirst(
  RegExp(r'^\s*step\s*\d+\s*[:.)\-]\s*', caseSensitive: false),
  '',
);
