import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'core/constants.dart';
import 'core/routes.dart';
import 'core/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/units_provider.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/practice_service.dart';
import 'services/progress_service.dart';
import 'services/storage_service.dart';

/// Closes the on-screen keyboard when the student taps anywhere outside a text
/// field. Buttons and fields still win their own taps (deepest recogniser wins).
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: child,
    );
  }
}

/// App root: builds services/providers and sends the user to Login whenever the
/// session ends (logout or an unrecoverable 401).
class MathMentorApp extends StatefulWidget {
  const MathMentorApp({
    super.key,
    required this.storage,
    this.httpClient,
    this.baseUrl = ApiConfig.baseUrl,
    @visibleForTesting this.home,
  });

  final StorageService storage;

  /// Tests only: start on this screen instead of the splash route.
  final Widget? home;

  /// Injected in tests (MockClient); a real client otherwise.
  final http.Client? httpClient;
  final String baseUrl;

  @override
  State<MathMentorApp> createState() => _MathMentorAppState();
}

class _MathMentorAppState extends State<MathMentorApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final ApiService _api = ApiService(
    storage: widget.storage,
    client: widget.httpClient,
    baseUrl: widget.baseUrl,
  );
  late final AuthProvider _auth = AuthProvider(
    AuthService(_api, widget.storage),
    _api,
  );
  late final UnitsProvider _units = UnitsProvider(_api);
  late final ThemeProvider _theme = ThemeProvider(widget.storage);
  final ThemeData _lightTheme = buildLightTheme();
  final ThemeData _darkTheme = buildDarkTheme();
  late final PracticeService _practice = PracticeService(_api);
  late final ProgressService _progress = ProgressService(_api);
  AuthStatus _lastStatus = AuthStatus.unknown;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    final AuthStatus status = _auth.status;
    if (_lastStatus == AuthStatus.authenticated &&
        status == AuthStatus.unauthenticated) {
      _units.clear();
      _progress.clearCache();
      _navigatorKey.currentState?.pushNamedAndRemoveUntil(
        Routes.login,
        (_) => false,
      );
    }
    _lastStatus = status;
  }

  @override
  void dispose() {
    _auth
      ..removeListener(_onAuthChanged)
      ..dispose();
    _units.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<StorageService>.value(value: widget.storage),
        Provider<ApiService>.value(value: _api),
        Provider<PracticeService>.value(value: _practice),
        Provider<ProgressService>.value(value: _progress),
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider<UnitsProvider>.value(value: _units),
        ChangeNotifierProvider<ThemeProvider>.value(value: _theme),
      ],
      child: ListenableBuilder(
        listenable: _theme,
        builder: (BuildContext context, _) => MaterialApp(
          title: AppStrings.appName,
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          themeMode: _theme.themeMode,
          themeAnimationDuration: themeSwitchDuration,
          themeAnimationCurve: Curves.easeInOut,
          home: widget.home,
          initialRoute: widget.home == null ? Routes.splash : null,
          onGenerateRoute: onGenerateRoute,
          builder: (BuildContext context, Widget? child) =>
              DismissKeyboard(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
