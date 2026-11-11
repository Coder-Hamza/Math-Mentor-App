import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/formula.dart';
import '../models/topic.dart';
import '../models/tutor_response.dart';
import '../models/unit.dart';
import '../models/user.dart';
import 'api_exception.dart';
import 'storage_service.dart';

export 'api_exception.dart';

/// HTTP client for the MathMentor backend.
///
/// * Adds `Authorization: Bearer <token>` to authenticated requests.
/// * On 401 it refreshes the access token once (using the stored refresh token) and
///   retries; if that fails it clears the tokens and calls [onUnauthorized].
/// * Every failure becomes an [ApiException] with a student-friendly message.
class ApiService {
  ApiService({
    required this._storage,
    http.Client? client,
    String baseUrl = ApiConfig.baseUrl,
  }) : _client = client ?? http.Client(),
       _base = '$baseUrl${ApiConfig.apiPrefix}';

  final StorageService _storage;
  final http.Client _client;
  final String _base;

  /// Called when the session can no longer be recovered (set by AuthProvider).
  void Function()? onUnauthorized;

  Future<bool>? _refreshInFlight;

  // ------------------------------------------------------------------ typed endpoints

  Future<List<Unit>> getUnits() async =>
      _list(await get('/units/'), Unit.fromJson);

  Future<List<Topic>> getUnitTopics(int unitId) async =>
      _list(await get('/units/$unitId/topics'), Topic.fromJson);

  Future<List<Formula>> getTopicFormulas(int topicId) async =>
      _list(await get('/topics/$topicId/formulas'), Formula.fromJson);

  Future<User> getCurrentUser() async =>
      User.fromJson(_map(await get('/auth/me')));

  Future<TutorResponse> askTutor({
    required int topicId,
    required String question,
    TutorLanguage language = TutorLanguage.urduEnglish,
  }) async {
    final Object? json = await post('/tutor/ask', <String, Object?>{
      'question': question,
      'topic_id': topicId,
      'language': language.apiValue,
    }, timeout: ApiConfig.tutorTimeout);
    return TutorResponse.fromJson(_map(json));
  }

  // ------------------------------------------------------------------ generic requests

  Future<Object?> get(
    String path, {
    bool authenticated = true,
    Duration? timeout,
  }) => _send('GET', path, authenticated: authenticated, timeout: timeout);

  Future<Object?> post(
    String path,
    Map<String, Object?> body, {
    bool authenticated = true,
    Duration? timeout,
  }) => _send(
    'POST',
    path,
    body: body,
    authenticated: authenticated,
    timeout: timeout,
  );

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
    required bool authenticated,
    Duration? timeout,
    bool isRetry = false,
  }) async {
    final http.Response response = await _perform(
      method,
      path,
      body: body,
      authenticated: authenticated,
      timeout: timeout ?? ApiConfig.requestTimeout,
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }
    if (response.statusCode == 401 && authenticated) {
      if (!isRetry && await _refreshTokens()) {
        return _send(
          method,
          path,
          body: body,
          authenticated: authenticated,
          timeout: timeout,
          isRetry: true,
        );
      }
      await _storage.clearTokens();
      onUnauthorized?.call();
      throw const ApiException(ApiErrorType.unauthorized, statusCode: 401);
    }
    throw _errorFor(response);
  }

  Future<http.Response> _perform(
    String method,
    String path, {
    Map<String, Object?>? body,
    required bool authenticated,
    required Duration timeout,
  }) async {
    final http.Request request = http.Request(method, Uri.parse('$_base$path'))
      ..headers['Accept'] = 'application/json';
    final String? token = _storage.accessToken;
    if (authenticated && token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    try {
      final http.StreamedResponse streamed = await _client
          .send(request)
          .timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorType.timeout);
    } on SocketException catch (e) {
      throw ApiException(_classifyNetworkError(e.message, e.osError?.message));
    } on http.ClientException catch (e) {
      throw ApiException(_classifyNetworkError(e.message));
    }
  }

  /// Exchange the stored refresh token for a new pair. Concurrent callers share one call.
  Future<bool> _refreshTokens() {
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefresh() async {
    final String? refreshToken = _storage.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    try {
      final Object? json = await post('/auth/refresh', <String, Object?>{
        'refresh_token': refreshToken,
      }, authenticated: false);
      await _storage.saveTokens(AuthTokens.fromJson(_map(json)));
      return true;
    } on ApiException {
      return false;
    }
  }

  // ------------------------------------------------------------------ helpers

  static ApiErrorType _classifyNetworkError(
    String message, [
    String? osMessage,
  ]) {
    final String text = '$message ${osMessage ?? ''}'.toLowerCase();
    // Phone is online but nothing answers on the server's port.
    if (text.contains('refused') || text.contains('reset by peer')) {
      return ApiErrorType.serverDown;
    }
    // No network / no route / DNS failure.
    return ApiErrorType.noInternet;
  }

  static ApiException _errorFor(http.Response response) {
    String? code;
    String? message;
    try {
      final Object? json = _decode(response);
      if (json is Map<String, dynamic> &&
          json['error'] is Map<String, dynamic>) {
        final Map<String, dynamic> error =
            json['error'] as Map<String, dynamic>;
        code = error['code'] as String?;
        message = error['message'] as String?;
      }
    } on FormatException {
      // Not our JSON envelope (e.g. a proxy error page) — fall through.
    }
    final int status = response.statusCode;
    final ApiErrorType type = switch (status) {
      401 => ApiErrorType.invalidCredentials,
      404 => ApiErrorType.notFound,
      409 => ApiErrorType.emailTaken,
      422 => ApiErrorType.validation,
      429 => ApiErrorType.aiBusy,
      504 => ApiErrorType.timeout,
      502 ||
      503 when (code ?? '').startsWith('ai_') => ApiErrorType.aiUnavailable,
      502 || 503 => ApiErrorType.serverDown,
      >= 500 => ApiErrorType.server,
      _ => ApiErrorType.unknown,
    };
    return ApiException(
      type,
      statusCode: status,
      code: code,
      serverMessage: message,
    );
  }

  static Object? _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return null;
    }
    // Always UTF-8: AI answers contain Urdu and maths symbols.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static Map<String, dynamic> _map(Object? json) {
    if (json is Map<String, dynamic>) {
      return json;
    }
    throw const ApiException(ApiErrorType.unknown);
  }

  static List<T> _list<T>(
    Object? json,
    T Function(Map<String, dynamic>) parse,
  ) {
    if (json is! List) {
      throw const ApiException(ApiErrorType.unknown);
    }
    return json.cast<Map<String, dynamic>>().map(parse).toList();
  }
}
