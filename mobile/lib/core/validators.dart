import 'constants.dart';

/// Form validators with short Urdu/English messages (mirror the backend rules).
class Validators {
  Validators._();

  static final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

  static String? email(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'Email zaroori hai (Email is required)';
    }
    if (!_email.hasMatch(v)) {
      return 'Sahi email likhein (Enter a valid email)';
    }
    return null;
  }

  /// Login: only "not empty" — the server decides if it is correct.
  static String? requiredPassword(String? value) => (value ?? '').isEmpty
      ? 'Password zaroori hai (Password is required)'
      : null;

  /// Registration: same rule as the backend (8–128 characters).
  static String? newPassword(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) {
      return 'Password zaroori hai (Password is required)';
    }
    if (v.length < ApiConfig.minPasswordLength) {
      return 'Password kam az kam ${ApiConfig.minPasswordLength} characters ka ho '
          '(At least ${ApiConfig.minPasswordLength} characters)';
    }
    if (v.length > 128) {
      return 'Password bohat lamba hai (Max 128 characters)';
    }
    return null;
  }

  static String? name(String? value) {
    final String v = value?.trim() ?? '';
    if (v.isEmpty) {
      return 'Naam zaroori hai (Name is required)';
    }
    if (v.length > 100) {
      return 'Naam bohat lamba hai (Name is too long)';
    }
    return null;
  }
}
