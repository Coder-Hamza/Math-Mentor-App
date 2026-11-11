import '../models/practice_question.dart';
import '../models/practice_result.dart';
import 'api_service.dart';

/// Practice endpoints. Answers are graded on the server (SymPy + text match, no AI).
class PracticeService {
  PracticeService(this._api);

  final ApiService _api;

  static const int defaultCount = 5;

  /// Random questions without answers, optionally from one unit.
  Future<List<PracticeQuestion>> randomQuestions({
    int? unitId,
    int count = defaultCount,
  }) async {
    final String query = Uri(
      queryParameters: <String, String>{
        'count': '$count',
        if (unitId != null) 'unit_id': '$unitId',
      },
    ).query;
    final Object? json = await _api.get('/practice/random?$query');
    if (json is! List) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return json
        .cast<Map<String, dynamic>>()
        .map(PracticeQuestion.fromJson)
        .toList();
  }

  Future<PracticeResult> submit({
    required int questionId,
    required String answer,
    required int timeTakenSeconds,
  }) async {
    final Object? json = await _api.post('/practice/submit', <String, Object?>{
      'question_id': questionId,
      'student_answer': answer,
      'time_taken_seconds': timeTakenSeconds,
    });
    if (json is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return PracticeResult.fromJson(json);
  }
}
