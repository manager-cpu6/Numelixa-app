import 'api_client.dart';

/// Thin, typed facade over the existing Numelixa HTTP contracts.
/// Protected methods require a real server-issued Numelixa API key as bearer token.
/// No endpoint in this class fabricates business data.
class NumelixaRepository {
  NumelixaRepository({ApiClient? client}) : _api = client ?? ApiClient();
  final ApiClient _api;

  Future<Map<String, dynamic>> me({String? token}) =>
      _api.get('/api/me', accessToken: token);

  Future<Map<String, dynamic>> balance({required String token}) =>
      _api.get('/api/v1/balance', accessToken: token);

  Future<Map<String, dynamic>> services({String? token}) =>
      _api.get('/api/catalog/services', accessToken: token);

  Future<Map<String, dynamic>> countries({
    required String service,
    String? token,
  }) =>
      _api.get('/api/catalog/countries?service=${Uri.encodeQueryComponent(service)}',
          accessToken: token);

  Future<Map<String, dynamic>> orders({
    required String token,
    int limit = 25,
    String? status,
  }) {
    final query = <String, String>{'limit': '${limit.clamp(1, 100)}'};
    if (status != null && status.isNotEmpty) query['status'] = status;
    return _api.get('/api/v1/orders?${Uri(queryParameters: query).query}',
        accessToken: token);
  }

  Future<Map<String, dynamic>> order({
    required String token,
    required String id,
  }) =>
      _api.get('/api/v1/orders/${Uri.encodeComponent(id)}', accessToken: token);

  Future<Map<String, dynamic>> purchase({
    required String token,
    required String country,
    required String service,
  }) =>
      _api.post('/api/v1/orders',
          accessToken: token,
          body: {'countryCode': country, 'service': service});

  Future<Map<String, dynamic>> checkSms({
    required String token,
    required String orderId,
  }) =>
      _api.post('/api/v1/orders/code',
          accessToken: token, body: {'orderId': orderId});

  Future<Map<String, dynamic>> cancelOrder({
    required String token,
    required String orderId,
  }) =>
      _api.delete('/api/orders',
          accessToken: token, body: {'orderId': orderId});

  Future<Map<String, dynamic>> transactions({required String token}) =>
      _api.get('/api/v1/transactions', accessToken: token);

  Future<Map<String, dynamic>> walletPricing({required String token}) =>
      _api.get('/api/me', accessToken: token);

  Future<Map<String, dynamic>> localPaymentStatus() =>
      _api.get('/api/payments/sifalo/status');

  Future<Map<String, dynamic>> createLocalPayment({required String token, required double amountUsd, required String method, required String phone}) =>
      _api.post('/api/payments/sifalo/create', accessToken: token, body: {'amountUsd': amountUsd, 'method': method, 'phone': phone});

  Future<Map<String, dynamic>> verifyLocalPayment({required String token, required String orderId}) =>
      _api.get('/api/payments/sifalo/verify?orderId=${Uri.encodeQueryComponent(orderId)}', accessToken: token);

  Future<Map<String, dynamic>> depositAssets({required String token}) =>
      _api.get('/api/payments/binance/networks', accessToken: token);

  Future<Map<String, dynamic>> createDeposit({
    required String token,
    required double amountUsd,
    required String currency,
    required String network,
  }) => _api.post('/api/payments/binance/create', accessToken: token,
      body: {'amountUsd': amountUsd, 'currency': currency, 'network': network});

  Future<Map<String, dynamic>> depositStatus({
    required String token,
    required String orderId,
  }) => _api.get('/api/payments/binance/status?orderId=${Uri.encodeQueryComponent(orderId)}',
      accessToken: token);

  Future<Map<String, dynamic>> notifications({required String token}) =>
      _api.get('/api/notifications', accessToken: token);

  Future<Map<String, dynamic>> markNotificationRead({
    required String token,
    String? id,
  }) =>
      _api.post('/api/notifications',
          accessToken: token, body: {if (id != null) 'id': id});

  Future<Map<String, dynamic>> forgotPassword({required String email}) =>
      _api.post('/api/auth/forgot', body: {'email': email});

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) =>
      _api.post('/api/auth/signup',
          body: {'name': name, 'email': email, 'password': password});

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) =>
      _api.post('/api/auth/login',
          body: {'email': email, 'password': password});
}
