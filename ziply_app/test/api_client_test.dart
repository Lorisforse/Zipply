import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ziply_app/services/api_client.dart';
import 'package:ziply_app/services/api_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock di flutter_secure_storage: nessun token salvato (read → null).
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  test('decodifica un corpo JSON oggetto sulle risposte 2xx', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{"hello":"world"}', 200)),
    );
    final res = await api.get('/x', authenticated: false);
    expect(res.statusCode, 200);
    expect(res.isSuccess, isTrue);
    expect(res.map?['hello'], 'world');
  });

  test('espone le liste JSON', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('[1,2,3]', 200)),
    );
    final res = await api.get('/x', authenticated: false);
    expect(res.list, [1, 2, 3]);
    expect(res.map, isNull);
  });

  test('estrae il messaggio di errore del backend', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{"error":"boom"}', 409)),
    );
    final res = await api.post('/x', authenticated: false);
    expect(res.statusCode, 409);
    expect(res.errorMessage, 'boom');
  });

  test('401 su chiamata autenticata → SessionExpiredException', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('', 401)),
    );
    await expectLater(
      api.get('/x'),
      throwsA(isA<SessionExpiredException>()),
    );
  });

  test('401 su chiamata pubblica → ritorna la risposta senza eccezione', () async {
    final api = ApiClient(
      client: MockClient((_) async => http.Response('{"error":"bad creds"}', 401)),
    );
    final res = await api.post('/auth/login', authenticated: false);
    expect(res.statusCode, 401);
    expect(res.errorMessage, 'bad creds');
  });

  test('errore di rete → Exception tradotta', () async {
    final api = ApiClient(
      client: MockClient((_) async => throw http.ClientException('down')),
    );
    await expectLater(
      api.get('/x', authenticated: false),
      throwsA(isA<Exception>()),
    );
  });

  test('aggiunge Content-Type e serializza il body', () async {
    late http.Request captured;
    final api = ApiClient(
      client: MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      }),
    );
    await api.post('/x', body: {'a': 1}, authenticated: false);
    expect(captured.headers['Content-Type'], contains('application/json'));
    expect(captured.body, '{"a":1}');
  });
}
