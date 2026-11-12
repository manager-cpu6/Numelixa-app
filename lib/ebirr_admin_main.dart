import 'package:flutter/material.dart';
import 'screens/ebirr_admin_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EbirrAdminApp());
}

class EbirrAdminApp extends StatelessWidget {
  const EbirrAdminApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Ebirr-Numelixa Admin',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xff07111f),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff45ddb4),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const EbirrAdminGate(),
      );
}
