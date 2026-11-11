/// Everything that can go wrong talking to the backend, as the UI needs to see it.
enum ApiErrorType {
  noInternet,
  serverDown,
  timeout,
  unauthorized, // session expired (authenticated request got 401 and refresh failed)
  invalidCredentials, // 401 on login
  emailTaken, // 409 on register
  aiUnavailable, // 503 / 502 from the tutor
  aiBusy, // 429 — free-tier quota
  notFound,
  validation,
  server,
  unknown,
}

class ApiException implements Exception {
  const ApiException(
    this.type, {
    this.statusCode,
    this.code,
    this.serverMessage,
  });

  final ApiErrorType type;
  final int? statusCode;

  /// Backend error code from the envelope, e.g. `ai_quota_exceeded`.
  final String? code;
  final String? serverMessage;

  /// Friendly Urdu/English text for students.
  String get userMessage => switch (type) {
    ApiErrorType.noInternet => 'Internet connection check karein.',
    ApiErrorType.serverDown =>
      'Server se connection nahi hua. Thodi der baad try karein.',
    ApiErrorType.timeout => 'Request timeout, dobara try karein.',
    ApiErrorType.unauthorized => 'Session khatam ho gaya. Dobara login karein.',
    ApiErrorType.invalidCredentials =>
      'Email ya password ghalat hai. (Incorrect email or password)',
    ApiErrorType.emailTaken =>
      'Is email se account pehle se bana hua hai. (Email already registered)',
    ApiErrorType.aiUnavailable =>
      'AI tutor abhi available nahi, thodi der baad try karein.',
    ApiErrorType.aiBusy =>
      'AI tutor abhi bohat busy hai. Ek minute baad dobara try karein.',
    ApiErrorType.notFound => 'Yeh cheez nahi mili. (Not found)',
    ApiErrorType.validation =>
      'Maloomat theek nahi. ${serverMessage ?? 'Please check your input.'}',
    ApiErrorType.server => 'Server mein masla aa gaya. Dobara try karein.',
    ApiErrorType.unknown => 'Kuch ghalat ho gaya. Dobara try karein.',
  };

  /// Whether a "Retry" button makes sense.
  bool get isRetryable => switch (type) {
    ApiErrorType.invalidCredentials ||
    ApiErrorType.emailTaken ||
    ApiErrorType.validation ||
    ApiErrorType.unauthorized ||
    ApiErrorType.notFound => false,
    _ => true,
  };

  @override
  String toString() => 'ApiException($type, status: $statusCode, code: $code)';
}
