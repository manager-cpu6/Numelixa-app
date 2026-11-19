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

const _backgroundNotificationIconNames = <String, String>{
  'admin': 'ic_notification_admin', 'number': 'ic_notification_number',
  'otp': 'ic_notification_otp', 'auto': 'ic_notification_auto',
  'payment': 'ic_notification_payment', 'gift': 'ic_notification_gift',
  'general': 'ic_notification_general', 'user': 'ic_notification_user',
  'system': 'ic_notification_system', 'numelixa': 'ic_notification_numelixa',
  'announcement': 'ic_notification_announcement', 'success': 'ic_notification_success',
};
String notificationIconFor(Map<String, dynamic> data) {
  final requested = (data['iconType'] ?? data['notificationCategory'] ?? data['notificationIcon'] ?? '').toString().toLowerCase().trim();
  if (_backgroundNotificationIconNames.containsKey(requested)) return '@drawable/${_backgroundNotificationIconNames[requested]}';
  final type = (data['type'] ?? '').toString().toLowerCase();
  if (type.contains('otp') || type.contains('verification') || type == 'sms' || type.contains('code')) return '@drawable/ic_notification_otp';
  if (type.contains('admin') || type == 'push_test') return '@drawable/ic_notification_admin';
  if (type.contains('announcement') || type.contains('news')) return '@drawable/ic_notification_announcement';
  if (type.contains('auto') || type.contains('automation') || type.contains('background')) return '@drawable/ic_notification_auto';
  if (type.contains('payment') || type.contains('wallet') || type.contains('deposit') || type.contains('balance') || type.contains('purchase')) return '@drawable/ic_notification_payment';
  if (type.contains('gift') || type.contains('reward') || type.contains('bonus') || type.contains('promo')) return '@drawable/ic_notification_gift';
  if (type.contains('number') || type.contains('order') || type.contains('activation')) return '@drawable/ic_notification_number';
  if (type.contains('user') || type.contains('account') || type.contains('profile')) return '@drawable/ic_notification_user';
  if (type.contains('system') || type.contains('maintenance') || type.contains('service')) return '@drawable/ic_notification_system';
  if (type.contains('success') || type.contains('completed')) return '@drawable/ic_notification_success';
  if (type.contains('numelixa') || type.contains('brand')) return '@drawable/ic_notification_numelixa';
  return '@drawable/ic_notification_general';
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Data-only FCM lets this background isolate apply the selected icon category.
  const android = AndroidInitializationSettings('@drawable/ic_stat_numelixa');
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(const InitializationSettings(android: android));
  final data = Map<String, dynamic>.from(message.data);
  final type = (data['type'] ?? '').toString().toLowerCase();
  final channelId = type == 'sms' || type == 'verification' || type == 'verification_code'
      ? 'verification'
      : type.contains('security') || type.contains('login')
          ? 'security'
          : type == 'admin' || type == 'announcement' || type == 'push_test'
              ? 'admin'
              : 'general';
  const channels = <AndroidNotificationChannel>[
    AndroidNotificationChannel('general', 'Numelixa notifications', description: 'Account, wallet and payment updates', importance: Importance.max),
    AndroidNotificationChannel('verification', 'SMS and verification codes', description: 'Incoming SMS codes and verification updates', importance: Importance.max),
    AndroidNotificationChannel('security', 'Account security', description: 'Login and account security alerts', importance: Importance.max),
    AndroidNotificationChannel('admin', 'Numelixa announcements', description: 'Important Numelixa announcements', importance: Importance.max),
  ];
  final androidNotifications = local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  for (final channel in channels) { await androidNotifications?.createNotificationChannel(channel); }
  final rawTitle = (data['title'] ?? '').toString().trim();
  final title = rawTitle.isEmpty ? 'Numelixa' : rawTitle;
  final rawBody = (data['body'] ?? data['message'] ?? '').toString();
  final body = rawBody.trim().isEmpty ? 'You have a new update from Numelixa.' : rawBody;
  final rawCode = (data['code'] ?? data['otp'] ?? data['verificationCode'] ?? data['smsCode'] ?? '').toString();
  final code = RegExp(r'^\d{4,8}$').hasMatch(rawCode)
      ? rawCode
      : RegExp(r'(?<!\d)\d{4,8}(?!\d)').firstMatch(body)?.group(0);
  await local.show(
    message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(android: AndroidNotificationDetails(
      channelId,
      channelId == 'verification' ? 'SMS and verification codes' : channelId == 'security' ? 'Account security' : channelId == 'admin' ? 'Numelixa announcements' : 'Numelixa notifications',
      channelDescription: channelId == 'verification' ? 'Incoming SMS codes and verification updates' : 'Account, wallet and payment updates',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      playSound: true,
      icon: notificationIconFor(data),
      largeIcon: DrawableResourceAndroidBitmap(notificationIconFor(data).replaceFirst('@drawable/', '') + '_color'),
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
          home: const AppShell(),
        ),
      );
}
