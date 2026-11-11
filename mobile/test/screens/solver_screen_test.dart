import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/core/constants.dart';
import 'package:mathmentor/models/solver_result.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/screens/solver/solver_screen.dart';
import 'package:mathmentor/screens/tutor/tutor_screen.dart';
import 'package:mathmentor/widgets/tutor_response_card.dart';

import '../helpers.dart';

final Finder chapterField = find.byKey(
  const ValueKey<String>('solver-chapter'),
);
final Finder questionField = find.byKey(
  const ValueKey<String>('solver-question'),
);
final Finder bookField = find.byKey(
  const ValueKey<String>('solver-book-answer'),
);
final Finder solveButton = find.byKey(const ValueKey<String>('solve-button'));
final Finder loading = find.byKey(const ValueKey<String>('solver-loading'));
final Finder resultView = find.byKey(const ValueKey<String>('solver-result'));

const String question = 'Solve x^2 - 5x + 6 = 0';

Map<String, Object?> solverJson({
  String? bookAnswer,
  bool answerVerified = false,
  bool sympyVerified = true,
  String? warning,
  List<Map<String, Object?>>? steps,
  String solution = 'Sawal: ...\n\nJawab: x = 2, x = 3',
}) => <String, Object?>{
  'question': question,
  'chapter': 'Complex Numbers',
  'solution': solution,
  'steps':
      steps ??
      <Map<String, Object?>>[
        <String, Object?>{
          'step_number': 1,
          'title': 'Factors talash karein',
          'explanation': 'Do numbers chahiye jinka product 6 aur sum -5 ho.',
          'formula_used': null,
          'calculation': 'x^2 - 2x - 3x + 6 = 0',
        },
        <String, Object?>{
          'step_number': 2,
          'title': 'Factorise karein',
          'explanation': 'Common factors bahar nikalein.',
          'formula_used': 'ab = 0 => a = 0 or b = 0',
          'calculation': '(x - 2)(x - 3) = 0',
        },
        <String, Object?>{
          'step_number': 3,
          'title': 'Zero rakhein',
          'explanation': 'Har factor ko zero ke barabar rakhein.',
          'formula_used': '',
          'calculation': null,
        },
      ],
  'method_used': 'Factorisation Method',
  'formulas_applied': <String>['Zero product: ab = 0 => a = 0 or b = 0'],
  'key_concepts': <String>['Quadratic equation', 'Factorisation'],
  'answer_verified': answerVerified,
  'book_answer': bookAnswer,
  'our_answer': 'x = 2, x = 3',
  'sympy_verified': sympyVerified,
  'difficulty_level': 'easy',
  'pro_tip': 'Jawab ko wapas equation mein rakh kar check karein.',
  'warning': warning,
};

Future<FakeBackend> openSolver(
  WidgetTester tester, {
  Object? response,
  FakeBackend? backend,
}) async {
  final FakeBackend b = backend ?? (FakeBackend()..withSyllabus());
  if (response != null) {
    b.on('POST', '/solver/solve', response);
  }
  usePhoneScreen(tester);
  await pumpApp(tester, b, prefs: loggedIn, home: const SolverScreen());
  return b;
}

Future<void> fillForm(
  WidgetTester tester, {
  String chapter = 'Complex Numbers',
  String q = question,
  String? book,
}) async {
  await tester.enterText(chapterField, chapter);
  await tester.enterText(questionField, q);
  if (book != null) {
    await tester.enterText(bookField, book);
  }
  await tester.pump();
}

Future<void> solve(WidgetTester tester) async {
  await tester.ensureVisible(solveButton);
  await tester.tap(solveButton);
  await tester.pumpAndSettle();
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await scrollNear(tester, finder);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> scrollNear(WidgetTester tester, Finder finder) =>
    tester.scrollUntilVisible(
      finder,
      200,
      // The list's own Scrollable (text fields inside it have Scrollables too).
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey<String>('solver-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Map<String, dynamic> lastBody(FakeBackend backend) =>
    jsonDecode(backend.calls('POST', '/solver/solve').last.body)
        as Map<String, dynamic>;

void main() {
  group('Form', () {
    testWidgets('chapter and question are required', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = await openSolver(
        tester,
        response: solverJson(),
      );
      expect(find.text('Chapter ka naam likhein'), findsOneWidget);
      expect(find.text('Book ka jawab (optional)'), findsOneWidget);
      expect(find.text('Hal Karo'), findsOneWidget);
      expect(
        find.descendant(
          of: solveButton,
          matching: find.byIcon(Icons.search_rounded),
        ),
        findsOneWidget,
      );

      await solve(tester);
      expect(find.text('Chapter ka naam zaroori hai'), findsOneWidget);
      expect(find.text('Sawal likhna zaroori hai'), findsOneWidget);
      expect(backend.calls('POST', '/solver/solve'), isEmpty);

      await tester.enterText(chapterField, '   ');
      await tester.enterText(questionField, question);
      await solve(tester);
      expect(find.text('Chapter ka naam zaroori hai'), findsOneWidget);
      expect(backend.calls('POST', '/solver/solve'), isEmpty);
    });

    testWidgets('"Done" on the book-answer field solves', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = await openSolver(
        tester,
        response: solverJson(),
      );
      await fillForm(tester, book: '2, 3');
      await tester.showKeyboard(bookField);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(backend.calls('POST', '/solver/solve'), hasLength(1));
      expect(resultView, findsOneWidget);
    });

    testWidgets('length limits match the API', (WidgetTester tester) async {
      await openSolver(tester);
      int? limit(Finder f) => tester
          .widget<TextField>(
            find.descendant(of: f, matching: find.byType(TextField)),
          )
          .maxLength;
      expect(limit(chapterField), ApiConfig.maxSolverChapterLength);
      expect(limit(questionField), 1000);
      expect(limit(bookField), 500);
    });
  });

  testWidgets('loading state while the AI solves, then the result', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> pending = Completer<http.Response>();
    final FakeBackend backend = FakeBackend()
      ..withSyllabus()
      ..handle('POST', '/solver/solve', (_) => pending.future);
    await openSolver(tester, backend: backend);
    await fillForm(tester);
    await tester.tap(solveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(loading, findsOneWidget);
    expect(find.textContaining('Sawal hal ho raha hai'), findsOneWidget);
    expect(find.text('Hal ho raha hai...'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: questionField,
              matching: find.byType(TextField),
            ),
          )
          .enabled,
      isFalse,
    );

    pending.complete(jsonResponse(solverJson()));
    await tester.pumpAndSettle();
    expect(loading, findsNothing);
    expect(resultView, findsOneWidget);
  });

  testWidgets('without a book answer: full result, no book check', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await openSolver(
      tester,
      response: solverJson(),
    );
    await fillForm(tester);
    await solve(tester);

    expect(lastBody(backend), <String, Object?>{
      'chapter_name': 'Complex Numbers',
      'question': question,
      'book_answer': null,
      'language': 'urdu_english',
    });

    expect(
      find.byKey(const ValueKey<String>('solver-chapter-badge')),
      findsOneWidget,
    );
    expect(find.text('Tareeqa: Factorisation Method'), findsOneWidget);
    expect(find.text('Easy'), findsOneWidget);
    for (final String label in <String>[
      'Pehla Qadam',
      'Doosra Qadam',
      'Teesra Qadam',
    ]) {
      await scrollTo(tester, find.text(label));
      expect(find.text(label), findsOneWidget);
    }
    await scrollTo(tester, find.text('Zero product: ab = 0 => a = 0 or b = 0'));
    await scrollTo(tester, find.text('Factorisation'));
    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('solver-our-answer')),
    );
    expect(find.text('x = 2, x = 3'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('book-match')), findsNothing);
    expect(find.text('SymPy verified'), findsOneWidget);
    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('solver-pro-tip')),
    );
    expect(find.textContaining('wapas equation mein'), findsOneWidget);
    expect(find.text('💡'), findsOneWidget);
    expect(find.byType(WarningBox), findsNothing);
  });

  testWidgets('steps expand: first open, others open on tap', (
    WidgetTester tester,
  ) async {
    await openSolver(tester, response: solverJson());
    await fillForm(tester);
    await solve(tester);

    await scrollTo(tester, find.text('Pehla Qadam'));
    expect(
      find.text('Do numbers chahiye jinka product 6 aur sum -5 ho.'),
      findsOneWidget,
    );
    expect(find.text('x^2 - 2x - 3x + 6 = 0'), findsOneWidget);
    expect(find.text('Common factors bahar nikalein.'), findsNothing);

    await scrollTo(tester, find.text('Doosra Qadam'));
    await tester.tap(find.text('Doosra Qadam'));
    await tester.pumpAndSettle();
    expect(find.text('Common factors bahar nikalein.'), findsOneWidget);
    final Finder step2 = find.byKey(const ValueKey<String>('solver-step-2'));
    expect(
      find.descendant(
        of: step2,
        matching: find.byKey(const ValueKey<String>('step-formula')),
      ),
      findsOneWidget,
    );
    expect(find.text('(x - 2)(x - 3) = 0'), findsOneWidget);

    // Step 3 has an empty formula and no calculation: neither box is shown.
    await scrollTo(tester, find.text('Teesra Qadam'));
    await tester.tap(find.text('Teesra Qadam'));
    await tester.pumpAndSettle();
    final Finder step3 = find.byKey(const ValueKey<String>('solver-step-3'));
    expect(
      find.descendant(
        of: step3,
        matching: find.byKey(const ValueKey<String>('step-formula')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: step3,
        matching: find.byKey(const ValueKey<String>('step-calculation')),
      ),
      findsNothing,
    );
  });

  testWidgets('book answer that matches shows a green confirmation', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = await openSolver(
      tester,
      response: solverJson(bookAnswer: 'x = 3, x = 2', answerVerified: true),
    );
    await fillForm(tester, book: '  x = 3, x = 2 ');
    await solve(tester);

    expect(lastBody(backend)['book_answer'], 'x = 3, x = 2');
    await scrollTo(tester, find.byKey(const ValueKey<String>('book-match')));
    expect(find.text('✅ Book ke jawab se match karta hai!'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('book-mismatch-note')),
      findsNothing,
    );
  });

  testWidgets('book answer that differs shows a red note and warning', (
    WidgetTester tester,
  ) async {
    await openSolver(
      tester,
      response: solverJson(
        bookAnswer: 'x = 1, x = 6',
        sympyVerified: false,
        warning: 'Hamara jawab book ke jawab se match nahi karta.',
      ),
    );
    await fillForm(tester, book: 'x = 1, x = 6');
    await solve(tester);

    expect(find.byType(WarningBox), findsOneWidget);
    await scrollTo(tester, find.byKey(const ValueKey<String>('book-match')));
    expect(find.text('❌ Book ke jawab se match nahi'), findsOneWidget);
    expect(find.textContaining('Book ka jawab: x = 1, x = 6'), findsOneWidget);
    expect(find.text('Not verified'), findsOneWidget);
  });

  testWidgets('unstructured answer is shown as plain text', (
    WidgetTester tester,
  ) async {
    await openSolver(
      tester,
      response: solverJson(
        steps: <Map<String, Object?>>[],
        solution: 'Plain text solution',
        warning: 'Format sahi nahi aaya.',
      ),
    );
    await fillForm(tester);
    await solve(tester);
    expect(
      find.byKey(const ValueKey<String>('solver-plain-solution')),
      findsOneWidget,
    );
    expect(find.text('Plain text solution'), findsOneWidget);
    expect(find.text('Pehla Qadam'), findsNothing);
  });

  testWidgets('a timeout shows a retry that solves again', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..withSyllabus()
      ..onError('POST', '/solver/solve', 504, 'ai_timeout');
    await openSolver(tester, backend: backend);
    await fillForm(tester);
    await solve(tester);
    expect(find.text('Request timeout, dobara try karein.'), findsOneWidget);

    backend.on('POST', '/solver/solve', solverJson());
    await tester.tap(find.text(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(resultView, findsOneWidget);
    expect(backend.calls('POST', '/solver/solve'), hasLength(2));
  });

  testWidgets('"Dobara Solve Karo" clears the question but keeps the chapter', (
    WidgetTester tester,
  ) async {
    await openSolver(tester, response: solverJson());
    await fillForm(tester, book: '2, 3');
    await solve(tester);

    final Finder again = find.byKey(const ValueKey<String>('solve-again'));
    await scrollTo(tester, again);
    await tester.tap(again);
    await tester.pumpAndSettle();

    expect(resultView, findsNothing);
    String text(Finder f) => tester
        .widget<TextField>(
          find.descendant(of: f, matching: find.byType(TextField)),
        )
        .controller!
        .text;
    expect(text(chapterField), 'Complex Numbers');
    expect(text(questionField), isEmpty);
    expect(text(bookField), isEmpty);
  });

  group('AI Tutor se poochein', () {
    testWidgets('opens the tutor in the matching unit, question pre-filled', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = await openSolver(
        tester,
        response: solverJson(),
      );
      await fillForm(tester);
      await solve(tester);

      final Finder ask = find.byKey(const ValueKey<String>('ask-tutor'));
      await scrollTo(tester, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();

      expect(find.byType(TutorScreen), findsOneWidget);
      final TextField input = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('tutor-input')),
      );
      expect(input.controller!.text, question);
      expect(find.textContaining('Unit 1: Complex Numbers'), findsOneWidget);
      expect(backend.calls('POST', '/tutor/ask'), isEmpty); // never auto-sent
    });

    testWidgets('a long question is cut to the tutor limit (500)', (
      WidgetTester tester,
    ) async {
      final String long = 'x' * 800;
      final Map<String, Object?> body = solverJson()..['question'] = long;
      await openSolver(tester, response: body);
      await fillForm(tester, q: long);
      await solve(tester);
      final Finder ask = find.byKey(const ValueKey<String>('ask-tutor'));
      await scrollTo(tester, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      final TextField input = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('tutor-input')),
      );
      expect(input.controller!.text, 'x' * ApiConfig.maxQuestionLength);
    });

    testWidgets('unknown chapter: the student picks the unit', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> body = solverJson()
        ..['chapter'] = 'Mixed revision';
      final FakeBackend backend = await openSolver(tester, response: body);
      await fillForm(tester, chapter: 'Mixed revision');
      await solve(tester);

      final Finder ask = find.byKey(const ValueKey<String>('ask-tutor'));
      await scrollTo(tester, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('unit-picker')), findsOneWidget);
      expect(find.text('Yeh sawal kis unit ka hai?'), findsOneWidget);

      await tester.tap(find.text('Unit 1: Complex Numbers'));
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsOneWidget);
      expect(backend.calls('GET', '/units/1/topics'), hasLength(1));
    });

    testWidgets('closing the picker stays on the solver', (
      WidgetTester tester,
    ) async {
      final Map<String, Object?> body = solverJson()..['chapter'] = 'Misc';
      await openSolver(tester, response: body);
      await fillForm(tester, chapter: 'Misc');
      await solve(tester);
      final Finder ask = find.byKey(const ValueKey<String>('ask-tutor'));
      await scrollTo(tester, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 40)); // outside the sheet
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsNothing);
      expect(resultView, findsOneWidget);
    });

    testWidgets('a unit without topics shows a message', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..withSyllabus()
        ..on('GET', '/units/1/topics', <Object?>[])
        ..on('POST', '/solver/solve', solverJson());
      await openSolver(tester, backend: backend);
      await fillForm(tester);
      await solve(tester);
      final Finder ask = find.byKey(const ValueKey<String>('ask-tutor'));
      await scrollTo(tester, ask);
      await tester.tap(ask);
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsNothing);
      expect(find.textContaining('topics load nahi ho sake'), findsOneWidget);
    });
  });

  testWidgets('Solver is the second bottom-nav tab', (
    WidgetTester tester,
  ) async {
    usePhoneScreen(tester);
    await pumpApp(tester, FakeBackend()..withSyllabus(), prefs: loggedIn);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('bottom-nav')),
        matching: find.text('Solver'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SolverScreen), findsOneWidget);
    expect(find.text('Sawal Hal Karo'), findsOneWidget);
  });

  group('helpers', () {
    final List<Unit> units = unitsJson.map(Unit.fromJson).toList();

    test('matchUnit finds the unit for a typed chapter', () {
      Unit? match(String chapter) => SolverScreen.matchUnit(chapter, units);
      expect(match('Complex Numbers')?.unitNumber, 1);
      expect(match('complex no.')?.unitNumber, 1);
      expect(match('VECTORS')?.unitNumber, 3);
      expect(match('Binomial theorem')?.unitNumber, 7);
      expect(match('Linear programming ch 9')?.unitNumber, 9);
      expect(match('trigonometry application')?.unitNumber, 11);
      expect(match('Chemistry'), isNull);
      expect(match(''), isNull);
    });

    test('stepLabel uses Urdu ordinals', () {
      expect(stepLabel(1), 'Pehla Qadam');
      expect(stepLabel(2), 'Doosra Qadam');
      expect(stepLabel(10), 'Daswan Qadam');
      expect(stepLabel(11), 'Qadam 11');
    });

    test('SolverResult.fromJson', () {
      final SolverResult r = SolverResult.fromJson(
        solverJson(bookAnswer: ' ', warning: ''),
      );
      expect(r.steps, hasLength(3));
      expect(r.steps.first.formulaUsed, isNull);
      expect(r.steps[1].formulaUsed, 'ab = 0 => a = 0 or b = 0');
      expect(r.steps[2].formulaUsed, isNull); // "" -> null
      expect(r.bookAnswer, isNull);
      expect(r.warning, isNull);
      expect(r.difficulty, Difficulty.easy);
      expect(r.isStructured, isTrue);
      expect(r.formulasApplied, hasLength(1));
      expect(r.keyConcepts, <String>['Quadratic equation', 'Factorisation']);
    });
  });
}
