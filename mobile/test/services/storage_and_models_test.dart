import 'package:flutter_test/flutter_test.dart';
import 'package:mathmentor/core/validators.dart';
import 'package:mathmentor/models/formula.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/models/tutor_response.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/models/user.dart';
import 'package:mathmentor/services/api_exception.dart';
import 'package:mathmentor/services/storage_service.dart';

import '../helpers.dart';

void main() {
  group('StorageService', () {
    test('saves and clears tokens', () async {
      final StorageService storage = await makeStorage();
      expect(storage.hasToken, isFalse);
      await storage.saveTokens(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      );
      expect(
        (storage.accessToken, storage.refreshToken, storage.hasToken),
        ('a', 'r', true),
      );
      await storage.clearTokens();
      expect(storage.hasToken, isFalse);
    });

    test(
      'recent questions: newest first, no duplicates, max 5, per topic',
      () async {
        final StorageService storage = await makeStorage();
        for (final String q in <String>[
          'q1',
          'q2',
          'q3',
          'q4',
          'q5',
          'q6',
          'q3',
          '  ',
        ]) {
          await storage.addRecentQuestion(1, q);
        }
        await storage.addRecentQuestion(2, 'other');
        expect(storage.recentQuestions(1), <String>[
          'q3',
          'q6',
          'q5',
          'q4',
          'q2',
        ]);
        expect(storage.recentQuestions(2), <String>['other']);
        expect(storage.recentQuestions(3), isEmpty);
      },
    );

    test('logout wipes tokens and question history', () async {
      final StorageService storage = await makeStorage(loggedIn);
      await storage.addRecentQuestion(1, 'private question');
      await storage.clearUserData();
      expect(storage.hasToken, isFalse);
      expect(storage.recentQuestions(1), isEmpty);
    });
  });

  group('models', () {
    test('User and tokens parse', () {
      final User user = User.fromJson(userJson);
      expect(
        (user.id, user.email, user.firstName, user.isActive),
        (7, 'sana@example.com', 'Sana', true),
      );
      final AuthTokens tokens = AuthTokens.fromJson(<String, Object?>{
        'access_token': 'a',
        'refresh_token': 'r',
      });
      expect(tokens.accessToken, 'a');
    });

    test('Unit parses', () {
      final Unit unit = Unit.fromJson(unitsJson[2]);
      expect(
        (unit.unitNumber, unit.title, unit.pageNumber),
        (3, 'Vectors', 74),
      );
    });

    test('Topic difficulty mapping (unknown -> medium)', () {
      expect(Topic.fromJson(topicsJson[0]).difficulty, Difficulty.easy);
      expect(Topic.fromJson(topicsJson[2]).difficulty, Difficulty.hard);
      expect(Difficulty.fromApi('weird'), Difficulty.medium);
      expect(Difficulty.fromApi(null), Difficulty.medium);
    });

    test('Formula prettifies SymPy syntax for students', () {
      final Formula f = Formula.fromJson(formulasJson.first);
      expect(f.displayExpression, 'i^2 = -1');
      expect(prettifyMath('sqrt(x**2 + y**2)'), '√(x^2 + y^2)');
      expect(prettifyMath('sin(theta)*cos(pi/2)'), 'sin(θ)·cos(π/2)');
      expect(prettifyMath('Integral'), 'Integral'); // whole words only
    });

    test('TutorResponse parses and tolerates missing fields', () {
      final TutorResponse r = TutorResponse.fromJson(tutorJson(warning: 'w'));
      expect(r.steps, hasLength(2));
      expect(r.formulasUsed.single, startsWith('Square'));
      expect(
        (r.sympyVerified, r.verificationStatus, r.warning),
        (true, VerificationStatus.verified, 'w'),
      );
      final TutorResponse minimal = TutorResponse.fromJson(<String, Object?>{
        'question': 'q',
        'explanation': 'e',
      });
      expect(minimal.steps, isEmpty);
      expect(minimal.verificationStatus, VerificationStatus.unverifiable);
      expect(minimal.verificationConfidence, 0);
    });

    test('step prefixes are stripped because the UI numbers steps', () {
      expect(stripStepPrefix('Step 1: Definition'), 'Definition');
      expect(stripStepPrefix('step 12) Last'), 'Last');
      expect(stripStepPrefix('No prefix here'), 'No prefix here');
    });
  });

  group('ApiException messages (Urdu/English)', () {
    test('spec messages', () {
      expect(
        const ApiException(ApiErrorType.noInternet).userMessage,
        'Internet connection check karein.',
      );
      expect(
        const ApiException(ApiErrorType.serverDown).userMessage,
        startsWith('Server se connection nahi hua'),
      );
      expect(
        const ApiException(ApiErrorType.aiUnavailable).userMessage,
        'AI tutor abhi available nahi, thodi der baad try karein.',
      );
      expect(
        const ApiException(ApiErrorType.timeout).userMessage,
        'Request timeout, dobara try karein.',
      );
    });

    test('every type has a message; retry only where it helps', () {
      for (final ApiErrorType type in ApiErrorType.values) {
        expect(ApiException(type).userMessage, isNotEmpty);
      }
      expect(const ApiException(ApiErrorType.timeout).isRetryable, isTrue);
      expect(
        const ApiException(ApiErrorType.invalidCredentials).isRetryable,
        isFalse,
      );
      expect(
        const ApiException(ApiErrorType.unauthorized).toString(),
        contains('unauthorized'),
      );
    });
  });

  group('validators', () {
    test('email', () {
      expect(Validators.email(''), contains('zaroori'));
      expect(Validators.email('not-an-email'), contains('Sahi email'));
      expect(Validators.email(' sana@example.com '), isNull);
    });

    test('passwords', () {
      expect(Validators.requiredPassword(''), contains('zaroori'));
      expect(Validators.requiredPassword('x'), isNull);
      expect(Validators.newPassword('short'), contains('8 characters'));
      expect(Validators.newPassword('x' * 129), contains('128'));
      expect(Validators.newPassword('long-enough'), isNull);
    });

    test('name', () {
      expect(Validators.name('   '), contains('zaroori'));
      expect(Validators.name('x' * 101), contains('lamba'));
      expect(Validators.name('Sana'), isNull);
    });
  });
}
