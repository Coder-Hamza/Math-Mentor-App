enum Difficulty {
  easy('Easy'),
  medium('Medium'),
  hard('Hard');

  const Difficulty(this.label);

  final String label;

  static Difficulty fromApi(String? value) => switch (value) {
    'easy' => Difficulty.easy,
    'hard' => Difficulty.hard,
    _ => Difficulty.medium,
  };
}

class Topic {
  const Topic({
    required this.id,
    required this.unitId,
    required this.title,
    required this.difficulty,
    this.description,
  });

  factory Topic.fromJson(Map<String, dynamic> json) => Topic(
    id: json['id'] as int,
    unitId: json['unit_id'] as int,
    title: json['title'] as String,
    difficulty: Difficulty.fromApi(json['difficulty_level'] as String?),
    description: json['description'] as String?,
  );

  final int id;
  final int unitId;
  final String title;
  final Difficulty difficulty;
  final String? description;
}
