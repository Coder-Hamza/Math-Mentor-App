import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/core/constants.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/screens/practice/practice_screen.dart';
import 'package:mathmentor/widgets/practice_result_card.dart';
import 'package:mathmentor/widgets/topic_card.dart';

import '../helpers.dart';

final Finder submitButton = find.byKey(const ValueKey<String>('submit-answer'));
final Finder nextButton = find.byKey(const ValueKey<String>('next-question'));
final Finder answerInput = find.byKey(const ValueKey<String>('answer-input'));
final Finder resultCard = find.byType(PracticeResultCard);
final Finder correctAnswerText = find.byKey(
  const ValueKey<String>('correct-answer'),
);

Finder option(int i) => find.byKey(ValueKey<String>('option-$i'));

bool submitEnabled(WidgetTester tester) =>
    tester.widget<ButtonStyleButton>(submitButton).onPressed != null;

Map<String, dynamic> lastSubmit(FakeBackend backend) =>
    jsonDecode(backend.calls('POST', '/practice/submit').last.body)
        as Map<String, dynamic>;

Future<void> openPractice(
  WidgetTester tester,
  FakeBackend backend, {
  int? unitId,
  VoidCallback? onHome,
}) async {
  usePhoneScreen(tester);
  await pumpApp(
    tester,
    backend,
    prefs: loggedIn,
    home: PracticeScreen(unitId: unitId, onHome: onHome),
  );
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('loads 5 random questions and shows the first one', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson);
    await openPractice(tester, backend);

    final http.Request request = backend
        .calls('GET', '/practice/random')
        .single;
    expect(request.url.queryParameters, <String, String>{'count': '5'});

    expect(find.text('Sawaal 1/3'), findsOneWidget);
    expect(find.text('Evaluate the determinant |2 3; 1 4|.'), findsOneWidget);
    expect(
      find.textContaining('Unit 2: Matrices & Determinants'),
      findsOneWidget,
    );
    final DifficultyBadge badge = tester.widget(find.byType(DifficultyBadge));
    expect(badge.difficulty, Difficulty.easy);
    // Never show an answer before the student submits.
    expect(correctAnswerText, findsNothing);
    expect(resultCard, findsNothing);
  });

  testWidgets('practice for one unit sends unit_id', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson);
    await openPractice(tester, backend, unitId: 6);
    expect(
      backend.calls('GET', '/practice/random').single.url.queryParameters,
      <String, String>{'count': '5', 'unit_id': '6'},
    );
  });

  testWidgets('MCQ: four lettered options, select, submit, result card', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..on('POST', '/practice/submit', practiceResultJson());
    await openPractice(tester, backend);

    for (int i = 0; i < 4; i++) {
      expect(option(i), findsOneWidget);
    }
    for (final String letter in <String>['A', 'B', 'C', 'D']) {
      expect(find.text(letter), findsOneWidget);
    }
    expect(answerInput, findsNothing);
    expect(submitEnabled(tester), isFalse);

    await tapAndSettle(tester, option(1)); // "11" (wrong choice first) ...
    await tapAndSettle(tester, option(0)); // ... then change mind to "5"
    expect(submitEnabled(tester), isTrue);
    await tapAndSettle(tester, submitButton);

    expect(lastSubmit(backend)['question_id'], 4);
    expect(lastSubmit(backend)['student_answer'], '5');
    expect(lastSubmit(backend)['time_taken_seconds'], isA<int>());

    expect(resultCard, findsOneWidget);
    expect(find.text('✅'), findsOneWidget);
    expect(find.text('Sahi jawab!'), findsOneWidget);
    expect(tester.widget<Text>(correctAnswerText).data, '5');
    expect(find.text('ad - bc = 8 - 3 = 5.'), findsOneWidget);
    expect(find.text('+15 points'), findsOneWidget);
    expect(find.text('Bilkul sahi! Bohat acha! ✅'), findsOneWidget);
    expect(submitButton, findsNothing);
    expect(find.text('Agla Sawaal'), findsOneWidget);

    // Options are locked after grading and the right one is marked.
    final McqOptionButton first = tester.widget(option(0));
    expect(first.onTap, isNull);
    expect(first.state, OptionState.correct);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('MCQ wrong choice is marked and the right one shown', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..on(
        'POST',
        '/practice/submit',
        practiceResultJson(correct: false, points: 0, total: 0, streak: 0),
      );
    await openPractice(tester, backend);
    await tapAndSettle(tester, option(2));
    await tapAndSettle(tester, submitButton);

    expect(find.text('❌'), findsOneWidget);
    expect(find.text('Ghalat jawab'), findsOneWidget);
    expect(find.text('Koi baat nahi, dobara koshish karo 💪'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget); // chosen wrong option
    expect(
      tester.widget<McqOptionButton>(option(0)).state,
      OptionState.correct,
    );
    expect(find.text('+0 points'), findsOneWidget);
  });

  testWidgets('short answer uses a text field', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', <Object?>[practiceQuestionsJson[1]])
      ..on(
        'POST',
        '/practice/submit',
        practiceResultJson(correctAnswer: '3/2', points: 25, total: 40),
      );
    await openPractice(tester, backend);

    expect(option(0), findsNothing);
    expect(answerInput, findsOneWidget);
    expect(tester.widget<TextField>(answerInput).maxLength, 500);
    expect(submitEnabled(tester), isFalse);

    await tester.enterText(answerInput, '   ');
    await tester.pump();
    expect(submitEnabled(tester), isFalse);

    await tester.enterText(answerInput, ' 1.5 ');
    await tester.pump();
    await tapAndSettle(tester, submitButton);

    expect(lastSubmit(backend)['student_answer'], '1.5');
    expect(tester.widget<Text>(correctAnswerText).data, '3/2');
    expect(tester.widget<TextField>(answerInput).enabled, isFalse);
    // Only one question: the button now leads to the summary.
    expect(find.text('Result dekhein'), findsOneWidget);
  });

  testWidgets('shows a spinner while grading', (WidgetTester tester) async {
    final Completer<http.Response> pending = Completer<http.Response>();
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..handle('POST', '/practice/submit', (_) => pending.future);
    await openPractice(tester, backend);
    await tapAndSettle(tester, option(0));
    await tester.tap(submitButton);
    await tester.pump();

    expect(find.text('Check ho raha hai...'), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    pending.complete(jsonResponse(practiceResultJson()));
    await tester.pumpAndSettle();
    expect(resultCard, findsOneWidget);
  });

  testWidgets('streak and already-solved notes', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..on(
        'POST',
        '/practice/submit',
        practiceResultJson(
          points: 0,
          streak: 3,
          alreadySolved: true,
          encouragement: 'Shabash! 3 sawaal lagataar sahi! 🔥',
        ),
      );
    await openPractice(tester, backend);
    await tapAndSettle(tester, option(0));
    await tapAndSettle(tester, submitButton);
    expect(find.text('Shabash! 3 sawaal lagataar sahi! 🔥'), findsOneWidget);
    expect(find.text('🔥 Streak: 3'), findsOneWidget);
    expect(find.textContaining('pehle hi solve'), findsOneWidget);
  });

  testWidgets('full session: next question, summary, play again and home', (
    WidgetTester tester,
  ) async {
    int homeTaps = 0;
    final List<Map<String, Object?>> results = <Map<String, Object?>>[
      practiceResultJson(points: 15, total: 15),
      practiceResultJson(correct: false, points: 0, total: 15, streak: 0),
      practiceResultJson(points: 35, total: 50),
    ];
    int submitted = 0;
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..handle(
        'POST',
        '/practice/submit',
        (_) async => jsonResponse(results[submitted++]),
      );
    await openPractice(tester, backend, onHome: () => homeTaps++);

    // Q1 (MCQ)
    await tapAndSettle(tester, option(0));
    await tapAndSettle(tester, submitButton);
    expect(
      find.byKey(const ValueKey<String>('session-points')),
      findsOneWidget,
    );
    expect(find.text('⭐ 15'), findsOneWidget);
    await tapAndSettle(tester, nextButton);

    // Q2 (short): a fresh, empty answer box.
    expect(find.text('Sawaal 2/3'), findsOneWidget);
    expect(resultCard, findsNothing);
    expect(tester.widget<TextField>(answerInput).controller!.text, isEmpty);
    await tester.enterText(answerInput, '2/3');
    await tester.pump();
    await tapAndSettle(tester, submitButton);
    await tapAndSettle(tester, nextButton);

    // Q3 (long)
    expect(find.text('Sawaal 3/3'), findsOneWidget);
    await tester.enterText(answerInput, 'R = 65/8, r = 4');
    await tester.pump();
    await tapAndSettle(tester, submitButton);
    expect(find.text('Result dekhein'), findsOneWidget);
    await tapAndSettle(tester, nextButton);

    // Summary
    expect(
      find.byKey(const ValueKey<String>('practice-summary')),
      findsOneWidget,
    );
    expect(find.text('🏆 50'), findsOneWidget);
    expect(find.text('✅ 2'), findsOneWidget);
    expect(find.text('❌ 1'), findsOneWidget);
    expect(find.text('Dobara Khelo'), findsOneWidget);

    await tapAndSettle(tester, find.text('Home'));
    expect(homeTaps, 1);

    await tapAndSettle(tester, find.text('Dobara Khelo'));
    expect(backend.calls('GET', '/practice/random'), hasLength(2));
    expect(find.text('Sawaal 1/3'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('session-points')), findsNothing);
  });

  testWidgets('load error offers retry', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend()
      ..onError('GET', '/practice/random', 503, 'maintenance');
    await openPractice(tester, backend);
    expect(
      find.textContaining('Server se connection nahi hua'),
      findsOneWidget,
    );

    backend.on('GET', '/practice/random', practiceQuestionsJson);
    await tapAndSettle(tester, find.text(AppStrings.retry));
    expect(find.text('Sawaal 1/3'), findsOneWidget);
  });

  testWidgets('submit error keeps the answer and offers retry', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', practiceQuestionsJson)
      ..handle(
        'POST',
        '/practice/submit',
        (_) async => throw http.ClientException('Network is unreachable'),
      );
    await openPractice(tester, backend);
    await tapAndSettle(tester, option(0));
    await tapAndSettle(tester, submitButton);

    expect(find.text('Internet connection check karein.'), findsOneWidget);
    expect(resultCard, findsNothing);
    expect(tester.widget<McqOptionButton>(option(0)).selected, isTrue);

    backend.on('POST', '/practice/submit', practiceResultJson());
    await tapAndSettle(tester, find.text(AppStrings.retry));
    expect(resultCard, findsOneWidget);
    expect(find.text('Internet connection check karein.'), findsNothing);
  });

  testWidgets('no questions available', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', <Object?>[]);
    await openPractice(tester, backend);
    expect(find.text('Abhi practice ke liye koi sawaal nahi.'), findsOneWidget);
  });

  testWidgets('home without a callback closes the screen', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('GET', '/practice/random', <Object?>[]);
    await pumpApp(tester, backend, prefs: loggedIn, home: const _Launcher());
    await tapAndSettle(tester, find.text('open'));
    expect(find.byType(PracticeScreen), findsOneWidget);
    await tapAndSettle(tester, find.text('Home'));
    expect(find.byType(PracticeScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}

class _Launcher extends StatelessWidget {
  const _Launcher();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const PracticeScreen())),
        child: const Text('open'),
      ),
    ),
  );
}
