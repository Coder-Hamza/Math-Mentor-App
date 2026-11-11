import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mathmentor/models/practice_question.dart';
import 'package:mathmentor/models/practice_result.dart';
import 'package:mathmentor/models/progress.dart';
import 'package:mathmentor/models/topic.dart';
import 'package:mathmentor/services/api_service.dart';
import 'package:mathmentor/services/practice_service.dart';
import 'package:mathmentor/services/progress_service.dart';

import '../helpers.dart';

void main() {
  late FakeBackend backend;
  late ApiService api;

  setUp(() async {
    backend = FakeBackend();
    api = ApiService(
      storage: await makeStorage(loggedIn),
      client: backend.client,
      baseUrl: testBaseUrl,
    );
  });

  group('PracticeService', () {
    test('randomQuestions parses MCQ and text questions', () async {
      backend.on('GET', '/practice/random', practiceQuestionsJson);
      final List<PracticeQuestion> questions = await PracticeService(api)
          .randomQuestions();

      expect(
        backend.calls('GET', '/practice/random').single.url.query,
        'count=5',
      );
      expect(
        backend.requests.single.headers['Authorization'],
        'Bearer access-1',
      );
      final PracticeQuestion mcq = questions.first;
      expect(mcq.isMcq, isTrue);
      expect(mcq.questionType, QuestionType.mcq);
      expect(mcq.options, <String>['5', '11', '-5', '8']);
      expect(mcq.difficulty, Difficulty.easy);
      expect((mcq.unitNumber, mcq.unitTitle), (2, 'Matrices & Determinants'));
      expect(questions[1].isMcq, isFalse);
      expect(questions[1].options, isNull);
      expect(questions[2].questionType, QuestionType.long);
    });

    test('randomQuestions with unit and count', () async {
      backend.on('GET', '/practice/random', <Object?>[]);
      await PracticeService(api).randomQuestions(unitId: 3, count: 10);
      expect(backend.requests.single.url.queryParameters, <String, String>{
        'count': '10',
        'unit_id': '3',
      });
    });

    test('submit sends the answer and parses the result', () async {
      backend.on(
        'POST',
        '/practice/submit',
        practiceResultJson(points: 35, total: 120, streak: 3),
      );
      final PracticeResult result = await PracticeService(api)
          .submit(questionId: 4, answer: '5', timeTakenSeconds: 12);

      expect(jsonDecode(backend.requests.single.body), <String, Object?>{
        'question_id': 4,
        'student_answer': '5',
        'time_taken_seconds': 12,
      });
      expect(result.isCorrect, isTrue);
      expect(result.correctAnswer, '5');
      expect(
        (result.pointsEarned, result.newTotalPoints, result.streak),
        (35, 120, 3),
      );
      expect(result.alreadySolved, isFalse);
    });

    test('server errors become ApiException', () async {
      backend.onError('POST', '/practice/submit', 422, 'question_not_gradable');
      await expectLater(
        PracticeService(api)
            .submit(questionId: 19, answer: 'n^2', timeTakenSeconds: 1),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.type,
                'type',
                ApiErrorType.validation,
              )
              .having(
                (ApiException e) => e.code,
                'code',
                'question_not_gradable',
              ),
        ),
      );
    });

    test('unexpected JSON shapes are rejected', () async {
      backend
        ..on('GET', '/practice/random', <String, Object?>{'oops': 1})
        ..on('POST', '/practice/submit', <Object?>[1]);
      final PracticeService service = PracticeService(api);
      await expectLater(
        service.randomQuestions(),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        service.submit(questionId: 1, answer: 'x', timeTakenSeconds: 1),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('ProgressService', () {
    test('getProgress parses totals and units', () async {
      backend.on('GET', '/progress/', progressJson());
      final ProgressSummary summary = await ProgressService(api).getProgress();
      expect(summary.totalPoints, 245);
      expect(summary.totalAttempted, 18);
      expect(summary.totalCorrect, 12);
      expect(summary.accuracyPercent, 66.7);
      expect(summary.currentStreak, 4);
      expect(summary.units, hasLength(3));
      final UnitProgress unit = summary.units[1];
      expect((unit.unitNumber, unit.unitTitle), (2, 'Matrices & Determinants'));
      expect((unit.topicsAttempted, unit.topicsTotal), (1, 3));
      expect((unit.avgScore, unit.progressPercent), (55.5, 55.5));
    });

    test('integer percentages from JSON become doubles', () async {
      backend.on(
        'GET',
        '/progress/',
        progressJson(accuracy: 50)..['accuracy_percent'] = 50,
      );
      final ProgressSummary summary = await ProgressService(api).getProgress();
      expect(summary.accuracyPercent, 50.0);
    });

    test('getWeakTopics', () async {
      backend.on('GET', '/progress/weak-topics', weakTopicsJson);
      final List<WeakTopic> weak = await ProgressService(api).getWeakTopics();
      final WeakTopic topic = weak.single;
      expect((topic.topicId, topic.topicTitle), (61, 'Combinations'));
      expect((topic.unitId, topic.unitNumber), (6, 6));
      expect(topic.unitTitle, 'Permutation, Combination & Probability');
      expect(
        (topic.attempts, topic.correct, topic.accuracyPercent),
        (3, 1, 33.3),
      );
    });

    test('unexpected JSON shapes are rejected', () async {
      backend
        ..on('GET', '/progress/', <Object?>[])
        ..on('GET', '/progress/weak-topics', <String, Object?>{});
      final ProgressService service = ProgressService(api);
      await expectLater(service.getProgress(), throwsA(isA<ApiException>()));
      await expectLater(service.getWeakTopics(), throwsA(isA<ApiException>()));
    });
  });

  test('QuestionType.fromApi', () {
    expect(QuestionType.fromApi('mcq'), QuestionType.mcq);
    expect(QuestionType.fromApi('long'), QuestionType.long);
    expect(QuestionType.fromApi('proof'), QuestionType.proof);
    expect(QuestionType.fromApi('short'), QuestionType.short);
    expect(QuestionType.fromApi(null), QuestionType.short);
  });
}
