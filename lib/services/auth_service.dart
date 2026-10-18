import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

/// Mobile bearer authentication. The existing backend accepts server-issued
/// nx_live_* API keys as Bearer credentials; email/password web login currently
/// only sets an HttpOnly cookie and does not issue a mobile access/refresh token.
class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'numelixa_mobile_access_token';
  static const _refreshKey = 'numelixa_mobile_refresh_token';
  final ApiClient _api = ApiClient();
  String? _accessToken;
  bool _ready = false;
  bool _validating = false;
  Map<String, dynamic>? _user;

  bool get isReady => _ready;
  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;
  bool get isValidating => _validating;
  String? get accessToken => _accessToken;
  Map<String, dynamic>? get user => _user;

  Future<void> restore() async {
    if (_ready) return;
    _accessToken = await _storage.read(key: _accessKey);
    if (_accessToken != null && _accessToken!.isNotEmpty) {
      try {
        final response = await _api.get('/api/me', accessToken: _accessToken);
        final user = response['user'];
        if (user is Map<String, dynamic>) {
          _user = user;
        } else {
          await _clearTokens();
        }
      } on ApiException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          await _clearTokens();
        }
      }
    }
    _ready = true;
    notifyListeners();
  }

  /// Authenticate using an existing user-owned API key. The key is verified
  /// against the live backend before being stored in Android secure storage.
  Future<void> signInWithApiKey(String key) async {
    final candidate = key.trim();
    if (!candidate.startsWith('nx_live_')) {
      throw const ApiException('Enter a valid Numelixa API key.');
    }
    _validating = true;
    notifyListeners();
    try {
      final response = await _api.get('/api/me', accessToken: candidate);
      final user = response['user'];
      if (user is! Map<String, dynamic> || user['id'] == null) {
        throw const ApiException('The server did not return an authenticated account.');
      }
      await _storage.write(key: _accessKey, value: candidate);
      await _storage.delete(key: _refreshKey);
      _accessToken = candidate;
      _user = user;
      _ready = true;
    } finally {
      _validating = false;
      notifyListeners();
    }
  }

  /// Token exchange can be wired here when the backend issues native tokens.
  Future<void> saveMobileTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    if (accessToken.trim().isEmpty) {
      throw ArgumentError('Access token cannot be empty');
    }
    await _storage.write(key: _accessKey, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _refreshKey, value: refreshToken);
    } else {
      await _storage.delete(key: _refreshKey);
    }
    _accessToken = accessToken;
    _ready = true;
    notifyListeners();
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    _accessToken = null;
    _user = null;
  }

  Future<void> logout() async {
    await _clearTokens();
    notifyListeners();
  }
}
