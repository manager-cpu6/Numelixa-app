import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_client.dart';
import '../core/config/app_config.dart';
import 'auth_service.dart';

/// Route hints are consumed by the root app shell; payloads never execute URLs.
final ValueNotifier<String?> appNotificationRoute = ValueNotifier<String?>(null);

String _routeFor(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString().toLowerCase();
  if (data['orderId'] != null || type == 'sms' || type.contains('order')) return 'orders';
  if (type.contains('wallet') || type.contains('payment') || type.contains('balance')) return 'wallet';
  if (type.contains('security') || type.contains('announcement')) return 'notifications';
  final raw = (data['url'] ?? '').toString().toLowerCase();
  if (raw.contains('order') || raw.contains('sms')) return 'orders';
  if (raw.contains('wallet') || raw.contains('payment')) return 'wallet';
  return 'notifications';
}

class NotificationService {
  NotificationService({required this.firebaseReady});
  final bool firebaseReady;
  static const _storage = FlutterSecureStorage();
  static const _permissionAskedKey = 'numelixa_notification_permission_asked';
  FirebaseMessaging? _messaging;
  FirebaseMessaging get _fcm => _messaging ??= FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final ApiClient _api = ApiClient();
  bool _initialized = false;

  Future<void> initialize({required AuthService auth}) async {
    if (!firebaseReady || _initialized) return;
    _messaging ??= FirebaseMessaging.instance;
    _initialized = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _local.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        try {
          final decoded = jsonDecode(response.payload ?? '');
          if (decoded is Map) {
            appNotificationRoute.value = _routeFor(Map<String, dynamic>.from(decoded));
          } else {
            appNotificationRoute.value = 'notifications';
          }
        } catch (_) {
          appNotificationRoute.value = 'notifications';
        }
      },
    );
    const channel = AndroidNotificationChannel(
      'general', 'Numelixa notifications',
      description: 'Account, order, and SMS updates',
      importance: Importance.high,
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      appNotificationRoute.value = _routeFor(message.data);
    });
    final initial = await _fcm.getInitialMessage();
    if (initial != null) appNotificationRoute.value = _routeFor(initial.data);
    _fcm.onTokenRefresh.listen((token) => _register(token, auth));
  }

  Future<PermissionStatus> requestPermission() async {
    var status = await Permission.notification.status;
    if (status.isGranted) return status;
    if (status.isPermanentlyDenied || status.isRestricted) return status;
    final alreadyAsked = await _storage.read(key: _permissionAskedKey) == 'true';
    if (alreadyAsked) return status;
    await _storage.write(key: _permissionAskedKey, value: 'true');
    status = await Permission.notification.request();
    if (status.isGranted) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    }
    return status;
  }

  Future<bool> openNotificationSettings() async => openAppSettings();

  Future<void> syncToken(AuthService auth) async {
    if (!firebaseReady || !auth.isSignedIn) return;
    final settings = await _fcm.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;
    final token = await _fcm.getToken();
    if (token != null && token.isNotEmpty) await _register(token, auth);
  }

  Future<void> _register(String token, AuthService auth) async {
    if (!auth.isSignedIn) return;
    try {
      final result = await _api.post(AppConfig.pushRegistrationPath,
        accessToken: auth.accessToken,
        body: {'token': token, 'platform': 'android'});
      if (result['registered'] != true || result['linked'] != true) {
        throw const ApiException('The server did not confirm device registration and user association.');
      }
    } on ApiException catch (error) {
      debugPrint('FCM registration not linked: ${error.message}');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      notification.hashCode,
      notification.title ?? 'Numelixa',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails('general', 'Numelixa notifications',
          channelDescription: 'Account, order, and SMS updates',
          importance: Importance.max, priority: Priority.high),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
