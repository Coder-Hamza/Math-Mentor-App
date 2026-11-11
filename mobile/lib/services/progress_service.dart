import '../models/progress.dart';
import 'api_service.dart';

/// Progress endpoints: totals, per-unit progress and weak topics.
///
/// The last successful answers are kept in memory so the Progress screen can show
/// them instantly while it refreshes in the background. [clearCache] runs on logout.
class ProgressService {
  ProgressService(this._api);

  final ApiService _api;

  ProgressSummary? _cachedSummary;
  List<WeakTopic>? _cachedWeakTopics;

  ProgressSummary? get cachedSummary => _cachedSummary;
  List<WeakTopic>? get cachedWeakTopics => _cachedWeakTopics;

  Future<ProgressSummary> getProgress() async {
    final Object? json = await _api.get('/progress/');
    if (json is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return _cachedSummary = ProgressSummary.fromJson(json);
  }

  Future<List<WeakTopic>> getWeakTopics() async {
    final Object? json = await _api.get('/progress/weak-topics');
    if (json is! List) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return _cachedWeakTopics = json
        .cast<Map<String, dynamic>>()
        .map(WeakTopic.fromJson)
        .toList();
  }

  /// Forget the cached progress (on logout, so the next student never sees it).
  void clearCache() {
    _cachedSummary = null;
    _cachedWeakTopics = null;
  }
}
