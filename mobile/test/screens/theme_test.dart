/// Glassmorphism theme: ThemeProvider persistence, the toggle on every screen,
/// glass widgets, animations and the reduced-effects (low-end) fallback.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mathmentor/app.dart';
import 'package:mathmentor/core/theme.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/providers/theme_provider.dart';
import 'package:mathmentor/screens/auth/login_screen.dart';
import 'package:mathmentor/screens/splash_screen.dart';
import 'package:mathmentor/screens/tutor/tutor_screen.dart';
import 'package:mathmentor/services/storage_service.dart';
import 'package:mathmentor/widgets/glass_card.dart';
import 'package:mathmentor/widgets/glass_scaffold.dart';
import 'package:mathmentor/widgets/gradient_background.dart';
import 'package:mathmentor/widgets/loading_widget.dart';
import 'package:mathmentor/widgets/motion.dart';
import 'package:mathmentor/widgets/progress_widgets.dart';

import '../helpers.dart';

final Finder toggle = find.byKey(const ValueKey<String>('theme-toggle'));

FakeBackend everything() => FakeBackend()
  ..withSyllabus()
  ..on('POST', '/tutor/ask', tutorJson())
  ..on('GET', '/practice/random', practiceQuestionsJson)
  ..on('GET', '/progress/', progressJson())
  ..on('GET', '/progress/weak-topics', weakTopicsJson);

/// The OS "remove animations" setting — also the app's low-end fallback.
void reduceEffects(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

Brightness brightnessOf(WidgetTester tester, Finder finder) =>
    Theme.of(tester.element(finder)).brightness;

/// Pumps [child] inside a themed MaterialApp (no app services needed).
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? buildDarkTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('ThemeProvider', () {
    test('defaults to dark mode when nothing is saved', () async {
      final StorageService storage = await makeStorage();
      final ThemeProvider provider = ThemeProvider(storage);
      expect(provider.isDarkMode, isTrue);
      expect(provider.themeMode, ThemeMode.dark);
      expect(storage.isDarkMode, isNull);
    });

    test('toggles, notifies and persists under "isDarkMode"', () async {
      final StorageService storage = await makeStorage();
      final ThemeProvider provider = ThemeProvider(storage);
      int notifications = 0;
      provider.addListener(() => notifications++);

      await provider.toggleTheme();
      expect(provider.isDarkMode, isFalse);
      expect(provider.themeMode, ThemeMode.light);
      expect(storage.isDarkMode, isFalse);

      await provider.toggleTheme();
      expect(provider.isDarkMode, isTrue);
      expect(storage.isDarkMode, isTrue);
      expect(notifications, 2);

      await provider.setDarkMode(true); // no change -> no notification
      expect(notifications, 2);
    });

    test('loads the saved preference on start', () async {
      final StorageService storage = await makeStorage(<String, Object>{
        'isDarkMode': false,
      });
      expect(ThemeProvider(storage).isDarkMode, isFalse);
    });

    test('the preference survives logout (clearUserData)', () async {
      final StorageService storage = await makeStorage(<String, Object>{
        ...loggedIn,
        'isDarkMode': false,
      });
      await storage.clearUserData();
      expect(storage.hasToken, isFalse);
      expect(storage.isDarkMode, isFalse);
    });
  });

  group('Theme toggle in the app', () {
    testWidgets('dark by default; toggling switches to light and is saved', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      final StorageService storage = await pumpApp(
        tester,
        everything(),
        prefs: loggedIn,
      );
      expect(brightnessOf(tester, toggle), Brightness.dark);
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.light_mode)),
        findsOneWidget,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(brightnessOf(tester, toggle), Brightness.light);
      expect(
        find.descendant(of: toggle, matching: find.byIcon(Icons.dark_mode)),
        findsOneWidget,
      );
      expect(storage.isDarkMode, isFalse);
      expect(
        Theme.of(tester.element(toggle)).extension<GlassPalette>()!.accent,
        GlassPalette.light.accent,
      );
    });

    testWidgets('the switch animates over 400 ms (colours are lerped)', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(tester, everything(), prefs: loggedIn);
      await tester.tap(toggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final Color mid = Theme.of(tester.element(toggle))
          .extension<GlassPalette>()!
          .backgroundTop;
      expect(mid, isNot(GlassPalette.dark.backgroundTop));
      expect(mid, isNot(GlassPalette.light.backgroundTop));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(toggle))
            .extension<GlassPalette>()!
            .backgroundTop,
        GlassPalette.light.backgroundTop,
      );
    });

    testWidgets('a saved light preference is used from the first frame', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(
        tester,
        everything(),
        prefs: <String, Object>{...loggedIn, 'isDarkMode': false},
      );
      expect(brightnessOf(tester, toggle), Brightness.light);
    });

    testWidgets('every screen has the toggle in its app bar', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(tester, everything(), prefs: loggedIn);
      expect(toggle, findsOneWidget); // Units

      await tester.tap(find.text('Complex Numbers'));
      await tester.pumpAndSettle();
      expect(toggle, findsOneWidget); // Unit detail
      await tester.tap(find.text('Introduction to Complex Numbers'));
      await tester.pumpAndSettle();
      expect(toggle, findsOneWidget); // Topic detail
      await tester.tap(find.byKey(const ValueKey<String>('ask-ai-button')));
      await tester.pumpAndSettle();
      expect(find.byType(TutorScreen), findsOneWidget);
      expect(toggle, findsOneWidget); // Tutor
      for (int i = 0; i < 3; i++) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      for (final String tab in <String>['Practice', 'Progress']) {
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey<String>('bottom-nav')),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
        expect(toggle, findsOneWidget, reason: tab);
      }
    });

    testWidgets('login screen: glass form card and toggle', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(tester, everything());
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('auth-card')), findsOneWidget);
      expect(toggle, findsOneWidget);
      expect(find.byType(GradientButton), findsOneWidget);
    });
  });

  group('Screen transitions', () {
    testWidgets('pages fade in over 300 ms', (WidgetTester tester) async {
      usePhoneScreen(tester);
      await pumpApp(tester, everything(), prefs: loggedIn);
      await tester.tap(find.text('Complex Numbers'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      final Iterable<FadeTransition> fades = tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.text('Unit 1').last,
          matching: find.byType(FadeTransition),
        ),
      );
      expect(
        fades.any(
          (FadeTransition f) => f.opacity.value > 0 && f.opacity.value < 1,
        ),
        isTrue,
      );
      await tester.pumpAndSettle();
      expect(const FadePageTransitionsBuilder(), isA<PageTransitionsBuilder>());
    });
  });

  group('Splash', () {
    testWidgets('floating maths symbols bob while the session is checked', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      final Completer<http.Response> me = Completer<http.Response>();
      final FakeBackend backend = everything()
        ..handle('GET', '/auth/me', (_) => me.future);
      final StorageService storage = await makeStorage(loggedIn);
      await tester.pumpWidget(
        MathMentorApp(
          storage: storage,
          httpClient: backend.client,
          baseUrl: testBaseUrl,
        ),
      );
      await tester.pump();

      expect(find.byType(FloatingMathSymbols), findsOneWidget);
      for (final String s in FloatingMathSymbols.symbols) {
        expect(find.text(s), findsOneWidget);
      }
      expect(
        find.byKey(const ValueKey<String>('splash-logo-card')),
        findsOneWidget,
      );
      final double before = tester.getTopLeft(find.text('π')).dy;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.getTopLeft(find.text('π')).dy, isNot(before));

      me.complete(jsonResponse(userJson));
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('with reduced motion the symbols stay still', (
      WidgetTester tester,
    ) async {
      reduceEffects(tester);
      usePhoneScreen(tester);
      final Completer<http.Response> me = Completer<http.Response>();
      final FakeBackend backend = everything()
        ..handle('GET', '/auth/me', (_) => me.future);
      final StorageService storage = await makeStorage(loggedIn);
      await tester.pumpWidget(
        MathMentorApp(
          storage: storage,
          httpClient: backend.client,
          baseUrl: testBaseUrl,
        ),
      );
      await tester.pump();
      final double before = tester.getTopLeft(find.text('π')).dy;
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tester.getTopLeft(find.text('π')).dy, before);
      me.complete(jsonResponse(userJson));
      await tester.pumpAndSettle();
    });
  });

  group('GlassCard', () {
    testWidgets('blurs the backdrop (grouped) when effects are allowed', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const GradientBackground(child: GlassCard(child: Text('glass'))),
      );
      expect(find.byType(BackdropGroup), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('glass'),
          matching: find.byType(BackdropFilter),
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });

    testWidgets('list cards and reduced effects skip the blur', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const GlassCard(blur: false, child: Text('a')));
      expect(find.byType(BackdropFilter), findsNothing);

      reduceEffects(tester);
      await pumpThemed(tester, const GlassCard(child: Text('b')));
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
    });

    testWidgets('onTap gives an ink ripple and fires', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpThemed(
        tester,
        GlassCard(onTap: () => taps++, child: const Text('tap me')),
      );
      expect(
        find.ancestor(of: find.text('tap me'), matching: find.byType(InkWell)),
        findsOneWidget,
      );
      await tester.tap(find.text('tap me'));
      expect(taps, 1);
    });

    test('fill: palette glass, custom opacity, or tinted', () {
      const GlassPalette p = GlassPalette.dark;
      expect(GlassCard.fillFor(p), p.glass);
      expect(GlassCard.fillFor(p, opacity: 0.3).a, closeTo(0.3, 0.01));
      final Color tinted = GlassCard.fillFor(p, tint: p.error);
      expect(tinted, isNot(p.glass));
      expect(tinted.r, greaterThan(p.glass.r - 0.0001));
    });

    testWidgets('glow and border colour are painted', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const GlassCard(
          glowColor: Colors.green,
          borderColor: Colors.green,
          child: Text('glow'),
        ),
      );
      final DecoratedBox shadowBox = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.text('glow'),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      final BoxShadow shadow =
          (shadowBox.decoration as BoxDecoration).boxShadow!.single;
      expect(shadow.color.g, greaterThan(shadow.color.r));
    });
  });

  group('Background and motion', () {
    testWidgets('orbs ease in once, then the background is idle', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const GradientBackground(child: SizedBox.expand()),
      );
      expect(tester.binding.hasScheduledFrame, isTrue); // entry animation
      // Settles (an endless animation would make pumpAndSettle time out), and
      // well within the 1.2 s entry plus a few frames.
      final int frames = await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
      );
      expect(frames, lessThanOrEqualTo(14));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: const GradientBackground(child: SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('gradient-background')),
        findsOneWidget,
      );
    });

    testWidgets('cards appear with a 200 ms fade + slide', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const Appear(child: Text('hi')));
      FadeTransition fade() => tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text('hi'),
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(fade().opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 100));
      expect(fade().opacity.value, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(fade().opacity.value, 1);
    });

    testWidgets('reduced motion: cards appear immediately', (
      WidgetTester tester,
    ) async {
      reduceEffects(tester);
      await pumpThemed(tester, const Appear(child: Text('hi')));
      expect(
        tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: find.text('hi'),
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value,
        1,
      );
    });

    testWidgets('buttons scale to 95% while pressed', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        Center(
          child: SizedBox(
            width: 200,
            child: GradientButton(onPressed: () {}, child: const Text('Go')),
          ),
        ),
      );
      double scale() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.text('Go')),
      );
      await tester.pump();
      expect(scale(), 0.95);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(scale(), 1);
    });

    testWidgets('disabled gradient button is dimmed and does not shrink', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const GradientButton(onPressed: null, child: Text('Off')),
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0.55,
      );
      await tester.startGesture(tester.getCenter(find.text('Off')));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    });

    testWidgets('loading shimmer moves; static with reduced motion', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const LoadingWidget(message: 'Wait'));
      LinearGradient gradient() =>
          (tester
                          .widget<DecoratedBox>(
                            find.descendant(
                              of: find.byType(ShimmerBar),
                              matching: find.byType(DecoratedBox),
                            ),
                          )
                          .decoration
                      as BoxDecoration)
                  .gradient!
              as LinearGradient;
      final AlignmentGeometry start = gradient().begin;
      await tester.pump(const Duration(milliseconds: 300));
      expect(gradient().begin, isNot(start));

      reduceEffects(tester);
      await pumpThemed(tester, const LoadingWidget(message: 'Wait'));
      await tester.pump();
      final AlignmentGeometry still = gradient().begin;
      await tester.pump(const Duration(milliseconds: 300));
      expect(gradient().begin, still);
    });
  });

  group('Palette and typography', () {
    test('dark and light palettes match the design spec', () {
      expect(GlassPalette.dark.backgroundTop, const Color(0xFF0A0E21));
      expect(GlassPalette.dark.backgroundBottom, const Color(0xFF1A1F3A));
      expect(GlassPalette.dark.accent, const Color(0xFF4FC3F7));
      expect(GlassPalette.dark.secondary, const Color(0xFFFFB74D));
      expect(GlassPalette.dark.success, const Color(0xFF69F0AE));
      expect(GlassPalette.dark.error, const Color(0xFFFF5252));
      expect(GlassPalette.dark.glass.a, closeTo(0.08, 0.005));
      expect(GlassPalette.dark.glassBorder.a, closeTo(0.15, 0.005));
      expect(GlassPalette.light.backgroundTop, const Color(0xFFF0F4FF));
      expect(GlassPalette.light.accent, const Color(0xFF1565C0));
      expect(GlassPalette.light.secondary, const Color(0xFFF57C00));
      expect(GlassPalette.light.textPrimary, const Color(0xFF1A1A2E));
      expect(GlassPalette.light.glass.a, closeTo(0.6, 0.005));
      expect(GlassPalette.light.glassBorder.a, closeTo(0.8, 0.005));
    });

    test('lerp blends every colour; copyWith overrides', () {
      final GlassPalette half = GlassPalette.dark.lerp(GlassPalette.light, 0.5);
      expect(
        half.accent,
        Color.lerp(GlassPalette.dark.accent, GlassPalette.light.accent, 0.5),
      );
      expect(GlassPalette.dark.lerp(null, 0.5), GlassPalette.dark);
      final GlassPalette custom = GlassPalette.dark.copyWith(
        accent: Colors.pink,
        glass: Colors.black,
      );
      expect((custom.accent, custom.glass), (Colors.pink, Colors.black));
      expect(custom.error, GlassPalette.dark.error);
      expect(GlassPalette.dark.copyWith().accent, GlassPalette.dark.accent);
    });

    test('type scale: heading, subheading, body, caption', () {
      final TextTheme t = buildDarkTheme().textTheme;
      expect(t.headlineSmall!.fontSize, 24);
      expect(t.headlineSmall!.fontWeight, FontWeight.w700);
      expect(t.headlineSmall!.letterSpacing, -0.5);
      expect(t.titleLarge!.fontSize, 18);
      expect(t.titleLarge!.fontWeight, FontWeight.w600);
      expect(t.bodyMedium!.fontSize, 14);
      expect(t.bodyMedium!.height, 1.5);
      expect(t.bodySmall!.fontSize, 12);
      expect(t.bodySmall!.color, GlassPalette.dark.textSecondary);
      expect(t.bodyMedium!.fontFamily, appFontFamily);
    });

    test('both themes are transparent glass themes', () {
      for (final ThemeData theme in <ThemeData>[
        buildDarkTheme(),
        buildLightTheme(),
      ]) {
        expect(theme.scaffoldBackgroundColor, Colors.transparent);
        expect(theme.appBarTheme.backgroundColor, Colors.transparent);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.inputDecorationTheme.filled, isTrue);
        expect(theme.extension<GlassPalette>(), isNotNull);
      }
      expect(buildLightTheme().brightness, Brightness.light);
    });

    testWidgets('gradient text and section headers use a ShaderMask', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const Column(
          children: <Widget>[
            SectionHeader('Formulas', icon: Icons.functions_rounded),
            GradientText('x', maxLines: 1),
          ],
        ),
      );
      expect(find.byType(ShaderMask), findsNWidgets(2));
      expect(find.byIcon(Icons.functions_rounded), findsOneWidget);
    });

    testWidgets('gradient progress bar fills to its value', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const SizedBox(width: 200, child: GradientProgressBar(value: 0.25)),
      );
      final Align fill = tester.widget<Align>(
        find
            .descendant(
              of: find.byType(GradientProgressBar),
              matching: find.byWidgetPredicate(
                (Widget w) => w is Align && w.widthFactor != null,
              ),
            )
            .first,
      );
      expect(fill.widthFactor, 0.25);
    });

    testWidgets('glass bottom bar blurs, unless effects are reduced', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const GlassBottomBar(child: Text('nav')));
      expect(find.byType(BackdropFilter), findsOneWidget);
      reduceEffects(tester);
      await pumpThemed(tester, const GlassBottomBar(child: Text('nav')));
      await tester.pump();
      expect(find.byType(BackdropFilter), findsNothing);
    });
  });

  group('Restyled widgets', () {
    testWidgets('tutor answer has a gradient header with the topic', (
      WidgetTester tester,
    ) async {
      usePhoneScreen(tester);
      await pumpApp(
        tester,
        everything(),
        prefs: loggedIn,
        home: TutorScreen(
          topic: Topic.fromJson(topicsJson.first),
          unit: Unit.fromJson(unitsJson.first),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('tutor-input')),
        'What is i?',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('send-button')));
      await tester.pumpAndSettle();
      final Finder header = find.byKey(
        const ValueKey<String>('response-header'),
      );
      expect(header, findsOneWidget);
      expect(
        find.descendant(
          of: header,
          matching: find.text('Introduction to Complex Numbers'),
        ),
        findsOneWidget,
      );
    });
  });
}
