import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/app_shell.dart';
import 'screens/ebirr_admin_screen.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  const android = AndroidInitializationSettings('@drawable/ic_stat_numelixa');
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(const InitializationSettings(android: android));
  const channel = AndroidNotificationChannel(
    'verification', 'SMS and verification codes',
    description: 'Incoming SMS codes and verification updates',
    importance: Importance.max,
  );
  await local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  final data = Map<String, dynamic>.from(message.data);
  final title = (data['title'] ?? 'Numelixa').toString();
  final body = (data['body'] ?? data['message'] ?? '').toString();
  final rawCode = (data['code'] ?? data['otp'] ?? data['verificationCode'] ?? data['smsCode'] ?? '').toString();
  final code = RegExp(r'^\d{4,8}$').hasMatch(rawCode)
      ? rawCode
      : RegExp(r'(?<!\d)\d{4,8}(?!\d)').firstMatch(body)?.group(0);
  await local.show(
    message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(android: AndroidNotificationDetails(
      'verification', 'SMS and verification codes',
      channelDescription: 'Incoming SMS codes and verification updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      icon: '@drawable/ic_stat_numelixa',
      actions: code == null ? null : const [
        AndroidNotificationAction('copy_code', 'Copy code', showsUserInterface: false),
      ],
    )),
    payload: jsonEncode({...data, 'body': body}),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    firebaseReady = true;
  } catch (_) {
    // Keep the app usable for UI/API development when Firebase config is not installed.
  }
  runApp(NumelixaApp(firebaseReady: firebaseReady));
}

class NumelixaApp extends StatelessWidget {
  const NumelixaApp({super.key, required this.firebaseReady});
  final bool firebaseReady;

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthService()),
          Provider(create: (_) => NotificationService(firebaseReady: firebaseReady)),
        ],
        child: MaterialApp(
          title: 'Numelixa',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark,
          home: const EbirrAdminGate(),
        ),
      );
}
