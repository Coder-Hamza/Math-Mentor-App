import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/core/constants.dart';
import 'package:mathmentor/core/theme.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/screens/tutor/tutor_screen.dart';
import 'package:mathmentor/services/storage_service.dart';
import 'package:mathmentor/widgets/tutor_response_card.dart';

import '../helpers.dart';

final Finder input = find.byKey(const ValueKey<String>('tutor-input'));
final Finder sendButton = find.byKey(const ValueKey<String>('send-button'));
final Finder loading = find.byKey(const ValueKey<String>('tutor-loading'));

final Unit unit = Unit.fromJson(unitsJson.first);
final Topic topic = Topic.fromJson(topicsJson.first);

Future<StorageService> openTutor(
  WidgetTester tester,
  FakeBackend backend, {
  String? initialQuestion,
}) => pumpApp(
  tester,
  backend,
  prefs: loggedIn,
  home: TutorScreen(topic: topic, unit: unit, initialQuestion: initialQuestion),
);

Future<void> ask(WidgetTester tester, String question) async {
  await tester.enterText(input, question);
  await tester.pump();
  await tester.tap(sendButton);
  await tester.pump();
}

bool sendEnabled(WidgetTester tester) =>
    tester.widget<IconButton>(sendButton).onPressed != null;

void main() {
  testWidgets('shows topic context, hint and an empty state', (
    WidgetTester tester,
  ) async {
    await openTutor(tester, FakeBackend());
    expect(find.text('AI Tutor'), findsOneWidget);
    expect(
      find.textContaining(
        'Unit 1: Complex Numbers › Introduction to Complex Numbers',
      ),
      findsOneWidget,
    );
    expect(find.text(AppStrings.askHint), findsOneWidget);
    expect(find.textContaining('koi bhi sawal poochein'), findsOneWidget);
  });

  testWidgets('send is disabled until something is typed', (
    WidgetTester tester,
  ) async {
    await openTutor(tester, FakeBackend());
    expect(sendEnabled(tester), isFalse);
    await tester.enterText(input, '   ');
    await tester.pump();
    expect(sendEnabled(tester), isFalse);
    await tester.enterText(input, 'What is i?');
    await tester.pump();
    expect(sendEnabled(tester), isTrue);
  });

  testWidgets('question box is limited to 500 characters', (
    WidgetTester tester,
  ) async {
    await openTutor(tester, FakeBackend());
    expect(tester.widget<TextField>(input).maxLength, 500);
  });

  testWidgets('suggestion chips fill the input', (WidgetTester tester) async {
    await openTutor(tester, FakeBackend());
    await tester.tap(find.textContaining('example ke saath samjhayein'));
    await tester.pump();
    expect(
      tester.widget<TextField>(input).controller!.text,
      contains('Introduction to Complex Numbers'),
    );
  });

  testWidgets('loading state while Gemini answers, then the full response', (
    WidgetTester tester,
  ) async {
    final Completer<http.Response> pending = Completer<http.Response>();
    final FakeBackend backend = FakeBackend()
      ..handle('POST', '/tutor/ask', (_) => pending.future);
    final StorageService storage = await openTutor(tester, backend);

    await ask(tester, 'What is i?');

    expect(find.text('What is i?'), findsOneWidget); // question bubble
    expect(loading, findsOneWidget);
    expect(find.textContaining('MathMentor soch raha hai'), findsOneWidget);
    expect(sendEnabled(tester), isFalse); // one question at a time
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);

    pending.complete(jsonResponse(tutorJson()));
    await tester.pumpAndSettle();

    expect(loading, findsNothing);
    expect(find.byType(TutorResponseCard), findsOneWidget);
    // Explanation is rendered as Markdown (bold text inside).
    expect(find.byType(MarkdownBody), findsWidgets);
    expect(
      find.textContaining('z = a + ib', findRichText: true),
      findsOneWidget,
    );
    // Steps are numbered by the UI; the "Step N:" prefix is removed.
    expect(find.text('Steps'), findsOneWidget);
    expect(
      find.textContaining('Definition likhein.', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Step 1:', findRichText: true), findsNothing);
    // Formulas used as chips, prettified.
    expect(
      find.widgetWithText(Chip, 'Square of Imaginary Unit: i^2 = -1'),
      findsOneWidget,
    );
    // Verified badge, no warning.
    expect(find.text('SymPy verified'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('badge-verified')),
      findsOneWidget,
    );
    expect(find.byType(WarningBox), findsNothing);
    // Request contents and history.
    expect(
      jsonDecode(backend.calls('POST', '/tutor/ask').single.body),
      <String, Object?>{
        'question': 'What is i?',
        'topic_id': 11,
        'language': 'urdu_english',
      },
    );
    expect(storage.recentQuestions(11), <String>['What is i?']);
  });

  testWidgets('unverified answer shows a yellow warning', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on(
        'POST',
        '/tutor/ask',
        tutorJson(
          status: 'unverifiable',
          verified: false,
          confidence: 0,
          warning: 'Could not be checked automatically.',
        ),
      );
    await openTutor(tester, backend);
    await ask(tester, 'Prove it');
    await tester.pumpAndSettle();

    expect(find.text('Not verified'), findsOneWidget);
    expect(find.byType(WarningBox), findsOneWidget);
    expect(find.text('Could not be checked automatically.'), findsOneWidget);
    final Container box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(WarningBox),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      WarningBox.backgroundFor(GlassPalette.dark),
    );
  });

  testWidgets('failed verification is clearly flagged', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on(
        'POST',
        '/tutor/ask',
        tutorJson(
          status: 'failed',
          verified: false,
          confidence: 0.5,
          warning: 'Possible mistake.',
        ),
      );
    await openTutor(tester, backend);
    await ask(tester, 'Q');
    await tester.pumpAndSettle();
    expect(find.text('Possible mistake found'), findsOneWidget);
    expect(find.text('SymPy verified'), findsNothing);
    expect(find.byType(WarningBox), findsOneWidget);
  });

  testWidgets(
    'AI unavailable (503) shows the friendly message and retry works',
    (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..onError('POST', '/tutor/ask', 503, 'ai_unavailable');
      await openTutor(tester, backend);
      await ask(tester, 'What is i?');
      await tester.pumpAndSettle();

      expect(
        find.text('AI tutor abhi available nahi, thodi der baad try karein.'),
        findsOneWidget,
      );
      expect(find.text('Dobara try karein'), findsOneWidget);

      backend.on('POST', '/tutor/ask', tutorJson());
      await tester.tap(find.text('Dobara try karein'));
      await tester.pumpAndSettle();

      expect(find.text('SymPy verified'), findsOneWidget);
      expect(backend.calls('POST', '/tutor/ask'), hasLength(2));
      expect(
        find.text('What is i?'),
        findsOneWidget,
      ); // same exchange, not duplicated
    },
  );

  final Map<String, (int, String)> errorCases = <String, (int, String)>{
    'Request timeout, dobara try karein.': (504, 'ai_timeout'),
    'AI tutor abhi bohat busy hai. Ek minute baad dobara try karein.': (
      429,
      'ai_quota_exceeded',
    ),
    'AI tutor abhi available nahi, thodi der baad try karein.': (
      503,
      'ai_model_unavailable',
    ),
  };
  for (final MapEntry<String, (int, String)> c in errorCases.entries) {
    testWidgets('error ${c.value.$1} ${c.value.$2}', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()
        ..onError('POST', '/tutor/ask', c.value.$1, c.value.$2);
      await openTutor(tester, backend);
      await ask(tester, 'Q');
      await tester.pumpAndSettle();
      expect(find.text(c.key), findsOneWidget);
      expect(find.text('Dobara try karein'), findsOneWidget);
    });
  }

  testWidgets('no internet while asking', (WidgetTester tester) async {
    final FakeBackend backend = FakeBackend()
      ..handle(
        'POST',
        '/tutor/ask',
        (_) async => throw http.ClientException('Network is unreachable'),
      );
    await openTutor(tester, backend);
    await ask(tester, 'Q');
    await tester.pumpAndSettle();
    expect(find.text('Internet connection check karein.'), findsOneWidget);
  });

  testWidgets('language menu switches the requested language', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('POST', '/tutor/ask', tutorJson());
    await openTutor(tester, backend);

    await tester.tap(find.byKey(const ValueKey<String>('language-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('· English'), findsOneWidget);

    await ask(tester, 'Q');
    await tester.pumpAndSettle();
    expect(
      jsonDecode(backend.calls('POST', '/tutor/ask').single.body)['language'],
      'english',
    );
  });

  testWidgets('a pre-filled question is not sent until Send is tapped', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('POST', '/tutor/ask', tutorJson());
    await openTutor(tester, backend, initialQuestion: 'Old question');
    expect(tester.widget<TextField>(input).controller!.text, 'Old question');
    expect(backend.calls('POST', '/tutor/ask'), isEmpty);

    await tester.tap(sendButton);
    await tester.pumpAndSettle();
    expect(backend.calls('POST', '/tutor/ask'), hasLength(1));
  });

  testWidgets('several questions build a conversation', (
    WidgetTester tester,
  ) async {
    final FakeBackend backend = FakeBackend()
      ..on('POST', '/tutor/ask', tutorJson());
    await openTutor(tester, backend);
    await ask(tester, 'First?');
    await tester.pumpAndSettle();
    await ask(tester, 'Second?');
    await tester.pumpAndSettle();
    expect(find.text('First?'), findsOneWidget);
    expect(find.text('Second?'), findsOneWidget);
    expect(find.byType(TutorResponseCard), findsNWidgets(2));
  });
}
