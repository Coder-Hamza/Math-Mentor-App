import 'package:flutter/material.dart';

/// Where the FastAPI backend lives. Chosen at build time, no code change needed:
///
/// * Android emulator (default): `flutter run` -> `http://10.0.2.2:8000`
///   (10.0.2.2 is the host PC as seen from the emulator).
/// * Phone over USB: `adb reverse tcp:8000 tcp:8000`, then
///   `flutter run --dart-define=API_TARGET=usb` -> `http://127.0.0.1:8000`.
/// * Anything else (phone on Wi-Fi, a deployed server):
///   `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`
///   (start the backend with `--host 0.0.0.0` so the phone can reach it).
///   API_BASE_URL wins over API_TARGET.
class ApiConfig {
  ApiConfig._();

  static const String emulatorBaseUrl = 'http://10.0.2.2:8000';
  static const String usbBaseUrl = 'http://127.0.0.1:8000';

  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');
  static const String _target = String.fromEnvironment(
    'API_TARGET',
    defaultValue: 'emulator',
  );
  static const String baseUrl = _baseUrlOverride != ''
      ? _baseUrlOverride
      : _target == 'usb'
      ? usbBaseUrl
      : emulatorBaseUrl;

  /// Same rule as [baseUrl], callable with any values (used by tests).
  static String resolveBaseUrl({String override = '', String target = ''}) {
    if (override.isNotEmpty) {
      return override;
    }
    return target == 'usb' ? usbBaseUrl : emulatorBaseUrl;
  }

  static const String apiPrefix = '/api/v1';

  /// Normal requests give up (and show "Dobara try karein") after 30 s.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// The backend caps the tutor at 30 s; allow a little extra for the network.
  static const Duration tutorTimeout = Duration(seconds: 40);

  static const int maxQuestionLength = 500;
  static const int minPasswordLength = 8;
}

class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1565C0); // deep blue
  static const Color secondary = Color(0xFFFFA000); // amber
  static const Color background = Color(0xFFF5F5F5); // light grey

  static const Color easy = Color(0xFF2E7D32); // green
  static const Color medium = Color(0xFFEF6C00); // orange
  static const Color hard = Color(0xFFC62828); // red

  static const Color verified = Color(0xFF2E7D32);
  static const Color failed = Color(0xFFC62828);
  static const Color unverified = Color(0xFF757575);
  static const Color warningBackground = Color(0xFFFFF8E1);
  static const Color warningBorder = Color(0xFFFFC107);
  static const Color errorBackground = Color(0xFFFFEBEE);
}

class AppStrings {
  AppStrings._();

  static const String appName = 'MathMentor AI';
  static const String tagline = 'Sindh Board HSC-I Mathematics';
  static const String askHint = 'Apna sawal likhein...';
  static const String retry = 'Dobara try karein';
  static const String noProgress =
      'Abhi koi sawaal hall nahi kiya, practice shuru karein! 📚';
  static const String noWeakTopics =
      'Bohat acha! Koi kamzor topic nahi hai! 🌟';
}
