import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

class AuthService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'numelixa_mobile_access_token';
  final ApiClient _api = ApiClient();
  String? _accessToken;
  bool _ready = false;
  bool _validating = false;
  bool _biometricEnabled = false;
  bool _biometricLocked = false;
  Map<String, dynamic>? _user;

  bool get isReady => _ready;
  bool get isSignedIn => _accessToken != null && _accessToken!.isNotEmpty;
  bool get isValidating => _validating;
  bool get biometricEnabled => _biometricEnabled;
  bool get biometricLocked => _biometricLocked;
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
    _biometricEnabled = (await _storage.read(key: 'numelixa_biometric_lock')) == 'true';
    _biometricLocked = _biometricEnabled && isSignedIn;
    _ready = true;
    notifyListeners();
  }

  Future<bool> enableBiometricLock() async {
    final auth = LocalAuthentication();
    final supported = await auth.isDeviceSupported();
    final canCheck = await auth.canCheckBiometrics;
    if (!supported || !canCheck) {
      throw const ApiException('This device does not have an available fingerprint or face unlock method.');
    }
    final success = await auth.authenticate(
      localizedReason: 'Confirm your identity to protect your Numelixa account',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
    if (!success) return false;
    await _storage.write(key: 'numelixa_biometric_lock', value: 'true');
    _biometricEnabled = true;
    _biometricLocked = false;
    notifyListeners();
    return true;
  }

  Future<void> disableBiometricLock() async {
    await _storage.delete(key: 'numelixa_biometric_lock');
    _biometricEnabled = false;
    _biometricLocked = false;
    notifyListeners();
  }

  Future<bool> unlockBiometrics() async {
    if (!_biometricEnabled || !isSignedIn) {
      _biometricLocked = false;
      notifyListeners();
      return true;
    }
    final success = await LocalAuthentication().authenticate(
      localizedReason: 'Unlock Numelixa',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
    if (success) {
      _biometricLocked = false;
      notifyListeners();
    }
    return success;
  }

  void lockBiometrics() {
    if (_biometricEnabled && isSignedIn && !_biometricLocked) {
      _biometricLocked = true;
      notifyListeners();
    }
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
    StreamSubscription<Uri>? callbackSubscription;
    try {
      // Use the website's verified Google Identity Services flow. This avoids
      // depending on a missing Android OAuth client/SHA-1 in Firebase config.
      final config = await _api.get('/api/auth/google/config');
      if ((config['clientId'] ?? '').toString().trim().isEmpty) {
        throw const ApiException('Google Sign-In is not configured for Numelixa yet.');
      }

      final callback = Completer<Uri>();
      final links = AppLinks();
      callbackSubscription = links.uriLinkStream.listen((uri) {
        if (uri.scheme == 'com.numelixa.app' &&
            uri.host == 'auth' &&
            uri.path == '/callback' &&
            uri.queryParameters['ticket']?.isNotEmpty == true &&
            !callback.isCompleted) {
          callback.complete(uri);
        }
      });

      final launched = await launchUrl(
        Uri.parse('https://www.numelixa.com/auth/native/google'),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        throw const ApiException('Could not open the secure Google sign-in page. Check your browser and internet connection.');
      }

      final uri = await callback.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw const ApiException('Google sign-in timed out. Return to Numelixa and try again.'),
      );
      final ticket = (uri.queryParameters['ticket'] ?? '').trim();
      if (ticket.isEmpty) {
        throw const ApiException('Google returned to Numelixa without a sign-in ticket. Please try again.');
      }
      final complete = await _api.post('/api/auth/google/native/complete', body: {'ticket': ticket});
      final token = (complete['accessToken'] ?? '').toString();
      if (token.isEmpty) {
        throw const ApiException('The server did not issue a mobile session. Please try again.');
      }
      await _saveSession(token, complete['user']);
    } finally {
      await callbackSubscription?.cancel();
      _validating = false;
      notifyListeners();
    }
  }

  void updateUserFields(Map<String, dynamic> fields) {
    _user = {...(_user ?? const <String, dynamic>{}), ...fields};
    notifyListeners();
  }

  Future<void> uploadProfilePhoto(String dataUrl) async {
    final result = await _api.put('/api/mobile/profile/avatar',
        accessToken: _accessToken, body: {'avatar': dataUrl});
    final avatar = (result['avatarUrl'] ?? dataUrl).toString();
    updateUserFields({'avatarDataUrl': avatar, 'avatarUrl': avatar});
  }

  Future<Map<String, dynamic>> listDevices() =>
      _api.get('/api/mobile/devices', accessToken: _accessToken);

  Future<void> removeDevice(String deviceId) async {
    await _api.delete('/api/mobile/devices',
        accessToken: _accessToken, body: {'deviceId': deviceId});
  }

  Future<void> requestPasswordChangeCode() async {
    await _api.post('/api/mobile/security/password/start', accessToken: _accessToken);
  }

  Future<void> confirmPasswordChange({
    required String code,
    required String newPassword,
  }) async {
    await _api.post('/api/mobile/security/password/confirm',
        accessToken: _accessToken,
        body: {'code': code.trim(), 'newPassword': newPassword});
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
