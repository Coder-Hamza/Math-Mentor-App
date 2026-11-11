class Unit {
  const Unit({
    required this.id,
    required this.unitNumber,
    required this.title,
    required this.pageNumber,
    this.description,
  });

  factory Unit.fromJson(Map<String, dynamic> json) => Unit(
    id: json['id'] as int,
    unitNumber: json['unit_number'] as int,
    title: json['title'] as String,
    pageNumber: json['page_number'] as int,
    description: json['description'] as String?,
  );

  final int id;
  final int unitNumber;
  final String title;
  final int pageNumber;
  final String? description;
}
