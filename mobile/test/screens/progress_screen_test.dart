import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathmentor/core/constants.dart';
import 'package:mathmentor/screens/practice/practice_screen.dart';
import 'package:mathmentor/screens/progress/progress_screen.dart';
import 'package:mathmentor/widgets/progress_widgets.dart';

import '../helpers.dart';

Future<FakeBackend> openProgress(
  WidgetTester tester, {
  Map<String, Object?>? progress,
  List<Map<String, Object?>>? weak,
}) async {
  final FakeBackend backend = FakeBackend()
    ..on('GET', '/progress/', progress ?? progressJson())
    ..on('GET', '/progress/weak-topics', weak ?? weakTopicsJson)
    ..on('GET', '/practice/random', practiceQuestionsJson);
  usePhoneScreen(tester);
  await pumpApp(tester, backend, prefs: loggedIn, home: const ProgressScreen());
  return backend;
}

Text statText(WidgetTester tester, String key) => tester.widget<Text>(
  find
      .descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(Text),
      )
      .first,
);

LinearProgressIndicator bar(WidgetTester tester, int unitId) =>
    tester.widget<LinearProgressIndicator>(
      find.descendant(
        of: find.byKey(ValueKey<String>('unit-progress-$unitId')),
        matching: find.byType(LinearProgressIndicator),
      ),
    );

void main() {
  testWidgets('stats card shows points, accuracy, streak and attempts', (
    WidgetTester tester,
  ) async {
    await openProgress(tester);
    expect(find.byType(StatsCard), findsOneWidget);
    expect(statText(tester, 'stat-points').data, '🏆 245');
    expect(statText(tester, 'stat-accuracy').data, '66.7%');
    expect(statText(tester, 'stat-streak').data, '🔥 4');
    expect(statText(tester, 'stat-attempted').data, '18');
    for (final String label in <String>[
      'Total Points',
      'Accuracy',
      'Current Streak',
      'Questions Attempted',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('unit progress bars render with value and colour', (
    WidgetTester tester,
  ) async {
    await openProgress(tester);
    expect(find.byType(UnitProgressRow), findsNWidgets(3));
    expect(find.text('Unit 1: Complex Numbers'), findsOneWidget);
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('55.5%'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('3/3 topics practised'), findsOneWidget);

    expect(bar(tester, 1).value, 0.25);
    expect(bar(tester, 1).color, AppColors.hard); // red < 40
    expect(bar(tester, 2).value, closeTo(0.555, 1e-9));
    expect(bar(tester, 2).color, AppColors.medium); // orange 40-70
    expect(bar(tester, 3).value, 1.0);
    expect(bar(tester, 3).color, AppColors.easy); // green > 70
  });

  testWidgets('weak topics are highlighted with a practice button', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await openProgress(tester);
    final Finder card = find.byKey(const ValueKey<String>('weak-topic-61'));
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Combinations'), findsOneWidget);
    expect(find.textContaining('33.3% (1/3 sahi)'), findsOneWidget);
    expect(
      tester
          .widget<Card>(find.descendant(of: card, matching: find.byType(Card)))
          .color,
      AppColors.errorBackground,
    );

    await tester.tap(find.text('Practice karein'));
    await tester.pumpAndSettle();
    expect(find.byType(PracticeScreen), findsOneWidget);
    expect(find.text('Practice: Unit 6'), findsOneWidget);
    expect(
      backend
          .calls('GET', '/practice/random')
          .single
          .url
          .queryParameters['unit_id'],
      '6',
    );
  });

  testWidgets('no weak topics: encouraging message', (
    WidgetTester tester,
  ) async {
    await openProgress(tester, weak: <Map<String, Object?>>[]);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('no-weak-topics')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Koi weak topic nahi. Shabash! 🌟'), findsOneWidget);
  });

  testWidgets('new student is invited to start practising', (
    WidgetTester tester,
  ) async {
    await openProgress(
      tester,
      progress: progressJson(
        points: 0,
        attempted: 0,
        correct: 0,
        accuracy: 0,
        streak: 0,
        units: <Map<String, Object?>>[unitProgressJson(1, 0, attempted: 0)],
      ),
      weak: <Map<String, Object?>>[],
    );
    expect(statText(tester, 'stat-points').data, '🏆 0');
    expect(statText(tester, 'stat-accuracy').data, '0%');
    expect(find.textContaining('Practice shuru karein'), findsOneWidget);
    expect(bar(tester, 1).value, 0.0);
  });

  testWidgets('pull to refresh reloads both requests', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await openProgress(tester);
    expect(backend.calls('GET', '/progress/'), hasLength(1));
    backend.on('GET', '/progress/', progressJson(points: 300));

    await tester.fling(find.byType(StatsCard), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(backend.calls('GET', '/progress/'), hasLength(2));
    expect(backend.calls('GET', '/progress/weak-topics'), hasLength(2));
    expect(statText(tester, 'stat-points').data, '🏆 300');
  });

  testWidgets('error shows retry, and a failed refresh keeps the data', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..onError('GET', '/progress/', 503, 'maintenance')
      ..on('GET', '/progress/weak-topics', weakTopicsJson);
    usePhoneScreen(tester);
    await pumpApp(
      tester,
      backend,
      prefs: loggedIn,
      home: const ProgressScreen(),
    );
    expect(
      find.textContaining('Server se connection nahi hua'),
      findsOneWidget,
    );
    expect(find.byType(StatsCard), findsNothing);

    backend.on('GET', '/progress/', progressJson());
    await tester.tap(find.text(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(find.byType(StatsCard), findsOneWidget);

    backend.onError('GET', '/progress/weak-topics', 500, 'boom');
    await tester.fling(find.byType(StatsCard), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(StatsCard), findsOneWidget); // stale data stays
    expect(find.textContaining('Server mein masla'), findsOneWidget);
  });

  group('helpers', () {
    test('progressColor thresholds', () {
      expect(progressColor(0), AppColors.hard);
      expect(progressColor(39.9), AppColors.hard);
      expect(progressColor(40), AppColors.medium);
      expect(progressColor(70), AppColors.medium);
      expect(progressColor(70.1), AppColors.easy);
      expect(progressColor(100), AppColors.easy);
    });

    test('formatPercent drops a trailing .0', () {
      expect(formatPercent(45), '45');
      expect(formatPercent(66.7), '66.7');
      expect(formatPercent(0), '0');
    });
  });
}
