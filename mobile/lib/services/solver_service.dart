import '../core/constants.dart';
import '../models/solver_result.dart';
import '../models/tutor_response.dart';
import 'api_service.dart';

/// Smart Question Solver: chapter + question (+ the book's answer) -> full solution.
class SolverService {
  SolverService(this._api);

  final ApiService _api;

  Future<SolverResult> solve({
    required String chapter,
    required String question,
    String? bookAnswer,
    TutorLanguage language = TutorLanguage.urduEnglish,
  }) async {
    final String book = (bookAnswer ?? '').trim();
    final Object? json = await _api.post('/solver/solve', <String, Object?>{
      'chapter_name': chapter.trim(),
      'question': question.trim(),
      'book_answer': book.isEmpty ? null : book,
      'language': language.apiValue,
    }, timeout: ApiConfig.solverTimeout);
    if (json is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return SolverResult.fromJson(json);
  }
}
