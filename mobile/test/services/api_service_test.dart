import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mathmentor/models/tutor_response.dart';
import 'package:mathmentor/models/unit.dart';
import 'package:mathmentor/services/api_service.dart';
import 'package:mathmentor/services/storage_service.dart';

import '../helpers.dart';

void main() {
  late FakeBackend backend;

  setUp(() => backend = FakeBackend());

  Future<(ApiService, StorageService)> build([
    Map<String, Object> prefs = loggedIn,
  ]) async {
    final StorageService storage = await makeStorage(prefs);
    return (
      ApiService(
        storage: storage,
        client: backend.client,
        baseUrl: testBaseUrl,
      ),
      storage,
    );
  }

  group('auth header', () {
    test('authenticated requests carry the bearer token', () async {
      backend.on('GET', '/units/', unitsJson);
      final (ApiService api, _) = await build();
      await api.getUnits();
      expect(
        backend.requests.single.headers['Authorization'],
        'Bearer access-1',
      );
      expect(
        backend.requests.single.url.toString(),
        '$testBaseUrl/api/v1/units/',
      );
    });

    test('unauthenticated requests never send a token', () async {
      backend.on('POST', '/auth/login', <String, Object?>{});
      final (ApiService api, _) = await build();
      await api.post('/auth/login', <String, Object?>{
        'x': 1,
      }, authenticated: false);
      expect(
        backend.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('no header when there is no stored token', () async {
      backend.on('GET', '/units/', unitsJson);
      final (ApiService api, _) = await build(const <String, Object>{});
      await api.getUnits();
      expect(
        backend.requests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('JSON bodies are sent as UTF-8 JSON', () async {
      backend.on('POST', '/tutor/ask', tutorJson());
      final (ApiService api, _) = await build();
      await api.askTutor(
        topicId: 11,
        question: 'Sawal: i ka square kya hai?',
        language: TutorLanguage.english,
      );
      final http.Request request = backend.requests.single;
      expect(request.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(request.body), <String, Object?>{
        'question': 'Sawal: i ka square kya hai?',
        'topic_id': 11,
        'language': 'english',
      });
    });
  });

  group('token refresh on 401', () {
    test('refreshes once, saves the new tokens and retries', () async {
      int unitsCalls = 0;
      backend
        ..handle('GET', '/units/', (http.Request r) async {
          unitsCalls++;
          return r.headers['Authorization'] == 'Bearer access-2'
              ? jsonResponse(unitsJson)
              : errorResponse(401, 'not_authenticated');
        })
        ..on('POST', '/auth/refresh', <String, Object?>{
          'access_token': 'access-2',
          'refresh_token': 'refresh-2',
          'token_type': 'bearer',
          'expires_in': 3600,
        });
      final (ApiService api, StorageService storage) = await build();

      final List<Unit> units = await api.getUnits();

      expect(units, hasLength(12));
      expect(unitsCalls, 2);
      expect(
        jsonDecode(backend.calls('POST', '/auth/refresh').single.body),
        <String, Object?>{'refresh_token': 'refresh-1'},
      );
      expect(storage.accessToken, 'access-2');
      expect(storage.refreshToken, 'refresh-2');
    });

    test('failed refresh clears tokens and reports session expiry', () async {
      backend
        ..onError('GET', '/units/', 401, 'not_authenticated')
        ..onError('POST', '/auth/refresh', 401, 'not_authenticated');
      final (ApiService api, StorageService storage) = await build();
      int expired = 0;
      api.onUnauthorized = () => expired++;

      await expectLater(
        api.getUnits(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.type,
            'type',
            ApiErrorType.unauthorized,
          ),
        ),
      );
      expect(expired, 1);
      expect(storage.hasToken, isFalse);
    });

    test('without a refresh token it logs out immediately', () async {
      backend.onError('GET', '/units/', 401, 'not_authenticated');
      final (ApiService api, _) = await build(const <String, Object>{
        'access_token': 'a',
      });
      await expectLater(api.getUnits(), throwsA(isA<ApiException>()));
      expect(backend.calls('POST', '/auth/refresh'), isEmpty);
    });

    test('concurrent 401s share a single refresh call', () async {
      backend
        ..handle(
          'GET',
          '/units/',
          (http.Request r) async =>
              r.headers['Authorization'] == 'Bearer access-2'
              ? jsonResponse(unitsJson)
              : errorResponse(401, 'not_authenticated'),
        )
        ..handle('POST', '/auth/refresh', (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return jsonResponse(<String, Object?>{
            'access_token': 'access-2',
            'refresh_token': 'refresh-2',
          });
        });
      final (ApiService api, _) = await build();
      await Future.wait(<Future<List<Unit>>>[api.getUnits(), api.getUnits()]);
      expect(backend.calls('POST', '/auth/refresh'), hasLength(1));
    });

    test(
      '401 on login means wrong credentials, not an expired session',
      () async {
        backend.onError('POST', '/auth/login', 401, 'not_authenticated');
        final (ApiService api, _) = await build(const <String, Object>{});
        int expired = 0;
        api.onUnauthorized = () => expired++;
        await expectLater(
          api.post('/auth/login', <String, Object?>{}, authenticated: false),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.type,
              'type',
              ApiErrorType.invalidCredentials,
            ),
          ),
        );
        expect(expired, 0);
        expect(backend.calls('POST', '/auth/refresh'), isEmpty);
      },
    );
  });

  group('HTTP errors map to friendly types', () {
    final Map<(int, String), ApiErrorType> cases =
        <(int, String), ApiErrorType>{
          (404, 'not_found'): ApiErrorType.notFound,
          (409, 'conflict'): ApiErrorType.emailTaken,
          (422, 'validation_error'): ApiErrorType.validation,
          (429, 'ai_quota_exceeded'): ApiErrorType.aiBusy,
          (502, 'ai_bad_response'): ApiErrorType.aiUnavailable,
          (503, 'ai_unavailable'): ApiErrorType.aiUnavailable,
          (503, 'ai_model_unavailable'): ApiErrorType.aiUnavailable,
          (503, 'maintenance'): ApiErrorType.serverDown,
          (504, 'ai_timeout'): ApiErrorType.timeout,
          (500, 'internal_error'): ApiErrorType.server,
          (418, 'teapot'): ApiErrorType.unknown,
        };
    for (final MapEntry<(int, String), ApiErrorType> c in cases.entries) {
      test('${c.key.$1} ${c.key.$2} -> ${c.value.name}', () async {
        backend.onError('GET', '/units/', c.key.$1, c.key.$2);
        final (ApiService api, _) = await build();
        await expectLater(
          api.getUnits(),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.type, 'type', c.value)
                .having((ApiException e) => e.statusCode, 'status', c.key.$1)
                .having((ApiException e) => e.code, 'code', c.key.$2),
          ),
        );
      });
    }

    test('non-JSON error bodies are handled', () async {
      backend.handle(
        'GET',
        '/units/',
        (_) async => http.Response('<html>Bad Gateway</html>', 502),
      );
      final (ApiService api, _) = await build();
      await expectLater(
        api.getUnits(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.type,
            'type',
            ApiErrorType.serverDown,
          ),
        ),
      );
    });

    test('server error message is kept for validation errors', () async {
      backend.handle(
        'GET',
        '/units/',
        (_) async => errorResponse(422, 'validation_error', 'Bad id'),
      );
      final (ApiService api, _) = await build();
      try {
        await api.getUnits();
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.serverMessage, 'Bad id');
        expect(e.userMessage, contains('Bad id'));
      }
    });
  });

  group('network failures', () {
    Future<ApiErrorType> typeFor(Object error) async {
      final StorageService storage = await makeStorage(loggedIn);
      final ApiService api = ApiService(
        storage: storage,
        client: MockClient((_) async => throw error),
        baseUrl: testBaseUrl,
      );
      try {
        await api.getUnits();
      } on ApiException catch (e) {
        return e.type;
      }
      throw StateError('no exception');
    }

    test('connection refused means the server is down', () async {
      expect(
        await typeFor(http.ClientException('Connection refused')),
        ApiErrorType.serverDown,
      );
      expect(
        await typeFor(
          const SocketException(
            'x',
            osError: OSError('Connection refused', 111),
          ),
        ),
        ApiErrorType.serverDown,
      );
    });

    test('no route / DNS failure means no internet', () async {
      expect(
        await typeFor(http.ClientException('Failed host lookup')),
        ApiErrorType.noInternet,
      );
      expect(
        await typeFor(
          const SocketException(
            'x',
            osError: OSError('Network is unreachable', 101),
          ),
        ),
        ApiErrorType.noInternet,
      );
    });

    test('slow responses time out', () async {
      final StorageService storage = await makeStorage(loggedIn);
      final ApiService api = ApiService(
        storage: storage,
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return jsonResponse(unitsJson);
        }),
        baseUrl: testBaseUrl,
      );
      await expectLater(
        api.get('/units/', timeout: const Duration(milliseconds: 20)),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.type,
            'type',
            ApiErrorType.timeout,
          ),
        ),
      );
    });
  });

  group('parsing', () {
    test('responses are decoded as UTF-8 even without a charset', () async {
      backend.handle('POST', '/tutor/ask', (_) async {
        final Map<String, Object?> body = tutorJson()
          ..['explanation'] = 'Shabash! √2 · π ✓';
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      });
      final (ApiService api, _) = await build();
      final TutorResponse r = await api.askTutor(topicId: 11, question: 'q');
      expect(r.explanation, 'Shabash! √2 · π ✓');
    });

    test('unexpected shapes raise a friendly unknown error', () async {
      backend.on('GET', '/units/', <String, Object?>{'not': 'a list'});
      final (ApiService api, _) = await build();
      await expectLater(
        api.getUnits(),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.type,
            'type',
            ApiErrorType.unknown,
          ),
        ),
      );
    });

    test('empty 2xx body decodes to null', () async {
      backend.handle('GET', '/ping', (_) async => http.Response('', 204));
      final (ApiService api, _) = await build();
      expect(await api.get('/ping'), isNull);
    });
  });
}
