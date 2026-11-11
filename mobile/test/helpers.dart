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
