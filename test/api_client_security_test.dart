import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:numelixa_app/services/api_client.dart';

void main() {
  test('API client refuses cleartext HTTP before making a request', () async {
    final client = ApiClient(
      baseUrl: 'http://www.numelixa.com',
      client: MockClient((_) async => throw StateError('Network must not be called')),
    );

    await expectLater(
      client.get('/api/me', accessToken: 'test-session'),
      throwsA(isA<ApiException>()),
    );
  });

  test('API client does not follow redirects with authorization attached', () async {
    var called = false;
    final client = ApiClient(
      baseUrl: 'https://www.numelixa.com',
      client: MockClient((request) async {
        called = true;
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(request.headers['Authorization'], 'Bearer test-session');
        return http.Response(
          '',
          302,
          headers: {'location': 'https://untrusted.example/collect'},
        );
      }),
    );

    await expectLater(
      client.get('/api/me', accessToken: 'test-session'),
      throwsA(
        isA<ApiException>().having((error) => error.statusCode, 'statusCode', 302),
      ),
    );
    expect(called, isTrue);
  });
}
