import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'numelixa_mobile_access_token';
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
  bool get needsEmailVerification => isSignedIn && _user != null && _user!.containsKey('verified_at') && _user!['verified_at'] == null;

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

  Future<Map<String, dynamic>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _validating = true;
    notifyListeners();
    try {
      final response = await _api.post('/api/auth/login', body: {
        'email': email.trim().toLowerCase(),
        'password': password,
      });
      final token = (response['accessToken'] ?? '').toString();
      if (token.isEmpty) {
        throw const ApiException('The server did not issue a mobile session. Please try again.');
      }
      await _saveSession(token, response['user']);
      return response;
    } finally {
      _validating = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) async {
    _validating = true;
    notifyListeners();
    try {
      final response = await _api.post('/api/auth/signup', body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      });
      final token = (response['accessToken'] ?? '').toString();
      if (token.isEmpty) {
        throw const ApiException('The server did not issue a mobile session. Please try again.');
      }
      await _saveSession(token, response['user']);
      return response;
    } finally {
      _validating = false;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _validating = true;
    notifyListeners();
    try {
      final config = await _api.get('/api/auth/google/config');
      final clientId = (config['clientId'] ?? '').toString().trim();
      if (clientId.isEmpty) {
        throw const ApiException('Google Sign-In is not configured for Numelixa yet.');
      }
      final google = GoogleSignIn(serverClientId: clientId, scopes: const ['email', 'profile']);
      final account = await google.signIn();
      if (account == null) throw const ApiException('Google sign-in was cancelled.');
      final authentication = await account.authentication;
      final idToken = authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        await google.signOut();
        throw const ApiException('Google did not return a sign-in token. Check the Android OAuth configuration.');
      }
      final credential = await _api.post('/api/auth/google/native/credential', body: {'credential': idToken});
      final ticket = (credential['ticket'] ?? '').toString();
      if (ticket.isEmpty) throw const ApiException('Google sign-in could not be completed.');
      final complete = await _api.post('/api/auth/google/native/complete', body: {'ticket': ticket});
      final token = (complete['accessToken'] ?? '').toString();
      if (token.isEmpty) throw const ApiException('The server did not issue a mobile session.');
      await _saveSession(token, complete['user']);
    } finally {
      _validating = false;
      notifyListeners();
    }
  }

  Future<bool> verifyEmailCode(String code) async {
    final result = await _api.post('/api/auth/verification/confirm',
        accessToken: _accessToken, body: {'code': code.trim()});
    if (result['verified'] != true) return false;
    final current = await _api.get('/api/me', accessToken: _accessToken);
    final user = current['user'];
    if (user is Map<String, dynamic>) _user = user;
    notifyListeners();
    return true;
  }

  Future<void> resendVerificationCode() async {
    await _api.post('/api/auth/verification/start',
        accessToken: _accessToken, body: {'resend': true});
  }

  Future<void> _saveSession(String token, dynamic user) async {
    await _storage.write(key: _accessKey, value: token);
    _accessToken = token;
    if (user is Map<String, dynamic>) {
      _user = Map<String, dynamic>.from(user);
    } else {
      final response = await _api.get('/api/me', accessToken: token);
      if (response['user'] is Map<String, dynamic>) {
        _user = Map<String, dynamic>.from(response['user']);
      }
    }
    _ready = true;
  }

  /// Legacy API-key sign-in remains available for existing developer accounts.
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
      await _saveSession(candidate, user);
    } finally {
      _validating = false;
      notifyListeners();
    }
  }

  Future<void> _clearTokens() async {
    await _storage.delete(key: _accessKey);
    _accessToken = null;
    _user = null;
  }

  Future<void> logout() async {
    try {
      if (isSignedIn) await _api.post('/api/auth/logout', accessToken: _accessToken);
    } catch (_) {}
    await _clearTokens();
    notifyListeners();
  }
}
