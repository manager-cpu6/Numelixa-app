import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores mobile API tokens securely. No browser-cookie or WebView session is used.
class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'numelixa_mobile_access_token';
  static const _refreshKey = 'numelixa_mobile_refresh_token';
  String? _accessToken;
  bool _ready = false;
  bool get isReady => _ready;
  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;
  String? get accessToken => _accessToken;

  Future<void> restore() async {
    _accessToken = await _storage.read(key: _accessKey);
    _ready = true;
    notifyListeners();
  }

  /// Use only after the backend implements a verified mobile-token exchange.
  Future<void> saveMobileTokens({required String accessToken, String? refreshToken}) async {
    if (accessToken.trim().isEmpty) throw ArgumentError('Access token cannot be empty');
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

  Future<void> logout() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    _accessToken = null;
    notifyListeners();
  }
}
