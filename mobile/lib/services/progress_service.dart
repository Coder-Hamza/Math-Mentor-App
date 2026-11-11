import '../models/progress.dart';
import 'api_service.dart';

/// Progress endpoints: totals, per-unit progress and weak topics.
class ProgressService {
  ProgressService(this._api);

  final ApiService _api;

  Future<ProgressSummary> getProgress() async {
    final Object? json = await _api.get('/progress/');
    if (json is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return ProgressSummary.fromJson(json);
  }

  Future<List<WeakTopic>> getWeakTopics() async {
    final Object? json = await _api.get('/progress/weak-topics');
    if (json is! List) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return json.cast<Map<String, dynamic>>().map(WeakTopic.fromJson).toList();
  }
}
