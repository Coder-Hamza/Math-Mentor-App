import 'package:flutter/material.dart';

import '../services/storage_service.dart';

/// Dark (default) / light mode, saved in SharedPreferences under `isDarkMode`.
///
/// The value is read synchronously at start-up (SharedPreferences is already
/// loaded by [StorageService.create]), so the first frame uses the right theme.
/// It survives logout: it is a device preference, not student data.
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._storage) : _isDarkMode = _storage.isDarkMode ?? true;

  final StorageService _storage;
  bool _isDarkMode;

  bool get isDarkMode => _isDarkMode;
  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> toggleTheme() => setDarkMode(!_isDarkMode);

  Future<void> setDarkMode(bool value) async {
    if (value == _isDarkMode) {
      return;
    }
    _isDarkMode = value;
    notifyListeners();
    await _storage.saveDarkMode(value);
  }
}
