import 'package:flutter/material.dart';
import 'screens/ebirr_admin_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NumelixaPaymentAdminApp());
}

// Dedicated entry point: this APK is the payment-admin app, not the customer app.\nclass NumelixaPaymentAdminApp extends StatelessWidget {
  const NumelixaPaymentAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ebirr-Numelixa Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff45ddb4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const EbirrAdminGate(),
    );
  }
}
