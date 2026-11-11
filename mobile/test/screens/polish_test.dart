/// Phase 6 polish: API URL switching, keyboard handling, back-button guards,
/// cached progress and token refresh mid-session.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/core/constants.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/screens/home/home_screen.dart';
import 'package:mathmentor/screens/progress/progress_screen.dart';
import 'package:mathmentor/screens/tutor/tutor_screen.dart';
import 'package:mathmentor/services/progress_service.dart';
import 'package:mathmentor/widgets/progress_widgets.dart';
import 'package:mathmentor/widgets/tutor_response_card.dart';
import 'package:provider/provider.dart';

import '../helpers.dart';

final Finder tutorInput = find.byKey(const ValueKey<String>('tutor-input'));
final Unit unit = Unit.fromJson(unitsJson.first);
final Topic topic = Topic.fromJson(topicsJson.first);

FakeBackend everything() => FakeBackend()
  ..withSyllabus()
  ..on('POST', '/tutor/ask', tutorJson())
  ..on('GET', '/practice/random', practiceQuestionsJson)
  ..on('GET', '/progress/', progressJson())
  ..on('GET', '/progress/weak-topics', weakTopicsJson);

/// A plain screen with a button that pushes the tutor, so "back" has somewhere to go.
Widget launcher({String? initialQuestion}) => Builder(
  builder: (BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TutorScreen(
              topic: topic,
              unit: unit,
              initialQuestion: initialQuestion,
            ),
          ),
        ),
        child: const Text('open tutor'),
      ),
    ),
  ),
);

Future<void> openTutorFromLauncher(
  WidgetTester tester,
  FakeBackend backend, {
  String? initialQuestion,
}) async {
  usePhoneScreen(tester);
  await pumpApp(
    tester,
    backend,
    prefs: loggedIn,
    home: launcher(initialQuestion: initialQuestion),
  );
  await tester.tap(find.text('open tutor'));
  await tester.pumpAndSettle();
  expect(find.byType(TutorScreen), findsOneWidget);
}

Future<void> pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<String>('bottom-nav')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

String pointsText(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('stat-points')),
            matching: find.byType(Text),
          )
          .first,
    )
    .data!;

void main() {
  group('API base URL', () {
    test('defaults to the emulator host', () {
      expect(ApiConfig.resolveBaseUrl(), 'http://10.0.2.2:8000');
      expect(
        ApiConfig.resolveBaseUrl(target: 'emulator'),
        ApiConfig.emulatorBaseUrl,
      );
      // The value compiled into this test run (no --dart-define).
      expect(ApiConfig.baseUrl, ApiConfig.emulatorBaseUrl);
    });

    test('API_TARGET=usb uses 127.0.0.1 for adb reverse', () {
      expect(ApiConfig.resolveBaseUrl(target: 'usb'), 'http://127.0.0.1:8000');
    });

    test('API_BASE_URL wins over API_TARGET', () {
      expect(
        ApiConfig.resolveBaseUrl(
          override: 'http://192.168.1.10:8000',
          target: 'usb',
        ),
        'http://192.168.1.10:8000',
      );
    });

    test('normal requests time out after 30 seconds, the tutor later', () {
      expect(ApiConfig.requestTimeout, const Duration(seconds: 30));
      expect(
        ApiConfig.tutorTimeout.compareTo(ApiConfig.requestTimeout),
        greaterThan(0),
      );
    });
  });

  group('Keyboard', () {
    testWidgets('tapping outside a text field closes the keyboard', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(tester, everything());
      await tester.showKeyboard(tutorInput);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(find.byKey(const ValueKey<String>('tutor-context')));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('keyboard opening scrolls the chat to the latest answer', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(tester, everything());
      for (int i = 0; i < 3; i++) {
        await tester.enterText(tutorInput, 'Question $i');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey<String>('send-button')));
        await tester.pumpAndSettle();
      }
      expect(find.byType(TutorResponseCard, skipOffstage: false), findsWidgets);
      final ScrollableState list = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      list.position.jumpTo(0);
      await tester.pump();

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(list.position.pixels, list.position.maxScrollExtent);
      expect(list.position.pixels, greaterThan(0));

      // Already open: further metric changes don't yank the list again.
      list.position.jumpTo(0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 901);
      await tester.pumpAndSettle();
      expect(list.position.pixels, 0);
    });
  });

  group('Tutor back button', () {
    testWidgets('empty input: back leaves without asking', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(tester, everything());
      await pressBack(tester);
      expect(find.byType(TutorScreen), findsNothing);
      expect(find.text('Sawaal bheja nahi gaya'), findsNothing);
    });

    testWidgets('typed but unsent question: confirm, stay, then discard', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(tester, everything());
      await tester.enterText(tutorInput, 'z = 3 + 4i ka modulus?');
      await tester.pump();

      await pressBack(tester);
      expect(find.text('Sawaal bheja nahi gaya'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('stay-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsOneWidget);
      expect(find.text('z = 3 + 4i ka modulus?'), findsOneWidget);

      await pressBack(tester);
      await tester.tap(find.byKey(const ValueKey<String>('discard-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsNothing);
      expect(find.text('open tutor'), findsOneWidget);
    });

    testWidgets('a pre-filled recent question does not trigger the dialog', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(
        tester,
        everything(),
        initialQuestion: 'What is i?',
      );
      await pressBack(tester);
      expect(find.byType(TutorScreen), findsNothing);
    });

    testWidgets('after sending, back leaves without asking', (
      WidgetTester tester,
    ) async {
      await openTutorFromLauncher(tester, everything());
      await tester.enterText(tutorInput, 'What is i?');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('send-button')));
      await tester.pumpAndSettle();
      await pressBack(tester);
      expect(find.byType(TutorScreen), findsNothing);
    });
  });

  group('Home back button', () {
    testWidgets('back on Progress returns to the Units tab first', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(tester, everything(), prefs: loggedIn);
      await tapTab(tester, 'Progress');

      await pressBack(tester);
      final BottomNavigationBar nav = tester.widget(
        find.byKey(const ValueKey<String>('bottom-nav')),
      );
      expect(nav.currentIndex, HomeScreen.unitsTab);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('Caching', () {
    testWidgets(
      'progress shows cached data instantly, refreshes in background',
      (WidgetTester tester) async {
        final FakeBackend backend = everything();
        usePhoneScreen(tester);
        await pumpApp(tester, backend, prefs: loggedIn);
        await tapTab(tester, 'Progress');
        expect(pointsText(tester), '🏆 245');

        await tapTab(tester, 'Units');
        final Completer<http.Response> slow = Completer<http.Response>();
        backend.handle('GET', '/progress/', (_) => slow.future);
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('bottom-nav')),
            matching: find.text('Progress'),
          ),
        );
        await tester.pump();
        await tester.pump();

        // Old numbers immediately, with a thin "refreshing" bar — no full-screen spinner.
        expect(find.byType(StatsCard), findsOneWidget);
        expect(pointsText(tester), '🏆 245');
        expect(
          find.byKey(const ValueKey<String>('progress-refreshing')),
          findsOneWidget,
        );

        slow.complete(jsonResponse(progressJson(points: 280)));
        await tester.pumpAndSettle();
        expect(pointsText(tester), '🏆 280');
        expect(
          find.byKey(const ValueKey<String>('progress-refreshing')),
          findsNothing,
        );
        expect(backend.calls('GET', '/progress/'), hasLength(2));
      },
    );

    testWidgets('logout wipes the cached progress', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = everything();
      usePhoneScreen(tester);
      await pumpApp(tester, backend, prefs: loggedIn);
      await tapTab(tester, 'Progress');
      final ProgressService service = tester
          .element(find.byType(ProgressScreen))
          .read<ProgressService>();
      expect(service.cachedSummary, isNotNull);
      expect(service.cachedWeakTopics, isNotEmpty);

      await tapTab(tester, 'Units');
      await tester.tap(find.byKey(const ValueKey<String>('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(service.cachedSummary, isNull);
      expect(service.cachedWeakTopics, isNull);
    });

    testWidgets('units and topics are fetched once, then served from cache', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = everything();
      usePhoneScreen(tester);
      await pumpApp(tester, backend, prefs: loggedIn);
      for (int i = 0; i < 2; i++) {
        await tester.tap(find.text('Complex Numbers'));
        await tester.pumpAndSettle();
        expect(find.text('Introduction to Complex Numbers'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(backend.calls('GET', '/units/'), hasLength(1));
      expect(backend.calls('GET', '/units/1/topics'), hasLength(1));
    });
  });

  group('Token expiry mid-session', () {
    testWidgets('silent refresh then the original request is retried', (
      WidgetTester tester,
    ) async {
      int topicCalls = 0;
      final FakeBackend backend = everything()
        ..handle('GET', '/units/1/topics', (http.Request request) async {
          topicCalls++;
          return request.headers['Authorization'] == 'Bearer access-2'
              ? jsonResponse(topicsJson)
              : errorResponse(401, 'not_authenticated');
        })
        ..on('POST', '/auth/refresh', <String, Object?>{
          'access_token': 'access-2',
          'refresh_token': 'refresh-2',
          'token_type': 'bearer',
        });
      usePhoneScreen(tester);
      await pumpApp(tester, backend, prefs: loggedIn);

      await tester.tap(find.text('Complex Numbers'));
      await tester.pumpAndSettle();

      // The student never notices: topics appear, no login screen.
      expect(find.text('Introduction to Complex Numbers'), findsOneWidget);
      expect(topicCalls, 2);
      expect(backend.calls('POST', '/auth/refresh'), hasLength(1));
    });
  });
}
