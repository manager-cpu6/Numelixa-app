import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:numelixa_app/services/api_client.dart';

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest request) handler;
  http.BaseRequest? lastRequest;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
      headers: response.headers,
    );
  }
}

void main() {
  test('GET sends bearer authorization and decodes JSON', () async {
    late _FakeClient client;
    client = _FakeClient((_) async => http.Response(
      jsonEncode({'ok': true, 'balance': 12}),
      200,
      headers: {'content-type': 'application/json'},
    ));
    final api = ApiClient(client: client);
    final result = await api.get('/api/v1/balance', accessToken: 'nx_live_test');
    expect(result['balance'], 12);
    expect(client.lastRequest?.headers['Authorization'], 'Bearer nx_live_test');
    expect(client.lastRequest?.url.path, '/api/v1/balance');
  });

  test('HTTP 401 becomes a clear authentication error', () async {
    final client = _FakeClient((_) async => http.Response(
      jsonEncode({'ok': false, 'error': 'Unauthorized'}),
      401,
      headers: {'content-type': 'application/json'},
    ));
    final api = ApiClient(client: client);
    expect(
      () => api.get('/api/me'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('POST sends JSON body', () async {
    final client = _FakeClient((_) async => http.Response(
      jsonEncode({'ok': true}),
      200,
      headers: {'content-type': 'application/json'},
    ));
    final api = ApiClient(client: client);
    await api.post('/api/auth/forgot', body: {'email': 'user@example.com'});
    expect(client.lastRequest?.headers['Content-Type'], 'application/json');
    expect(client.lastRequest, isA<http.Request>());
    expect((client.lastRequest as http.Request).body, contains('user@example.com'));
  });
}
