import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'screens/app_shell.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
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
