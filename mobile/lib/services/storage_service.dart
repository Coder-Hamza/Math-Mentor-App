import 'package:shared_preferences/shared_preferences.dart';

import '../models/user.dart';

/// Thin wrapper over SharedPreferences: JWTs, per-topic recent questions and the
/// theme preference.
class StorageService {
  StorageService(this._prefs);

  static Future<StorageService> create() async =>
      StorageService(await SharedPreferences.getInstance());

  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _recentPrefix = 'recent_questions_';
  static const String _darkModeKey = 'isDarkMode';
  static const int maxRecentQuestions = 5;

  final SharedPreferences _prefs;

  String? get accessToken => _prefs.getString(_accessKey);
  String? get refreshToken => _prefs.getString(_refreshKey);
  bool get hasToken => (accessToken ?? '').isNotEmpty;

  Future<void> saveTokens(AuthTokens tokens) async {
    await _prefs.setString(_accessKey, tokens.accessToken);
    await _prefs.setString(_refreshKey, tokens.refreshToken);
  }

  Future<void> clearTokens() async {
    await _prefs.remove(_accessKey);
    await _prefs.remove(_refreshKey);
  }

  /// Theme preference (`isDarkMode`); null until the student first toggles it.
  /// Not removed by [clearUserData]: it's a device setting, not student data.
  bool? get isDarkMode => _prefs.getBool(_darkModeKey);

  Future<void> saveDarkMode(bool value) => _prefs.setBool(_darkModeKey, value);

  /// Most recent first, without duplicates.
  List<String> recentQuestions(int topicId) =>
      _prefs.getStringList('$_recentPrefix$topicId') ?? const <String>[];

  Future<void> addRecentQuestion(int topicId, String question) async {
    final String trimmed = question.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final List<String> updated = <String>[
      trimmed,
      ...recentQuestions(topicId).where((String q) => q != trimmed),
    ].take(maxRecentQuestions).toList();
    await _prefs.setStringList('$_recentPrefix$topicId', updated);
  }

  /// On logout: remove tokens and question history (phones are often shared).
  Future<void> clearUserData() async {
    await clearTokens();
    final Iterable<String> recentKeys = _prefs.getKeys().where(
      (String key) => key.startsWith(_recentPrefix),
    );
    for (final String key in recentKeys.toList()) {
      await _prefs.remove(key);
    }
  }
}
