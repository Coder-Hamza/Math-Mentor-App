class Formula {
  const Formula({
    required this.id,
    required this.topicId,
    required this.name,
    required this.expression,
    this.description,
  });

  factory Formula.fromJson(Map<String, dynamic> json) => Formula(
    id: json['id'] as int,
    topicId: json['topic_id'] as int,
    name: json['name'] as String,
    expression: json['expression'] as String,
    description: json['description'] as String?,
  );

  final int id;
  final int topicId;
  final String name;

  /// SymPy syntax from the backend, e.g. `sin(x + y) = sin(x)*cos(y) + cos(x)*sin(y)`.
  final String expression;
  final String? description;

  /// Student-friendly version of [expression].
  String get displayExpression => prettifyMath(expression);
}

/// Turns SymPy-style text into something closer to textbook notation.
String prettifyMath(String text) {
  return text
      .replaceAll('**', '^')
      .replaceAll('*', '·')
      .replaceAllMapped(RegExp(r'\bsqrt\b'), (_) => '√')
      .replaceAllMapped(RegExp(r'\bpi\b'), (_) => 'π')
      .replaceAllMapped(RegExp(r'\btheta\b'), (_) => 'θ')
      .replaceAllMapped(RegExp(r'\bI\b'), (_) => 'i');
}
