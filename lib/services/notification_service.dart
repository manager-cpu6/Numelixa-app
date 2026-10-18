import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_client.dart';
import '../core/config/app_config.dart';
import 'auth_service.dart';

class NotificationService {
  NotificationService({required this.firebaseReady});
  final bool firebaseReady;
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
    await _local.initialize(const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        // Route notification payload through app navigation in a later screen-level handler.
        debugPrint('Notification tapped: ${response.payload ?? ''}');
      });
    const channel = AndroidNotificationChannel(
      'general', 'Numelixa notifications',
      description: 'Account, order, and SMS updates',
      importance: Importance.high,
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint('Push opened: ${jsonEncode(message.data)}');
    });
    final initial = await _fcm.getInitialMessage();
    if (initial != null) debugPrint('Cold-start push: ${jsonEncode(initial.data)}');
    _fcm.onTokenRefresh.listen((token) => _register(token, auth));
  }

  Future<PermissionStatus> requestPermission() async {
    if (!firebaseReady) return PermissionStatus.denied;
    final status = await Permission.notification.request();
    if (status.isGranted) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    }
    return status;
  }

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
      if (result['registered'] != true) {
        throw const ApiException('The server did not confirm device registration.');
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
