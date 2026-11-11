import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathmentor/screens/practice/practice_screen.dart';
import 'package:mathmentor/screens/progress/progress_screen.dart';
import 'package:mathmentor/widgets/unit_card.dart';

import '../helpers.dart';

FakeBackend backendWithEverything() => FakeBackend()
  ..withSyllabus()
  ..on('GET', '/practice/random', practiceQuestionsJson)
  ..on('POST', '/practice/submit', practiceResultJson())
  ..on('GET', '/progress/', progressJson())
  ..on('GET', '/progress/weak-topics', weakTopicsJson);

Future<void> tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const ValueKey<String>('bottom-nav')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('bottom navigation has Units, Practice and Progress', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = backendWithEverything();
    usePhoneScreen(tester);
    await pumpApp(tester, backend, prefs: loggedIn);

    final BottomNavigationBar nav = tester.widget(
      find.byKey(const ValueKey<String>('bottom-nav')),
    );
    expect(nav.items.map((BottomNavigationBarItem i) => i.label), <String>[
      'Units',
      'Solver',
      'Practice',
      'Progress',
    ]);
    expect(nav.currentIndex, 0);
    expect(find.byType(UnitCard), findsWidgets);
    // Other tabs are not built (no requests) until opened.
    expect(backend.calls('GET', '/practice/random'), isEmpty);
    expect(backend.calls('GET', '/progress/'), isEmpty);
  });

  testWidgets('practice tab keeps its session while switching tabs', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = backendWithEverything();
    usePhoneScreen(tester);
    await pumpApp(tester, backend, prefs: loggedIn);

    await tapTab(tester, 'Practice');
    expect(find.byType(PracticeScreen), findsOneWidget);
    expect(find.text('Sawaal 1/3'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('option-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('submit-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('next-question')));
    await tester.pumpAndSettle();
    expect(find.text('Sawaal 2/3'), findsOneWidget);

    await tapTab(tester, 'Units');
    await tapTab(tester, 'Practice');
    expect(find.text('Sawaal 2/3'), findsOneWidget);
    expect(backend.calls('GET', '/practice/random'), hasLength(1));
  });

  testWidgets('progress tab reloads every time it is opened', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = backendWithEverything();
    usePhoneScreen(tester);
    await pumpApp(tester, backend, prefs: loggedIn);

    await tapTab(tester, 'Progress');
    expect(find.byType(ProgressScreen), findsOneWidget);
    expect(find.text('Meri Progress'), findsOneWidget);
    expect(backend.calls('GET', '/progress/'), hasLength(1));

    await tapTab(tester, 'Units');
    await tapTab(tester, 'Progress');
    expect(backend.calls('GET', '/progress/'), hasLength(2));
  });

  testWidgets('summary Home button returns to the Units tab', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = backendWithEverything()
      ..on('GET', '/practice/random', <Object?>[practiceQuestionsJson.first]);
    usePhoneScreen(tester);
    await pumpApp(tester, backend, prefs: loggedIn);

    await tapTab(tester, 'Practice');
    await tester.tap(find.byKey(const ValueKey<String>('option-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('submit-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Result dekhein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    final BottomNavigationBar nav = tester.widget(
      find.byKey(const ValueKey<String>('bottom-nav')),
    );
    expect(nav.currentIndex, 0);
    expect(find.text('MathMentor AI'), findsOneWidget);
  });
}
