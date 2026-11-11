import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._auth, ApiService api) {
    api.onUnauthorized = _onSessionExpired;
  }

  final AuthService _auth;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _busy = false;
  String? _error;
  bool _sessionExpired = false;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get isBusy => _busy;
  String? get errorMessage => _error;

  /// True once after a 401 forced a logout, so the login screen can explain why.
  bool get sessionExpired => _sessionExpired;

  /// Splash: decide where to go. A stored token is checked with /auth/me.
  Future<void> bootstrap() async {
    if (!_auth.hasToken) {
      _set(AuthStatus.unauthenticated);
      return;
    }
    try {
      _user = await _auth.currentUser();
      _set(AuthStatus.authenticated);
    } on ApiException catch (e) {
      // Offline or server down: keep the session; screens show retry buttons.
      _set(
        e.type == ApiErrorType.unauthorized
            ? AuthStatus.unauthenticated
            : AuthStatus.authenticated,
      );
    }
  }

  Future<bool> login(String email, String password) =>
      _run(() => _auth.login(email: email, password: password));

  Future<bool> register(String name, String email, String password) =>
      _run(() => _auth.register(name: name, email: email, password: password));

  Future<void> logout() async {
    await _auth.logout();
    _user = null;
    _set(AuthStatus.unauthenticated);
  }

  void clearError() {
    if (_error != null || _sessionExpired) {
      _error = null;
      _sessionExpired = false;
      notifyListeners();
    }
  }

  Future<bool> _run(Future<User> Function() action) async {
    _busy = true;
    _error = null;
    _sessionExpired = false;
    notifyListeners();
    try {
      _user = await action();
      _status = AuthStatus.authenticated;
      return true;
    } on ApiException catch (e) {
      _error = e.userMessage;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _onSessionExpired() {
    _user = null;
    _sessionExpired = true;
    _set(AuthStatus.unauthenticated);
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}
