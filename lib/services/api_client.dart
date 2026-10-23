import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/config/app_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl}) : _client = client ?? http.Client(), _baseUrl = baseUrl;
  final http.Client _client;
  final String? _baseUrl;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static final Future<String> _deviceId = _loadDeviceId();
  static Future<String> get deviceId => _deviceId;

  static Future<String> _loadDeviceId() async {
    try {
      final stored = await _secureStorage.read(key: 'numelixa_device_id');
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (_) {
      // Unit tests and restricted platform contexts may not have a method-channel binding.
    }
    final random = Random.secure();
    final suffix = List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
    final id = '${DateTime.now().microsecondsSinceEpoch}-$suffix';
    try {
      await _secureStorage.write(key: 'numelixa_device_id', value: id);
    } catch (_) {}
    return id;
  }

  static final Future<String> _deviceLabel = DeviceInfoPlugin().androidInfo.then((info) {
    final maker = info.manufacturer.trim();
    final model = info.model.trim();
    final product = info.device.toLowerCase();
    if (maker.toLowerCase() == 'samsung') {
      const galaxyModels = <String, String>{
        'a15': 'Samsung Galaxy A15', 'a16': 'Samsung Galaxy A16',
        'a14': 'Samsung Galaxy A14', 'a05': 'Samsung Galaxy A05',
        'a06': 'Samsung Galaxy A06', 'a25': 'Samsung Galaxy A25',
        'a35': 'Samsung Galaxy A35', 'a55': 'Samsung Galaxy A55',
        's24': 'Samsung Galaxy S24', 's25': 'Samsung Galaxy S25',
      };
      for (final entry in galaxyModels.entries) {
        if (product.contains(entry.key) || model.toLowerCase().contains(entry.key)) return entry.value;
      }
    }
    return [maker, model].where((part) => part.isNotEmpty).join(' ');
  }).catchError((_) => 'Android device');

  Future<Map<String, dynamic>> get(String path, {String? accessToken}) =>
      _request('GET', path, accessToken: accessToken);

  Future<Map<String, dynamic>> post(String path,
          {Map<String, dynamic>? body, String? accessToken}) =>
      _request('POST', path, body: body, accessToken: accessToken);

  Future<Map<String, dynamic>> put(String path,
          {Map<String, dynamic>? body, String? accessToken}) =>
      _request('PUT', path, body: body, accessToken: accessToken);

  Future<Map<String, dynamic>> delete(String path,
          {Map<String, dynamic>? body, String? accessToken}) =>
      _request('DELETE', path, body: body, accessToken: accessToken);

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, dynamic>? body, String? accessToken}) async {
    final uri = Uri.parse(_baseUrl ?? AppConfig.apiBase).resolve(path);
    final deviceLabel = await _deviceLabel;
    final deviceId = await _deviceId;
    final headers = <String, String>{
      'Accept': 'application/json',
      'x-numelixa-client': 'android-app',
      'x-numelixa-device': deviceLabel.isEmpty ? 'Android device' : deviceLabel,
      'x-numelixa-device-id': deviceId,
      'x-numelixa-platform': 'Android',
    };
    if (body != null) headers['Content-Type'] = 'application/json';
    if (accessToken != null && accessToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $accessToken';
    }
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'DELETE' => _client.delete(uri, headers: headers, body: body == null ? null : jsonEncode(body)),
        'PUT' => _client.put(uri, headers: headers, body: jsonEncode(body ?? {})),
        _ => _client.post(uri, headers: headers, body: jsonEncode(body ?? {})),
      };
      final response = await request.timeout(const Duration(seconds: 20));
      final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(_friendlyMessage(response.statusCode, decoded),
            statusCode: response.statusCode);
      }
      if (decoded is Map<String, dynamic>) return decoded;
      throw const ApiException('The server returned an unexpected response.');
    } on TimeoutException {
      throw const ApiException('The request took too long. Please try again.');
    } on FormatException {
      throw const ApiException('The server response could not be read.');
    } on http.ClientException {
      throw const ApiException('Could not connect. Check your internet connection.');
    }
  }

  String _friendlyMessage(int status, dynamic body) {
    // Prefer the server's actionable error over a generic HTTP label. This is
    // especially important for diagnosing FCM token linking and OAuth tickets.
    if (body is Map && body['message'] is String && (body['message'] as String).trim().isNotEmpty) {
      return body['message'] as String;
    }
    if (body is Map && body['error'] is String && (body['error'] as String).trim().isNotEmpty) {
      return body['error'] as String;
    }
    if (status == 401) return 'Please sign in again.';
    if (status == 403) return 'You do not have permission to do that.';
    if (status >= 500) return 'The service is temporarily unavailable.';
    return 'The request could not be completed (HTTP $status).';
  }
}
