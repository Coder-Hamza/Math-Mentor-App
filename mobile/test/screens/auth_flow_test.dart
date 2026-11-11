import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/screens/auth/login_screen.dart';
import 'package:mathmentor/screens/auth/register_screen.dart';
import 'package:mathmentor/screens/home/home_screen.dart';
import 'package:mathmentor/services/storage_service.dart';

import '../helpers.dart';

final Finder loginEmail = find.byKey(const ValueKey<String>('login-email'));
final Finder loginPassword = find.byKey(
  const ValueKey<String>('login-password'),
);
final Finder loginButton = find.byKey(const ValueKey<String>('login-button'));

Map<String, Object?> tokensJson(String access) => <String, Object?>{
  'access_token': access,
  'refresh_token': 'refresh-$access',
  'token_type': 'bearer',
  'expires_in': 3600,
};

void main() {
  group('Splash', () {
    testWidgets('no stored token -> login screen', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend();
      await pumpApp(tester, backend);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('valid stored token -> home', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await pumpApp(tester, backend, prefs: loggedIn);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Assalam-o-Alaikum, Sana!'), findsOneWidget);
    });

    testWidgets('expired session that cannot refresh -> login', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..onError('GET', '/auth/me', 401, 'not_authenticated')
        ..onError('POST', '/auth/refresh', 401, 'not_authenticated');
      final StorageService storage = await pumpApp(
        tester,
        backend,
        prefs: loggedIn,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.hasToken, isFalse);
    });

    testWidgets('offline with a token -> home with a retry option', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..handle(
          'GET',
          '/auth/me',
          (_) async => throw http.ClientException('Failed host lookup'),
        )
        ..handle(
          'GET',
          '/units/',
          (_) async => throw http.ClientException('Failed host lookup'),
        );
      await pumpApp(tester, backend, prefs: loggedIn);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Internet connection check karein.'), findsOneWidget);
      expect(find.text('Dobara try karein'), findsOneWidget);
    });
  });

  group('Login screen', () {
    testWidgets('shows branding and both fields', (WidgetTester tester) async {
      await pumpApp(tester, FakeBackend());
      expect(find.text('MathMentor AI'), findsOneWidget);
      expect(loginEmail, findsOneWidget);
      expect(loginPassword, findsOneWidget);
      expect(find.text('Account nahi hai? Register karein'), findsOneWidget);
    });

    testWidgets('empty form shows validation errors and sends nothing', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend();
      await pumpApp(tester, backend);
      await tester.tap(loginButton);
      await tester.pump();
      expect(
        find.text('Email zaroori hai (Email is required)'),
        findsOneWidget,
      );
      expect(
        find.text('Password zaroori hai (Password is required)'),
        findsOneWidget,
      );
      expect(backend.requests, isEmpty);
    });

    testWidgets('invalid email is rejected', (WidgetTester tester) async {
      await pumpApp(tester, FakeBackend());
      await tester.enterText(loginEmail, 'not-an-email');
      await tester.enterText(loginPassword, 'secret123');
      await tester.tap(loginButton);
      await tester.pump();
      expect(
        find.text('Sahi email likhein (Enter a valid email)'),
        findsOneWidget,
      );
    });

    testWidgets('button disables and spins while logging in, then goes home', (
      WidgetTester tester,
    ) async {
      final Completer<http.Response> pending = Completer<http.Response>();
      final FakeBackend backend = FakeBackend()
        ..withSyllabus()
        ..handle('POST', '/auth/login', (_) => pending.future);
      final StorageService storage = await pumpApp(tester, backend);

      await tester.enterText(loginEmail, 'sana@example.com');
      await tester.enterText(loginPassword, 'secret123');
      await tester.tap(loginButton);
      await tester.pump();

      final FilledButton button = tester.widget<FilledButton>(
        find.descendant(of: loginButton, matching: find.byType(FilledButton)),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(jsonResponse(tokensJson('fresh')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(storage.accessToken, 'fresh');
      expect(
        jsonDecode(backend.calls('POST', '/auth/login').single.body),
        <String, Object?>{'email': 'sana@example.com', 'password': 'secret123'},
      );
      expect(find.text('Complex Numbers'), findsOneWidget);
    });

    testWidgets('wrong password shows a bilingual error and stays', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..onError('POST', '/auth/login', 401, 'not_authenticated');
      await pumpApp(tester, backend);
      await tester.enterText(loginEmail, 'sana@example.com');
      await tester.enterText(loginPassword, 'wrong-pass');
      await tester.tap(loginButton);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Email ya password ghalat hai. (Incorrect email or password)',
        ),
        findsOneWidget,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('server down shows the Urdu/English message', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..handle(
          'POST',
          '/auth/login',
          (_) async => throw http.ClientException('Connection refused'),
        );
      await pumpApp(tester, backend);
      await tester.enterText(loginEmail, 'sana@example.com');
      await tester.enterText(loginPassword, 'secret123');
      await tester.tap(loginButton);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Server se connection nahi hua'),
        findsOneWidget,
      );
    });

    testWidgets('password visibility toggle', (WidgetTester tester) async {
      await pumpApp(tester, FakeBackend());
      EditableText field() => tester.widget<EditableText>(
        find.descendant(of: loginPassword, matching: find.byType(EditableText)),
      );
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });

    testWidgets('link opens the register screen', (WidgetTester tester) async {
      await pumpApp(tester, FakeBackend());
      await tester.tap(find.text('Account nahi hai? Register karein'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
    });
  });

  group('Register screen', () {
    Future<void> openRegister(WidgetTester tester, FakeBackend backend) async {
      await pumpApp(tester, backend);
      await tester.tap(find.text('Account nahi hai? Register karein'));
      await tester.pumpAndSettle();
    }

    final Finder name = find.byKey(const ValueKey<String>('register-name'));
    final Finder email = find.byKey(const ValueKey<String>('register-email'));
    final Finder password = find.byKey(
      const ValueKey<String>('register-password'),
    );
    final Finder button = find.byKey(const ValueKey<String>('register-button'));

    testWidgets('validates name, email and password length', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend();
      await openRegister(tester, backend);
      await tester.enterText(email, 'bad');
      await tester.enterText(password, 'short');
      await tester.tap(button);
      await tester.pump();
      expect(find.text('Naam zaroori hai (Name is required)'), findsOneWidget);
      expect(
        find.text('Sahi email likhein (Enter a valid email)'),
        findsOneWidget,
      );
      expect(find.textContaining('kam az kam 8 characters'), findsOneWidget);
      expect(backend.requests, isEmpty);
    });

    testWidgets('register -> auto login -> home', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..withSyllabus()
        ..on('POST', '/auth/register', userJson, status: 201)
        ..on('POST', '/auth/login', tokensJson('new-user'));
      await openRegister(tester, backend);
      await tester.enterText(name, 'Sana Ahmed');
      await tester.enterText(email, 'sana@example.com');
      await tester.enterText(password, 'secret123');
      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        backend.requests
            .map((http.Request r) => '${r.method} ${r.url.path}')
            .take(3),
        <String>[
          'POST /api/v1/auth/register',
          'POST /api/v1/auth/login',
          'GET /api/v1/auth/me',
        ],
      );
    });

    testWidgets('email already registered', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..onError('POST', '/auth/register', 409, 'conflict');
      await openRegister(tester, backend);
      await tester.enterText(name, 'Sana');
      await tester.enterText(email, 'sana@example.com');
      await tester.enterText(password, 'secret123');
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.textContaining('Email already registered'), findsOneWidget);
    });

    testWidgets('link back to login', (WidgetTester tester) async {
      await openRegister(tester, FakeBackend());
      await tester.tap(find.text('Pehle se account hai? Login karein'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('Session handling', () {
    testWidgets('logout asks, clears data and returns to login', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      final StorageService storage = await pumpApp(
        tester,
        backend,
        prefs: loggedIn,
      );
      await storage.addRecentQuestion(11, 'private');

      await tester.tap(find.byKey(const ValueKey<String>('logout-button')));
      await tester.pumpAndSettle();
      expect(find.text('Logout karein?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.hasToken, isFalse);
      expect(storage.recentQuestions(11), isEmpty);
    });

    testWidgets('cancelling logout keeps the user signed in', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await pumpApp(tester, backend, prefs: loggedIn);
      await tester.tap(find.byKey(const ValueKey<String>('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets(
      'a 401 mid-session sends the student to login with an explanation',
      (WidgetTester tester) async {
        final FakeBackend backend = FakeBackend()
          ..withSyllabus()
          ..onError('GET', '/units/1/topics', 401, 'not_authenticated')
          ..onError('POST', '/auth/refresh', 401, 'not_authenticated');
        await pumpApp(tester, backend, prefs: loggedIn);

        await tester.tap(find.text('Complex Numbers'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
          find.text('Session khatam ho gaya. Dobara login karein.'),
          findsOneWidget,
        );
      },
    );
  });
}
