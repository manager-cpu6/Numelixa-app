import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'api_client.dart';
import '../core/config/app_config.dart';
import 'auth_service.dart';

/// Route hints are consumed by the root app shell; payloads never execute URLs.
final ValueNotifier<String?> appNotificationRoute = ValueNotifier<String?>(null);

String _channelFor(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString().toLowerCase();
  if (type == 'sms' || type == 'verification' || type == 'verification_code') return 'verification';
  if (type == 'security' || type == 'login' || type == 'login_approval') return 'security';
  if (type == 'admin' || type == 'announcement' || type == 'push_test') return 'admin';
  return 'general';
}

String _channelNameFor(String channel) => switch (channel) {
  'verification' => 'SMS and verification codes',
  'security' => 'Account security',
  'admin' => 'Numelixa announcements',
  _ => 'Numelixa notifications',
};

String _channelDescriptionFor(String channel) => switch (channel) {
  'verification' => 'Incoming SMS codes and verification updates',
  'security' => 'Login and account security alerts',
  'admin' => 'Important announcements and push tests',
  _ => 'Account, order, and SMS updates',
};

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
  FirebaseMessaging? _messaging;
  FirebaseMessaging get _fcm => _messaging ??= FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final ApiClient _api = ApiClient();
  bool _initialized = false;
  final ValueNotifier<String> registrationStatus = ValueNotifier<String>('Notifications are not registered yet.');

  Future<void> initialize({required AuthService auth}) async {
    if (!firebaseReady) {
      registrationStatus.value = 'Firebase is not configured in this app build.';
      return;
    }
    if (_initialized) return;
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
    final androidNotifications = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    const channels = <AndroidNotificationChannel>[
      AndroidNotificationChannel('general', 'Numelixa notifications',
        description: 'Account, order, and SMS updates', importance: Importance.high),
      AndroidNotificationChannel('verification', 'SMS and verification codes',
        description: 'Incoming SMS codes and verification updates', importance: Importance.high),
      AndroidNotificationChannel('security', 'Account security',
        description: 'Login and account security alerts', importance: Importance.high),
      AndroidNotificationChannel('admin', 'Numelixa announcements',
        description: 'Important announcements and push tests', importance: Importance.high),
    ];
    for (final channel in channels) {
      await androidNotifications?.createNotificationChannel(channel);
    }
    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      appNotificationRoute.value = _routeFor(message.data);
    });
    final initial = await _fcm.getInitialMessage();
    if (initial != null) appNotificationRoute.value = _routeFor(initial.data);
    _fcm.onTokenRefresh.listen((token) => _register(token, auth));
  }

  Future<PermissionStatus> requestPermission() async {
    if (!firebaseReady) {
      registrationStatus.value = 'Firebase is not configured in this app build.';
      return Permission.notification.status;
    }
    var status = await Permission.notification.status;
    if (status.isGranted) {
      registrationStatus.value = 'Notification permission is enabled; checking device registration.';
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
      return status;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      registrationStatus.value = 'Notifications are blocked. Open Android settings and allow Numelixa notifications.';
      return status;
    }
    // Ask after account sign-in, not on the anonymous splash screen. Do not
    // persist a local "already asked" bit: it prevented retry after a denial.
    status = await Permission.notification.request();
    if (status.isGranted) {
      registrationStatus.value = 'Notification permission is enabled; linking this device.';
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    } else {
      registrationStatus.value = 'Notifications are disabled. Enable them to receive SMS codes and order updates.';
    }
    return status;
  }

  Future<bool> openNotificationSettings() async => openAppSettings();

  Future<void> syncToken(AuthService auth) async {
    if (!firebaseReady) {
      registrationStatus.value = 'Firebase is not configured in this app build.';
      return;
    }
    if (!auth.isSignedIn) {
      registrationStatus.value = 'Sign in to link notifications to your account.';
      return;
    }
    try {
      final settings = await _fcm.getNotificationSettings();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        registrationStatus.value = 'Notifications are blocked. Enable them in Android settings.';
        return;
      }
      final token = await _fcm.getToken();
      if (token == null || token.isEmpty) {
        registrationStatus.value = 'Firebase did not provide a device token. Retry after checking your connection.';
        return;
      }
      await _register(token, auth);
    } catch (error) {
      registrationStatus.value = 'FCM registration error: ' + error.toString();
      debugPrint('FCM token sync failed: $error');
    }
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
      registrationStatus.value = 'This device is linked to your Numelixa account.';
    } on ApiException catch (error) {
      registrationStatus.value = 'Device registration failed: ${error.message}';
      debugPrint('FCM registration not linked: ${error.message}');
    }
  }

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final channelId = _channelFor(message.data);
    await _local.show(
      notification.hashCode,
      notification.title ?? 'Numelixa',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(channelId, _channelNameFor(channelId),
          channelDescription: _channelDescriptionFor(channelId),
          importance: Importance.max, priority: Priority.high, playSound: true),
      ),
      payload: jsonEncode(message.data),
    );
  }
}
