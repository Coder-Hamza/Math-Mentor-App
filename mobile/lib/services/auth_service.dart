import '../models/user.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// Login, registration and session lifecycle on top of [ApiService].
class AuthService {
  AuthService(this._api, this._storage);

  final ApiService _api;
  final StorageService _storage;

  bool get hasToken => _storage.hasToken;

  Future<User> login({required String email, required String password}) async {
    final Object? json = await _api.post('/auth/login', <String, Object?>{
      'email': email.trim(),
      'password': password,
    }, authenticated: false);
    if (json is! Map<String, dynamic>) {
      throw const ApiException(ApiErrorType.unknown);
    }
    await _storage.saveTokens(AuthTokens.fromJson(json));
    return _api.getCurrentUser();
  }

  /// Creates the account, then logs straight in.
  Future<User> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await _api.post('/auth/register', <String, Object?>{
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
    }, authenticated: false);
    return login(email: email, password: password);
  }

  Future<User> currentUser() => _api.getCurrentUser();

  Future<void> logout() => _storage.clearUserData();
}
