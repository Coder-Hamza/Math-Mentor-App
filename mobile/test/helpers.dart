/// Shared test utilities: a fake backend (no real HTTP) and app pumping helpers.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mathmentor/app.dart';
import 'package:mathmentor/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String testBaseUrl = 'http://test.local';
const String api = '/api/v1';

typedef Handler = Future<http.Response> Function(http.Request request);

http.Response jsonResponse(Object? body, [int status = 200]) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: <String, String>{'content-type': 'application/json'},
    );

http.Response errorResponse(
  int status,
  String code, [
  String message = 'error',
]) => jsonResponse(<String, Object?>{
  'error': <String, Object?>{'code': code, 'message': message, 'details': null},
}, status);

/// In-memory stand-in for the FastAPI backend.
class FakeBackend {
  final Map<String, Handler> _handlers = <String, Handler>{};
  final List<http.Request> requests = <http.Request>[];

  void on(String method, String path, Object? body, {int status = 200}) =>
      _handlers['$method $api$path'] = (_) async => jsonResponse(body, status);

  void onError(String method, String path, int status, String code) =>
      _handlers['$method $api$path'] = (_) async => errorResponse(status, code);

  void handle(String method, String path, Handler handler) =>
      _handlers['$method $api$path'] = handler;

  List<http.Request> calls(String method, String path) => requests
      .where(
        (http.Request r) => r.method == method && r.url.path == '$api$path',
      )
      .toList();

  http.Client get client => MockClient((http.Request request) async {
    requests.add(request);
    final Handler? handler = _handlers['${request.method} ${request.url.path}'];
    if (handler == null) {
      return errorResponse(
        404,
        'not_found',
        'No fake route for ${request.url.path}',
      );
    }
    return handler(request);
  });

  /// The standard happy-path syllabus used by most screen tests.
  void withSyllabus() {
    on('GET', '/auth/me', userJson);
    on('GET', '/units/', unitsJson);
    on('GET', '/units/1/topics', topicsJson);
    on('GET', '/topics/11/formulas', formulasJson);
    on('GET', '/topics/12/formulas', <Object?>[]);
  }
}

Future<StorageService> makeStorage([
  Map<String, Object> values = const <String, Object>{},
]) {
  SharedPreferences.setMockInitialValues(values);
  return StorageService.create();
}

const Map<String, Object> loggedIn = <String, Object>{
  'access_token': 'access-1',
  'refresh_token': 'refresh-1',
};

/// A tall phone-sized viewport (412 x 915 logical pixels) instead of 800 x 600.
void usePhoneScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1236, 2745)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps the whole app (splash first, or [home] directly) against [backend].
Future<StorageService> pumpApp(
  WidgetTester tester,
  FakeBackend backend, {
  Map<String, Object> prefs = const <String, Object>{},
  Widget? home,
}) async {
  final StorageService storage = await makeStorage(prefs);
  await tester.pumpWidget(
    MathMentorApp(
      storage: storage,
      httpClient: backend.client,
      baseUrl: testBaseUrl,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

// ------------------------------------------------------------------ sample data

final Map<String, Object?> userJson = <String, Object?>{
  'id': 7,
  'email': 'sana@example.com',
  'name': 'Sana Ahmed',
  'created_at': '2026-11-11T08:00:00Z',
  'is_active': true,
};

const List<String> unitTitles = <String>[
  'Complex Numbers',
  'Matrices & Determinants',
  'Vectors',
  'Sequences & Series',
  'Miscellaneous Series',
  'Permutation, Combination & Probability',
  'Mathematical Induction & Binomial Theorem',
  'Functions & Graphs',
  'Linear Programming',
  'Trigonometric Identities',
  'Application of Trigonometry',
  'Graphs of Trigonometric Functions',
];
const List<int> unitPages = <int>[
  1,
  25,
  74,
  124,
  162,
  179,
  214,
  238,
  267,
  292,
  317,
  337,
];

final List<Map<String, Object?>> unitsJson = <Map<String, Object?>>[
  for (int i = 0; i < 12; i++)
    <String, Object?>{
      'id': i + 1,
      'unit_number': i + 1,
      'title': unitTitles[i],
      'description': 'About ${unitTitles[i]}',
      'page_number': unitPages[i],
    },
];

final List<Map<String, Object?>> topicsJson = <Map<String, Object?>>[
  <String, Object?>{
    'id': 11,
    'unit_id': 1,
    'title': 'Introduction to Complex Numbers',
    'description': 'The imaginary unit i',
    'difficulty_level': 'easy',
  },
  <String, Object?>{
    'id': 12,
    'unit_id': 1,
    'title': 'Conjugate and Modulus',
    'description': null,
    'difficulty_level': 'medium',
  },
  <String, Object?>{
    'id': 13,
    'unit_id': 1,
    'title': 'Equations in Complex Numbers',
    'description': null,
    'difficulty_level': 'hard',
  },
];

final List<Map<String, Object?>> formulasJson = <Map<String, Object?>>[
  <String, Object?>{
    'id': 101,
    'topic_id': 11,
    'name': 'Square of the imaginary unit',
    'expression': 'I**2 = -1',
    'description': 'i squared is minus one',
  },
];

Map<String, Object?> tutorJson({
  String status = 'verified',
  bool verified = true,
  double confidence = 1.0,
  String? warning,
}) => <String, Object?>{
  'question': 'What is i?',
  'explanation': 'Complex number **z = a + ib** hota hai.',
  'steps': <String>[
    'Step 1: Definition likhein.',
    'Step 2: i^2 = -1 yaad rakhein.',
  ],
  'formulas_used': <String>['Square of Imaginary Unit: I**2 = -1'],
  'sympy_verified': verified,
  'verification_confidence': confidence,
  'verification_status': status,
  'topic': 'Introduction to Complex Numbers',
  'unit': 'Complex Numbers',
  'warning': warning,
};

// ------------------------------------------------------------------ practice & progress

final List<Map<String, Object?>> practiceQuestionsJson = <Map<String, Object?>>[
  <String, Object?>{
    'id': 4,
    'topic_id': 21,
    'topic_title': 'Determinants and Their Properties',
    'unit_id': 2,
    'unit_number': 2,
    'unit_title': 'Matrices & Determinants',
    'question_text': 'Evaluate the determinant |2 3; 1 4|.',
    'difficulty': 'easy',
    'question_type': 'mcq',
    'options': <String>['5', '11', '-5', '8'],
  },
  <String, Object?>{
    'id': 11,
    'topic_id': 41,
    'topic_title': 'Geometric Progression',
    'unit_id': 4,
    'unit_number': 4,
    'unit_title': 'Sequences & Series',
    'question_text':
        'Find the sum of the infinite geometric series 1 + 1/3 + 1/9 + ...',
    'difficulty': 'medium',
    'question_type': 'short',
    'options': null,
  },
  <String, Object?>{
    'id': 33,
    'topic_id': 113,
    'topic_title': 'Circles Connected with a Triangle',
    'unit_id': 11,
    'unit_number': 11,
    'unit_title': 'Application of Trigonometry',
    'question_text': 'Find R and r of the triangle with sides 13, 14 and 15.',
    'difficulty': 'hard',
    'question_type': 'long',
    'options': null,
  },
];

Map<String, Object?> practiceResultJson({
  bool correct = true,
  String correctAnswer = '5',
  int points = 15,
  int total = 15,
  int streak = 1,
  String? encouragement,
  bool alreadySolved = false,
}) => <String, Object?>{
  'is_correct': correct,
  'correct_answer': correctAnswer,
  'explanation': 'ad - bc = 8 - 3 = 5.',
  'points_earned': points,
  'new_total_points': total,
  'streak': streak,
  'encouragement':
      encouragement ??
      (correct
          ? 'Bilkul sahi! Bohat acha! ✅'
          : 'Koi baat nahi, dobara koshish karo 💪'),
  'already_solved': alreadySolved,
};

Map<String, Object?> unitProgressJson(
  int number,
  double percent, {
  int attempted = 1,
  int total = 3,
}) => <String, Object?>{
  'unit_id': number,
  'unit_number': number,
  'unit_title': unitTitles[number - 1],
  'topics_attempted': attempted,
  'topics_total': total,
  'avg_score': percent,
  'progress_percent': percent,
};

Map<String, Object?> progressJson({
  int points = 245,
  int attempted = 18,
  int correct = 12,
  double accuracy = 66.7,
  int streak = 4,
  List<Map<String, Object?>>? units,
}) => <String, Object?>{
  'total_points': points,
  'total_attempted': attempted,
  'total_correct': correct,
  'accuracy_percent': accuracy,
  'current_streak': streak,
  'units_progress':
      units ??
      <Map<String, Object?>>[
        unitProgressJson(1, 25),
        unitProgressJson(2, 55.5),
        unitProgressJson(3, 100, attempted: 3),
      ],
};

final List<Map<String, Object?>> weakTopicsJson = <Map<String, Object?>>[
  <String, Object?>{
    'topic_id': 61,
    'topic_title': 'Combinations',
    'unit_id': 6,
    'unit_number': 6,
    'unit_title': 'Permutation, Combination & Probability',
    'attempts': 3,
    'correct': 1,
    'accuracy_percent': 33.3,
  },
];
