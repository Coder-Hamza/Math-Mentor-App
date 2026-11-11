import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mathmentor/core/theme.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/screens/topic/topic_detail_screen.dart';
import 'package:mathmentor/screens/tutor/tutor_screen.dart';
import 'package:mathmentor/screens/unit/unit_detail_screen.dart';
import 'package:mathmentor/services/storage_service.dart';
import 'package:mathmentor/widgets/topic_card.dart';
import 'package:mathmentor/widgets/unit_card.dart';

import '../helpers.dart';

void main() {
  group('Home screen', () {
    testWidgets('renders all 12 units with number, title and page', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await pumpApp(tester, backend, prefs: loggedIn);

      expect(find.text('MathMentor AI'), findsOneWidget); // app bar
      final ScrollableState list = tester.state(find.byType(Scrollable).first);
      for (int i = 0; i < 12; i++) {
        final Finder card = find.byKey(ValueKey<String>('unit-${i + 1}'));
        await tester.scrollUntilVisible(
          card,
          200,
          scrollable: find.byWidget(list.widget),
        );
        expect(
          find.descendant(of: card, matching: find.text(unitTitles[i])),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text('Page ${unitPages[i]}'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: card, matching: find.text('${i + 1}')),
          findsOneWidget,
        );
      }
      expect(find.byType(UnitCard), findsWidgets);
    });

    testWidgets('pull to refresh reloads the units', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await pumpApp(tester, backend, prefs: loggedIn);
      expect(backend.calls('GET', '/units/'), hasLength(1));

      await tester.fling(
        find.text('Complex Numbers'),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(backend.calls('GET', '/units/'), hasLength(2));
    });

    testWidgets('error state offers retry', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..on('GET', '/auth/me', userJson)
        ..onError('GET', '/units/', 503, 'maintenance');
      await pumpApp(tester, backend, prefs: loggedIn);
      expect(
        find.textContaining('Server se connection nahi hua'),
        findsOneWidget,
      );

      backend.on('GET', '/units/', unitsJson);
      await tester.tap(find.text('Dobara try karein'));
      await tester.pumpAndSettle();
      expect(find.text('Complex Numbers'), findsOneWidget);
    });

    testWidgets('tapping a unit opens its topics', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await pumpApp(tester, backend, prefs: loggedIn);
      await tester.tap(find.text('Complex Numbers'));
      await tester.pumpAndSettle();
      expect(find.byType(UnitDetailScreen), findsOneWidget);
      expect(find.text('Unit 1'), findsOneWidget);
    });
  });

  group('Unit detail screen', () {
    Future<void> openUnit(WidgetTester tester, FakeBackend backend) async {
      await pumpApp(tester, backend, prefs: loggedIn);
      await tester.tap(find.text('Complex Numbers'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists topics with colour-coded difficulty badges', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await openUnit(tester, backend);

      expect(find.byType(TopicCard), findsNWidgets(3));
      expect(find.text('Introduction to Complex Numbers'), findsOneWidget);
      expect(find.text('Textbook page 1'), findsOneWidget);

      Color badgeColor(String label) => tester
          .widget<Text>(
            find.descendant(
              of: find.byType(DifficultyBadge),
              matching: find.text(label),
            ),
          )
          .style!
          .color!;
      expect(badgeColor('Easy'), GlassPalette.dark.success);
      expect(badgeColor('Medium'), GlassPalette.dark.secondary);
      expect(badgeColor('Hard'), GlassPalette.dark.error);
      expect(
        DifficultyBadge.colorFor(Difficulty.hard, GlassPalette.dark),
        const Color(0xFFFF5252),
      );
    });

    testWidgets('topics error shows retry', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()
        ..withSyllabus()
        ..onError('GET', '/units/1/topics', 500, 'internal_error');
      await openUnit(tester, backend);
      expect(
        find.text('Server mein masla aa gaya. Dobara try karein.'),
        findsOneWidget,
      );

      backend.on('GET', '/units/1/topics', topicsJson);
      await tester.tap(find.text('Dobara try karein'));
      await tester.pumpAndSettle();
      expect(find.byType(TopicCard), findsNWidgets(3));
    });

    testWidgets('tapping a topic opens topic detail', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await openUnit(tester, backend);
      await tester.tap(find.text('Introduction to Complex Numbers'));
      await tester.pumpAndSettle();
      expect(find.byType(TopicDetailScreen), findsOneWidget);
    });
  });

  group('Topic detail screen', () {
    Future<StorageService> openTopic(
      WidgetTester tester,
      FakeBackend backend, {
      String title = 'Introduction to Complex Numbers',
      Map<String, Object> prefs = loggedIn,
    }) async {
      final StorageService storage = await pumpApp(
        tester,
        backend,
        prefs: prefs,
      );
      await tester.tap(find.text('Complex Numbers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      return storage;
    }

    testWidgets('formulas expand to show the prettified expression', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await openTopic(tester, backend);

      expect(find.text('Square of the imaginary unit'), findsOneWidget);
      expect(find.text('i^2 = -1'), findsNothing); // collapsed
      await tester.tap(find.text('Square of the imaginary unit'));
      await tester.pumpAndSettle();
      expect(find.text('i^2 = -1'), findsOneWidget);
      expect(find.text('i squared is minus one'), findsOneWidget);
    });

    testWidgets('topic without formulas says so', (WidgetTester tester) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await openTopic(tester, backend, title: 'Conjugate and Modulus');
      expect(
        find.text('Is topic ke liye formulas abhi nahi hain.'),
        findsOneWidget,
      );
    });

    testWidgets('Ask AI Tutor opens the tutor for this topic', (
      WidgetTester tester,
    ) async {
      final FakeBackend backend = FakeBackend()..withSyllabus();
      await openTopic(tester, backend);
      await tester.tap(find.byKey(const ValueKey<String>('ask-ai-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsOneWidget);
      expect(find.textContaining('Unit 1: Complex Numbers'), findsOneWidget);
    });

    testWidgets(
      'recent questions are listed and re-open the tutor pre-filled',
      (WidgetTester tester) async {
        final FakeBackend backend = FakeBackend()..withSyllabus();
        await openTopic(
          tester,
          backend,
          prefs: <String, Object>{
            ...loggedIn,
            'recent_questions_11': <String>['What is iota?'],
          },
        );

        expect(find.text('Recent questions'), findsOneWidget);
        await tester.tap(find.text('What is iota?'));
        await tester.pumpAndSettle();
        final TextField input = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('tutor-input')),
        );
        expect(input.controller!.text, 'What is iota?');
        expect(backend.calls('POST', '/tutor/ask'), isEmpty); // never auto-sent
      },
    );
  });
}
