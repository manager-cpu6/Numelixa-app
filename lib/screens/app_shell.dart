import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/numelixa_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';
import '../widgets/payment_receipt_dialog.dart';
import 'help_team_screen.dart';
import 'support_admin_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  bool _booted = false;
  bool _wasBackgrounded = false;
  bool _biometricUnlockInProgress = false;
  bool _updateCheckStarted = false;
  Map<String, dynamic>? _accessBlock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    appNotificationRoute.addListener(_handleNotificationRoute);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android may emit inactive/resumed around system dialogs (including the
    // biometric prompt itself). Only a real background pause should trigger
    // a fresh app lock, otherwise the prompt can loop repeatedly.
    if (state == AppLifecycleState.paused) {
      _wasBackgrounded = true;
      return;
    }
    if (state != AppLifecycleState.resumed || !mounted) return;
    final auth = context.read<AuthService>();
    final didBackground = _wasBackgrounded;
    _wasBackgrounded = false;
    if (didBackground && auth.biometricEnabled && auth.isSignedIn &&
        !auth.biometricLocked && !_biometricUnlockInProgress) {
      _biometricUnlockInProgress = true;
      auth.lockBiometrics();
      auth.unlockBiometrics().then((_) {
        if (mounted && !auth.biometricLocked) _syncNotifications();
      }).catchError((_) {}).whenComplete(() {
        _biometricUnlockInProgress = false;
      });
      return;
    }
    _syncNotifications();
    // Re-check after the user returns to Numelixa. This makes a deferred
    // update reminder appear again later, and refreshes release metadata.
    if (didBackground) {
      _checkForAppUpdate();
    }
  }


  Future<void> _checkForAppUpdate() async {
    if (_updateCheckStarted || !mounted) return;
    _updateCheckStarted = true;
    final updates = AppUpdateService();
    final update = await updates.check();
    if (!mounted || update == null) { _updateCheckStarted = false; return; }
    var downloading = false;
    var received = 0;
    var total = update.apkSizeBytes ?? 0;
    var error = '';
    var installerLaunched = false;
    String sizeLabel(int bytes) => bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(1)} MB' : '${(bytes / 1024).toStringAsFixed(0)} KB';
    await showDialog<void>(
      context: context,
      barrierDismissible: !update.mandatory && update.allowSkip,
      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
        final progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
        final percent = (progress * 100).round();
        return PopScope(
          canPop: !update.mandatory && update.allowSkip && !downloading,
          child: Dialog(
            backgroundColor: const Color(0xFF071329),
            insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: const BorderSide(color: Color(0xFF1B4770))),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  width: 68, height: 68, alignment: Alignment.center,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(21), gradient: const LinearGradient(colors: [Color(0xFF1677FF), Color(0xFF713BFF)])),
                  child: const Icon(Icons.system_update_rounded, size: 36, color: Colors.white),
                ),
                const SizedBox(height: 18),
                const Text('NUMELIXA UPDATE', style: TextStyle(color: AppTheme.cyan, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Version ${update.version}', style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                const Text('A better Numelixa experience is ready.', style: TextStyle(color: Color(0xFFA7B7D0), height: 1.4)),
                if (!downloading) ...[
                  const SizedBox(height: 18),
                  Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF0D2345), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF1B4770))),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.auto_awesome_rounded, color: AppTheme.cyan, size: 18), SizedBox(width: 8), Text('What’s new', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))]),
                      const SizedBox(height: 9),
                      Text(update.releaseNotes.trim().isEmpty ? 'Improvements, stability updates and bug fixes.' : update.releaseNotes.trim(), maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFA7B7D0), height: 1.5, fontSize: 13)),
                      if (update.apkSizeBytes != null && update.apkSizeBytes! > 0) ...[const SizedBox(height: 10), Row(children: [const Icon(Icons.download_rounded, size: 16, color: AppTheme.cyan), const SizedBox(width: 7), Text('Update size · ${sizeLabel(update.apkSizeBytes!)}', style: const TextStyle(color: Color(0xFFDAE9FF), fontSize: 12, fontWeight: FontWeight.w700))])],
                    ]),
                  ),
                ],
                if (downloading) ...[
                  const SizedBox(height: 22),
                  Row(children: [const Icon(Icons.downloading_rounded, color: AppTheme.cyan, size: 22), const SizedBox(width: 9), Expanded(child: Text(total > 0 ? 'Downloading update · ${sizeLabel(total)}' : 'Connecting to download…', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))), if (total > 0) Text('$percent%', style: const TextStyle(color: AppTheme.cyan, fontSize: 18, fontWeight: FontWeight.w900))]),
                  const SizedBox(height: 14),
                  ClipRRect(borderRadius: BorderRadius.circular(20), child: LinearProgressIndicator(value: total > 0 ? progress : null, minHeight: 10, backgroundColor: const Color(0xFF203553), color: AppTheme.cyan)),
                  const SizedBox(height: 10),
                  Text(total > 0 ? '${sizeLabel(received)} of ${sizeLabel(total)} downloaded' : '${sizeLabel(received)} downloaded', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFDAE9FF), fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 10),
                  const Text('Keep Numelixa open while the update downloads. Your account and app data will remain on this device.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFFA7B7D0), height: 1.4)),
                ],
                if (error.isNotEmpty) ...[const SizedBox(height: 14), Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF3B1827), borderRadius: BorderRadius.circular(12)), child: Text(error, style: const TextStyle(color: Color(0xFFFFA5B5), fontSize: 12)))],
                if (installerLaunched && update.mandatory) ...[
                  const SizedBox(height: 14),
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF12334A), borderRadius: BorderRadius.circular(12)), child: const Text('Complete the Android installation to continue using Numelixa. If you cancelled it, tap Install update again.', style: TextStyle(color: Color(0xFFBFEAFF), fontSize: 12, height: 1.45))),
                ],
                const SizedBox(height: 22),
                if (!downloading) FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppTheme.cyan, foregroundColor: const Color(0xFF031021), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  onPressed: () async {
                    setDialogState(() { downloading = true; received = 0; error = ''; });
                    try {
                      await updates.downloadAndOpen(update, (r, t) { if (dialogContext.mounted) setDialogState(() { received = r; if (t > 0) total = t; }); });
                      if (dialogContext.mounted) {
                        // Keep mandatory updates blocking if the user returns
                        // from Android's installer without completing install.
                        setDialogState(() { downloading = false; installerLaunched = true; });
                      }
                    } catch (e) {
                      if (dialogContext.mounted) setDialogState(() { downloading = false; error = 'Could not download or open the installer. Check your connection and try again. Details: ${e.toString()}'; });
                    }
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: Text(installerLaunched && update.mandatory ? 'Install update again' : 'Download and install', style: const TextStyle(fontWeight: FontWeight.w900)),
                ),
                if (!update.mandatory && update.allowSkip && !downloading) ...[const SizedBox(height: 8), Center(child: TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Remind me later', style: TextStyle(color: Color(0xFFA7B7D0)))))],
              ])),
            ),
          ),
        );
      }),
    );
    _updateCheckStarted = false;
  }

  Future<void> _syncNotifications() async {
    final auth = context.read<AuthService>();
    if (!auth.isReady || !auth.isSignedIn) return;
    final notifications = context.read<NotificationService>();
    final permission = await notifications.requestPermission();
    if (!mounted) return;
    if (permission.isGranted) await notifications.syncToken(auth);
  }

  void _handleNotificationRoute() {
    final route = appNotificationRoute.value;
    if (!mounted || route == null) return;
    appNotificationRoute.value = null;

    // Normal push notifications should open the regular app dashboard, not
    // the in-app Notifications screen or an unrelated tab. Keep the explicit
    // security approval flow intact for login-approval notifications.
    if (route.startsWith('login_approval:')) {
      final approvalId = route.substring('login_approval:'.length).trim();
      if (approvalId.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _LoginApprovalPage(approvalId: approvalId),
        ));
        return;
      }
    }
    setState(() => _index = 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appNotificationRoute.removeListener(_handleNotificationRoute);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Restore the session and check for a mandatory app update before
      // applying country/device access restrictions. Older installations must
      // still be able to receive the update that restores current policy support.
      final auth = context.read<AuthService>();
      await auth.restore();
      if (!mounted) return;
      await _checkForAppUpdate();
      if (!mounted) return;
      try {
        final access = await ApiClient().get('/api/mobile/access-check');
        if (access['allowed'] == false) {
          if (mounted) setState(() => _accessBlock = Map<String, dynamic>.from(access));
          return;
        }
      } catch (_) {
        // Keep the app usable if a temporary policy lookup cannot be reached.
      }
      final notifications = context.read<NotificationService>();
      await notifications.initialize(auth: auth);
      // Ask only once a real account is signed in; registration requires that
      // account's mobile bearer token to associate the FCM token correctly.
      if (auth.biometricLocked) {
        try { await auth.unlockBiometrics(); } catch (_) {}
      }
      if (auth.isSignedIn && !auth.biometricLocked) {
        final permission = await notifications.requestPermission();
        if (permission.isGranted) await notifications.syncToken(auth);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (_accessBlock != null) return _AppUnavailableScreen(details: _accessBlock!);
    if (!auth.isReady) {
      return const _SplashScreen();
    }
    if (!auth.isSignedIn) return const _AuthScreen();
    if (auth.biometricLocked) return const _BiometricLockScreen();
    if (auth.needsEmailVerification) return const _EmailVerificationScreen();
    final role = (auth.user?['role'] ?? 'user').toString();
    if (role == 'support_admin' || role == 'support_agent') {
      return SupportAdminScreen(accessToken: auth.accessToken!, role: role);
    }
    final pages = [
      const _HomePage(),
      const _CatalogPage(),
      const _OrdersPage(),
      const _WalletPage(),
      const _AccountPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          _NumelixaLogo(size: 27),
          SizedBox(width: 9),
          Text('Numelixa', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5)),
        ]),
      ),
      body: SafeArea(child: IndexedStack(index: _index, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.public_rounded), label: 'Buy'),
          NavigationDestination(icon: Icon(Icons.sms_outlined), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), label: 'Account'),
        ],
      ),
    );
  }
}

class _AppUnavailableScreen extends StatelessWidget {
  const _AppUnavailableScreen({required this.details});
  final Map<String, dynamic> details;
  @override
  Widget build(BuildContext context) {
    final reason = (details['reason'] ?? '').toString();
    final countryBlocked = reason == 'country';
    final appVersionBlocked = reason == 'version';
    final number = (details['whatsapp'] ?? '252907868526').toString().replaceAll(RegExp(r'[^0-9]'), '');
    final message = countryBlocked
        ? 'This app is not available in your country.'
        : appVersionBlocked
          ? 'This Numelixa app version is no longer supported.'
          : reason == 'android-version'
            ? 'This app is not available on this Android version.'
            : 'This app is not available on this device.';
    final description = appVersionBlocked
        ? 'An administrator has retired this app version. Install the latest official Numelixa update to continue. If you still cannot update, contact support and we will help you.'
        : 'If you believe this is a mistake, contact our support team for assistance.';
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 76, height: 76, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF17233D), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF365174))),
              child: const Icon(Icons.public_off_rounded, size: 38, color: Color(0xFF8CB8F7))),
            const SizedBox(height: 22),
            const Text('NUMELIXA', style: TextStyle(fontSize: 13, letterSpacing: 2.5, fontWeight: FontWeight.w900, color: AppTheme.cyan)),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 23, height: 1.2, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Text(description, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF91A8C4), height: 1.55)),
            if (appVersionBlocked) ...[
              const SizedBox(height: 18),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: () => launchUrl(Uri.parse('https://www.numelixa.com/android'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.system_update_rounded),
                label: const Text('Get the latest Numelixa update'),
              )),
            ],
            const SizedBox(height: 22),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: number.isEmpty ? null : () => launchUrl(Uri.parse('https://wa.me/$number'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.chat_rounded), label: const Text('Contact WhatsApp support'),
            )),
          ],
        )),
      ))),
    );
  }
}

class _NumelixaLogo extends StatelessWidget {
  const _NumelixaLogo({this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter: _NumelixaBrandPainter()),
  );
}

class _NumelixaBrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final globe = Paint()..shader = const LinearGradient(
      colors: [Color(0xFF27E8FF), Color(0xFF0864FF), Color(0xFF07134C)],
      begin: Alignment.topLeft, end: Alignment.bottomRight,
    ).createShader(const Rect.fromLTWH(8, 5, 84, 84));
    canvas.drawCircle(const Offset(50, 43), 35, globe);
    final grid = Paint()..color = const Color(0xFF71EFFF).withValues(alpha: .42)..style = PaintingStyle.stroke..strokeWidth = 1.1;
    canvas.drawOval(Rect.fromCenter(center: const Offset(50,43),width:58,height:66),grid);
    canvas.drawOval(Rect.fromCenter(center: const Offset(50,43),width:30,height:66),grid);
    canvas.drawLine(const Offset(18,43),const Offset(82,43),grid);
    final ribbon = Path()..moveTo(19,72)..cubicTo(28,48,34,26,43,28)..cubicTo(51,29,57,47,65,57)..cubicTo(72,67,80,69,84,60)..cubicTo(87,54,87,45,87,38);
    final paint = Paint()..style=PaintingStyle.stroke..strokeWidth=13..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round
      ..shader=const LinearGradient(colors:[Color(0xFF2AF4EE),Color(0xFF168BFF),Color(0xFF722CFF),Color(0xFFEF43E8)]).createShader(const Rect.fromLTWH(10,20,82,60));
    canvas.drawPath(ribbon,paint);
    final orbit=Path()..moveTo(5,57)..cubicTo(23,38,43,39,60,48)..cubicTo(75,56,88,51,96,39);
    canvas.drawPath(orbit,Paint()..style=PaintingStyle.stroke..strokeWidth=2.2..strokeCap=StrokeCap.round..color=Colors.white);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 82, height: 82, alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(27),
          gradient: const LinearGradient(colors: [Color(0xFF1677FF), Color(0xFF00D9FF)]),
        ),
        child: const _NumelixaLogo(size: 62),
      ),
      const SizedBox(height: 20),
      const Text('NUMELIXA', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 3)),
      const SizedBox(height: 7),
      const Text('Numbers, without the noise.', style: TextStyle(color: Color(0xFF91A8C4))),
      const SizedBox(height: 25),
      const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
    ])),
  );
}

class _AuthScreen extends StatefulWidget {
  const _AuthScreen();
  @override
  State<_AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<_AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _apiKey = TextEditingController();
  bool _creating = false;
  bool _phoneMode = false;
  bool _phoneCodeSent = false;
  final _phone = TextEditingController();
  final _phoneCode = TextEditingController();
  bool _showApiKey = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); _apiKey.dispose(); _phone.dispose(); _phoneCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.isEmpty || (_creating && _name.text.trim().length < 2)) {
      setState(() => _error = _creating
        ? 'Enter your name, a valid email, and a password of at least 8 characters.'
        : 'Enter your account email and password.');
      return;
    }
    if (_creating && password.length < 8) {
      setState(() => _error = 'Your password must contain at least 8 characters.');
      return;
    }
    setState(() { _error = null; });
    try {
      if (_creating) {
        await context.read<AuthService>().register(name: _name.text, email: email, password: password);
      } else {
        await context.read<AuthService>().signInWithEmail(email: email, password: password);
      }
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final notifications = context.read<NotificationService>();
      final permission = await notifications.requestPermission();
      if (permission.isGranted) await notifications.syncToken(auth);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect. Please check your internet and try again.');
    }
  }

  Future<void> _requestPhoneCode() async {
    final phone = _phone.text.trim();
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)) {
      setState(() => _error = 'Enter your phone number in international format, for example +2519XXXXXXXX.');
      return;
    }
    if (_creating && _name.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name first.');
      return;
    }
    setState(() { _error = null; });
    try {
      await context.read<AuthService>().requestPhoneCode(phone: phone, name: _name.text, signup: _creating);
      if (mounted) setState(() => _phoneCodeSent = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send the phone verification code. Try again.');
    }
  }

  Future<void> _verifyPhoneCode() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_phoneCode.text.trim())) {
      setState(() => _error = 'Enter the 6-digit verification code.');
      return;
    }
    setState(() { _error = null; });
    try {
      final auth = context.read<AuthService>();
      await auth.verifyPhoneCode(phone: _phone.text, code: _phoneCode.text, name: _name.text);
      if (!mounted) return;
      final notifications = context.read<NotificationService>();
      final permission = await notifications.requestPermission();
      if (permission.isGranted) await notifications.syncToken(auth);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Phone verification could not be completed. Try again.');
    }
  }

  Future<void> _google() async {
    setState(() => _error = null);
    try {
      await context.read<AuthService>().signInWithGoogle();
      if (!mounted) return;
      final auth = context.read<AuthService>();
      final notifications = context.read<NotificationService>();
      final permission = await notifications.requestPermission();
      if (permission.isGranted) await notifications.syncToken(auth);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Account email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Send reset link')),
        ],
      ),
    );
    controller.dispose();
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await NumelixaRepository().forgotPassword(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If the account exists, a password reset email will be sent.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not request a reset email.');
    }
  }

  Future<void> _apiKeyLogin() async {
    try {
      await context.read<AuthService>().signInWithApiKey(_apiKey.text);
      if (mounted) {
        final auth = context.read<AuthService>();
        final notifications = context.read<NotificationService>();
        final permission = await notifications.requestPermission();
        if (permission.isGranted) await notifications.syncToken(auth);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not validate this API key.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    const ink = Color(0xFF061225);
    const blue = Color(0xFF168BFF);
    const cyan = Color(0xFF35DDF5);
    Widget sectionLabel(String value) => Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 3),
      child: Text(value.toUpperCase(), style: const TextStyle(
        color: Color(0xFF9DB5D1), fontSize: 10, letterSpacing: 1.35,
        fontWeight: FontWeight.w800)),
    );
    InputDecoration fieldDecoration(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label, prefixIcon: Icon(icon, color: const Color(0xFF83A9D0)),
        suffixIcon: suffix, filled: true, fillColor: const Color(0xFF07172B),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        labelStyle: const TextStyle(color: Color(0xFF9DB5D1)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF203D5C))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: cyan, width: 1.5)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );
    return Scaffold(
      backgroundColor: ink,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF102D58), Color(0xFF07172D), Color(0xFF030A15)])))),
        Positioned(top: -125, right: -95, child: Container(width: 270, height: 270,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x442078FF), blurRadius: 100, spreadRadius: 35)]))),
        Positioned(bottom: -150, left: -120, child: Container(width: 300, height: 300,
          decoration: const BoxDecoration(shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Color(0x332B57FF), blurRadius: 110, spreadRadius: 35)]))),
        SafeArea(child: Center(child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Column(children: [
                Container(width: 76, height: 76, padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(colors: [cyan, blue, Color(0xFF8655FF)]),
                    boxShadow: const [BoxShadow(color: Color(0x55328BFF), blurRadius: 28, spreadRadius: 1)]),
                  child: ClipRRect(borderRadius: BorderRadius.circular(21),
                    child: Container(color: const Color(0xFF030B18),
                      alignment: Alignment.center, child: const _NumelixaLogo(size: 60)))),
                const SizedBox(height: 13),
                const Text('Numelixa', style: TextStyle(color: Colors.white,
                  fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.7)),
                const SizedBox(height: 5),
                const Text('Your numbers. Your world.',
                  style: TextStyle(color: Color(0xFFAAC2DE), fontSize: 13, letterSpacing: .2)),
              ])),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(
                  color: const Color(0xF20A1B30),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: const Color(0xFF25496C)),
                  boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 32, offset: Offset(0, 16))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(_creating ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(color: Colors.white, fontSize: 25,
                      fontWeight: FontWeight.w900, letterSpacing: -.65)),
                  const SizedBox(height: 6),
                  Text(_creating ? 'Set up your secure Numelixa account.' : 'Sign in to continue to your Numelixa account.',
                    style: const TextStyle(color: Color(0xFFA7BCD4), fontSize: 13, height: 1.45)),
                  if (!_phoneMode) ...[
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: auth.isValidating ? null : _google,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF102743),
                        side: const BorderSide(color: Color(0xFF315477)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                        Icon(Icons.g_mobiledata_rounded, size: 30, color: Color(0xFF69A9FF)),
                        SizedBox(width: 9),
                        Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.w800)),
                      ]),
                    ),
                    const SizedBox(height: 17),
                    Row(children: const [
                      Expanded(child: Divider(color: Color(0xFF29425D))),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('OR USE EMAIL', style: TextStyle(color: Color(0xFF7F9AB8),
                          fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800))),
                      Expanded(child: Divider(color: Color(0xFF29425D))),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: _AuthModeButton(label: 'Sign in', selected: !_creating,
                      onPressed: auth.isValidating ? null : () => setState(() { _creating = false; _phoneCodeSent = false; _error = null; }))),
                    const SizedBox(width: 8),
                    Expanded(child: _AuthModeButton(label: 'Create account', selected: _creating,
                      onPressed: auth.isValidating ? null : () => setState(() { _creating = true; _phoneCodeSent = false; _error = null; }))),
                  ]),
                  const SizedBox(height: 12),
                  Container(padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFF061326),
                      borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF203A56))),
                    child: Row(children: [
                      Expanded(child: _AuthModeButton(label: 'Email', selected: !_phoneMode,
                        onPressed: auth.isValidating ? null : () => setState(() { _phoneMode = false; _error = null; }))),
                      const SizedBox(width: 5),
                      Expanded(child: _AuthModeButton(label: 'Phone', selected: _phoneMode,
                        onPressed: auth.isValidating ? null : () => setState(() { _phoneMode = true; _error = null; }))),
                    ])),
                  if (_creating) ...[
                    const SizedBox(height: 18), sectionLabel('Full name'),
                    TextField(controller: _name, textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration('Your name', Icons.person_outline_rounded)),
                  ],
                  if (_phoneMode) ...[
                    const SizedBox(height: 18), sectionLabel('Phone number'),
                    TextField(controller: _phone, keyboardType: TextInputType.phone,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: fieldDecoration('e.g. +2519XXXXXXXX', Icons.phone_iphone_rounded)),
                    if (_phoneCodeSent) ...[
                      const SizedBox(height: 14), const Text('Verification code',
                        style: TextStyle(color: Color(0xFFB5C8DD), fontWeight: FontWeight.w700)),
                      const SizedBox(height: 9), _OtpCodeField(controller: _phoneCode),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: auth.isValidating ? null : _verifyPhoneCode,
                        child: const Text('Verify and continue')),
                      TextButton(onPressed: auth.isValidating ? null : _requestPhoneCode,
                        child: const Text('Resend code')),
                    ] else ...[
                      const SizedBox(height: 16),
                      FilledButton(onPressed: auth.isValidating ? null : _requestPhoneCode,
                        child: const Text('Send verification code')),
                    ],
                  ] else ...[
                    const SizedBox(height: 18), sectionLabel('Email address'),
                    TextField(controller: _email, keyboardType: TextInputType.emailAddress,
                      autocorrect: false, autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: fieldDecoration('name@example.com', Icons.mail_outline_rounded)),
                    const SizedBox(height: 14), sectionLabel('Password'),
                    TextField(controller: _password, obscureText: _obscurePassword,
                      autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
                      onSubmitted: (_) => auth.isValidating ? null : _submit(),
                      decoration: fieldDecoration('Enter your password', Icons.lock_outline_rounded,
                        suffix: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            color: const Color(0xFF91ABC6)),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword)))),
                    if (!_creating) Align(alignment: Alignment.centerRight,
                      child: TextButton(onPressed: auth.isValidating ? null : _forgotPassword,
                        style: TextButton.styleFrom(foregroundColor: cyan),
                        child: const Text('Forgot password?'))),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0x332C1320),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0x88FF6B8C))),
                      child: Text(_error!, style: const TextStyle(color: Color(0xFFFFA9BD), height: 1.4))),
                  ],
                  if (!_phoneMode) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: auth.isValidating ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: blue, foregroundColor: Colors.white,
                        elevation: 5, shadowColor: const Color(0x66328BFF),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                      child: auth.isValidating
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_creating ? 'Create account' : 'Sign in securely',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    ),
                  ],
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => setState(() { _showApiKey = !_showApiKey; _error = null; }),
                    icon: const Icon(Icons.key_rounded, size: 17),
                    label: Text(_showApiKey ? 'Hide API key sign in' : 'Sign in with API key'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(45),
                      foregroundColor: const Color(0xFFBBD2EA),
                      side: const BorderSide(color: Color(0xFF294967)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                  ),
                  if (_showApiKey) ...[
                    const SizedBox(height: 12),
                    TextField(controller: _apiKey, obscureText: !_showApiKey,
                      autocorrect: false, decoration: fieldDecoration('Numelixa API key', Icons.vpn_key_rounded)),
                    const SizedBox(height: 9),
                    OutlinedButton(onPressed: auth.isValidating ? null : _apiKeyLogin,
                      child: const Text('Connect API key')),
                  ],
                ]),
              ),
              const SizedBox(height: 18),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.shield_outlined, size: 15, color: Color(0xFF55D8B8)),
                SizedBox(width: 7),
                Text('Secure sign-in · Your account stays protected',
                  style: TextStyle(color: Color(0xFF8FA9C4), fontSize: 11, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Center(child: Text(_creating ? 'Already registered? Sign in' : 'New to Numelixa? Create an account',
                style: const TextStyle(color: Color(0xFFA8BED5), fontSize: 12))),
            ]),
          ),
        ))),
      ]),
    );
  }

}

class _OtpCodeField extends StatefulWidget {
  const _OtpCodeField({required this.controller});
  final TextEditingController controller;
  @override
  State<_OtpCodeField> createState() => _OtpCodeFieldState();
}
class _OtpCodeFieldState extends State<_OtpCodeField> {
  @override
  void initState() { super.initState(); widget.controller.addListener(_refresh); }
  @override
  void didUpdateWidget(covariant _OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { widget.controller.removeListener(_refresh); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    return Semantics(
      label: '6-digit verification code',
      textField: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(padding: EdgeInsets.only(bottom: 9, left: 3), child: Text('6-digit verification code', style: TextStyle(color: Color(0xFFCDDAEC), fontWeight: FontWeight.w600))),
        SizedBox(height: 62, child: Stack(children: [
          Row(children: List.generate(6, (index) {
            final filled = index < value.length;
            final active = index == value.length;
            return Expanded(child: Container(
              height: 58,
              margin: EdgeInsets.only(right: index == 5 ? 0 : 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF07152B),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: active ? AppTheme.cyan : filled ? AppTheme.blue.withValues(alpha: .7) : const Color(0xFF263F62), width: active ? 1.6 : 1),
                boxShadow: active ? const [BoxShadow(color: Color(0x2200D9FF), blurRadius: 12)] : const [],
              ),
              child: Text(filled ? value[index] : '', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white)),
            ));
          })),
          Positioned.fill(child: TextField(
            controller: widget.controller,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.transparent, fontSize: 24),
            cursorColor: Colors.transparent,
            decoration: const InputDecoration(
              counterText: '',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          )),
        ])),
      ]),
    );
  }
}

class _AuthModeButton extends StatelessWidget {
  const _AuthModeButton({required this.label, required this.selected, required this.onPressed});
  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      gradient: selected ? const LinearGradient(colors: [Color(0xFF1677FF), Color(0xFF6545F5)]) : null,
      color: selected ? null : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: selected ? const Color(0xFF70C9FF) : Colors.transparent),
      boxShadow: selected ? const [BoxShadow(color: Color(0x331677FF), blurRadius: 16, offset: Offset(0, 5))] : const [],
    ),
    child: TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : const Color(0xFFA7B7D0),
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    ),
  );
}

class _EmailVerificationScreen extends StatefulWidget {
  const _EmailVerificationScreen();
  @override
  State<_EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<_EmailVerificationScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _code.dispose(); super.dispose(); }

  Future<void> _verify() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code sent to your email.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final auth = context.read<AuthService>();
      final notifications = context.read<NotificationService>();
      final ok = await auth.verifyEmailCode(_code.text);
      if (!ok) throw const ApiException('The verification code was not accepted.');
      if (!mounted) return;
      await notifications.syncToken(auth);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify this code. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<AuthService>().resendVerificationCode();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A verification code request was submitted. Check your inbox.')));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not send another verification code.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = (context.watch<AuthService>().user?['email'] ?? '').toString();
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.mark_email_read_outlined, size: 64, color: AppTheme.cyan),
            const SizedBox(height: 20),
            const Text('Verify your email', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text('Enter the 6-digit code sent to $email to activate purchases and your wallet.',
              textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFA7B7D0), height: 1.5)),
            const SizedBox(height: 22),
            TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(labelText: 'Verification code', counterText: '')),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Color(0xFFFF788C)))],
            const SizedBox(height: 14),
            FilledButton(onPressed: _busy ? null : _verify,
              child: _busy ? const CircularProgressIndicator(strokeWidth: 2) : const Text('Verify email')),
            TextButton(onPressed: _busy ? null : _resend, child: const Text('Resend code')),
            TextButton(onPressed: () async => context.read<AuthService>().logout(), child: const Text('Sign out')),
          ],
        )),
      ))),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final name = (auth.user?['name'] ?? auth.user?['email'] ?? 'there').toString();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 28), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFF123C64), Color(0xFF0B1B34), Color(0xFF10162F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: const Color(0xFF24547B)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('GLOBAL VIRTUAL NUMBERS', style: TextStyle(color: AppTheme.mint, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
          const SizedBox(height: 13),
          Text('Welcome back, $name', style: const TextStyle(fontSize: 25, height: 1.15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text('Numbers, without the noise.', style: TextStyle(color: Color(0xFFB2C7DD), height: 1.45)),
        ]),
      ),
      const SizedBox(height: 18),
      const _DataCard(title: 'Available balance', icon: Icons.account_balance_wallet_outlined),
      const SizedBox(height: 12),
      const Text('Your workspace', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      const _ActionTile(icon: Icons.public_rounded, title: 'Browse services', subtitle: 'Explore the live catalog', destination: 'catalog'),
      const _ActionTile(icon: Icons.phone_android_rounded, title: 'Active numbers', subtitle: 'Manage waiting activations', destination: 'active'),
      const _ActionTile(icon: Icons.sms_outlined, title: 'Your orders', subtitle: 'View activations and SMS status', destination: 'orders'),
      const SizedBox(height: 14),
      const Text('Information shown here is retrieved from Numelixa APIs. If the service is unavailable, no example balance or order is substituted.', style: TextStyle(color: Color(0xFF7185A5), height: 1.5, fontSize: 12)),
    ]);
  }
}

class _DataCard extends StatefulWidget {
  const _DataCard({required this.title, required this.icon});
  final String title;
  final IconData icon;
  @override
  State<_DataCard> createState() => _DataCardState();
}
class _DataCardState extends State<_DataCard> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().balance(token: context.read<AuthService>().accessToken!); }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(18), child: FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      final value = snapshot.data?['balance'];
      return Row(children: [
        Icon(widget.icon, color: AppTheme.cyan, size: 27),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12)),
          const SizedBox(height: 5),
          if (snapshot.connectionState == ConnectionState.waiting)
            const SizedBox(height: 23, width: 23, child: CircularProgressIndicator(strokeWidth: 2))
          else if (snapshot.hasError)
            const Text('Balance unavailable', style: TextStyle(color: Color(0xFFFF788C)))
          else
            Text(value == null ? 'Balance unavailable' : '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)} USD', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        ])),
        IconButton(onPressed: () => setState(_load), icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
      ]);
    },
  )));
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.destination});
  final IconData icon; final String title, subtitle, destination;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: const Color(0xFF102844), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: AppTheme.cyan)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12)),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        final page = switch (destination) {
          'catalog' => const _CatalogPage(),
          'orders' => const _OrdersPage(),
          'active' => const _ActiveNumbersPage(),
          _ => const _NotificationsPage(),
        };
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
      },
    ),
  );
}

class _CatalogPage extends StatefulWidget {
  const _CatalogPage();
  @override
  State<_CatalogPage> createState() => _CatalogPageState();
}
class _CatalogPageState extends State<_CatalogPage> {
  late Future<Map<String, dynamic>> _future;
  String _search = '';
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().services(token: context.read<AuthService>().accessToken); }

  String _serviceKey(Map<String, dynamic> service) =>
      (service['name'] ?? service['title'] ?? service['id'] ?? service['code'] ?? '')
          .toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '')
          .replaceFirst(RegExp(r'\\d+$'), '');

  String _serviceName(Map<String, dynamic> service) {
    final raw = (service['name'] ?? service['title'] ?? service['id'] ?? service['code'] ?? 'Service').toString().trim();
    final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const names = <String, String>{
      'wa': 'WhatsApp', 'whatsapp': 'WhatsApp', 'tg': 'Telegram', 'telegram': 'Telegram',
      'fb': 'Facebook', 'facebook': 'Facebook', 'ig': 'Instagram', 'instagram': 'Instagram',
      'tt': 'TikTok', 'tiktok': 'TikTok', 'googlevoice': 'Google Voice', 'google': 'Google',
      'gmail': 'Gmail', 'youtube': 'YouTube', 'ms': 'Microsoft', 'microsoft': 'Microsoft',
      'discord': 'Discord', 'snapchat': 'Snapchat', 'reddit': 'Reddit', 'netflix': 'Netflix',
      'amazon': 'Amazon', 'apple': 'Apple', 'x': 'X', 'twitter': 'X', 'spotify': 'Spotify',
      'linkedin': 'LinkedIn', 'pinterest': 'Pinterest', 'twitch': 'Twitch', 'steam': 'Steam',
      'uber': 'Uber', 'airbnb': 'Airbnb', 'yahoo': 'Yahoo', 'signal': 'Signal',
      'viber': 'Viber', 'wechat': 'WeChat', 'line': 'LINE', 'kakaotalk': 'KakaoTalk',
      'imo': 'imo', 'paypal': 'PayPal', 'binance': 'Binance', 'aliexpress': 'AliExpress',
      'ebay': 'eBay', 'microsoftteams': 'Microsoft Teams', 'telegramx': 'Telegram X',
      'olx': 'OLX', 'tinder': 'Tinder', 'bumble': 'Bumble', 'grab': 'Grab', 'bolt': 'Bolt',
    };
    if (names.containsKey(key)) return names[key]!;
    if (raw.contains(' ') || raw.contains('&')) return raw;
    return raw.replaceAll(RegExp(r'[_\-]+'), ' ')
        .split(RegExp(r'\s+')).where((part) => part.isNotEmpty)
        .map((part) => part.length <= 2 ? part.toUpperCase() : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  Widget _serviceLogo(Map<String, dynamic> service) {
    final rawKey = _serviceKey(service);
    const aliases = <String, String>{
      'wa':'whatsapp','tg':'telegram','go':'google','op':'openai','oi':'openai',
      'am':'amazon','fb':'facebook','ig':'instagram','tt':'tiktok','tw':'x',
      'ms':'microsoft','ap':'apple','ds':'discord','sn':'snapchat','li':'linkedin',
      'pp':'paypal','rd':'reddit','sp':'spotify','nf':'netflix','vb':'viber',
      'sg':'signal','gm':'gmail','yt':'youtube','in':'linkedin',
    };
    final key = aliases[rawKey] ?? rawKey;
    const logos = <String, String>{
      'wa': 'whatsapp/25D366', 'whatsapp': 'whatsapp/25D366',
      'tg': 'telegram/26A5E4', 'telegram': 'telegram/26A5E4',
      'fb': 'facebook/0866FF', 'facebook': 'facebook/0866FF',
      'ig': 'instagram/E4405F', 'instagram': 'instagram/E4405F',
      'tt': 'tiktok/FFFFFF', 'tiktok': 'tiktok/FFFFFF',
      'googlevoice': 'googlevoice/4285F4', 'google': 'google/4285F4',
      'gmail': 'gmail/EA4335', 'youtube': 'youtube/FF0033',
      'microsoft': 'microsoft/737373', 'microsoftteams': 'microsoftteams/6264A7',
      'discord': 'discord/5865F2', 'snapchat': 'snapchat/FFFC00',
      'reddit': 'reddit/FF4500', 'netflix': 'netflix/E50914',
      'amazon': 'amazon/FF9900', 'apple': 'apple/FFFFFF',
      'x': 'x/FFFFFF', 'twitter': 'x/FFFFFF', 'spotify': 'spotify/1DB954',
      'linkedin': 'linkedin/0A66C2', 'pinterest': 'pinterest/BD081C',
      'twitch': 'twitch/9146FF', 'steam': 'steam/FFFFFF',
      'uber': 'uber/FFFFFF', 'airbnb': 'airbnb/FF5A5F', 'yahoo': 'yahoo/6001D2',
      'signal': 'signal/3A76F0', 'viber': 'viber/7360F2', 'wechat': 'wechat/07C160',
      'line': 'line/00C300', 'kakaotalk': 'kakaotalk/FFCD00', 'paypal': 'paypal/003087',
      'binance': 'binance/F0B90B', 'aliexpress': 'aliexpress/FF4747', 'ebay': 'ebay/E53238',
      'tinder': 'tinder/FF6B6B', 'bumble': 'bumble/FFC629', 'grab': 'grab/00B14F',
      'bolt': 'bolt/34D186', 'olx': 'olx/6E0AD6', 'shopee': 'shopee/EE4D2D',
      'rakuten': 'rakuten/BF0000', 'dropbox': 'dropbox/0061FF', 'slack': 'slack/4A154B',
      'zoom': 'zoom/0B5CFF', 'notion': 'notion/FFFFFF', 'canva': 'canva/00C4CC',
      'figma': 'figma/F24E1E', 'openai': 'openai/FFFFFF', 'chatgpt': 'openai/FFFFFF',
      'tiktoklite': 'tiktok/FFFFFF', 'capcut': 'capcut/FFFFFF', 'threads': 'threads/FFFFFF',
      'instagramlite': 'instagram/E4405F', 'facebooklite': 'facebook/0866FF',
      'vk': 'vk/0077FF', 'yandex': 'yandex/FF0000', 'protonmail': 'protonmail/6D4AFF',
      'youtubemusic': 'youtubemusic/FF0033', 'hulu': 'hulu/1CE783',
      'disneyplus': 'disneyplus/113CCF', 'max': 'max/002BE7', 'paramountplus': 'paramountplus/0064FF',
      'booking': 'bookingdotcom/003B95', 'bookingcom': 'bookingdotcom/003B95',
      'expedia': 'expedia/191E3B', 'agoda': 'agoda/ED1C24',
      'steamcommunity': 'steam/FFFFFF', 'playstation': 'playstation/003791',
      'xbox': 'xbox/107C10', 'epicgames': 'epicgames/FFFFFF', 'roblox': 'roblox/FFFFFF',
      'coinbase': 'coinbase/0052FF', 'bybit': 'bybit/F7A600', 'okx': 'okx/FFFFFF',
      'kucoin': 'kucoin/23AF91', 'bitget': 'bitget/00F0FF', 'binanceus': 'binance/ F0B90B',
    };
    String? slug;
    for (final entry in logos.entries) {
      if (key == entry.key || key.startsWith(entry.key)) { slug = entry.value.replaceAll(' ', ''); break; }
    }
    final knownDomains = <String, String>{
      'whatsapp': 'whatsapp.com', 'telegram': 'telegram.org', 'facebook': 'facebook.com',
      'instagram': 'instagram.com', 'tiktok': 'tiktok.com', 'google': 'google.com',
      'gmail': 'mail.google.com', 'youtube': 'youtube.com', 'discord': 'discord.com',
      'snapchat': 'snapchat.com', 'reddit': 'reddit.com', 'netflix': 'netflix.com',
      'amazon': 'amazon.com', 'apple': 'apple.com', 'spotify': 'spotify.com',
      'linkedin': 'linkedin.com', 'pinterest': 'pinterest.com', 'twitch': 'twitch.tv',
      'steam': 'steampowered.com', 'uber': 'uber.com', 'airbnb': 'airbnb.com',
      'yahoo': 'yahoo.com', 'signal': 'signal.org', 'viber': 'viber.com',
      'wechat': 'wechat.com', 'line': 'line.me', 'paypal': 'paypal.com',
      'binance': 'binance.com', 'ebay': 'ebay.com', 'tinder': 'tinder.com',
      'bumble': 'bumble.com', 'shopee': 'shopee.com', 'dropbox': 'dropbox.com',
      'slack': 'slack.com', 'zoom': 'zoom.us', 'notion': 'notion.so',
      'canva': 'canva.com', 'figma': 'figma.com', 'openai': 'openai.com',
      'chatgpt': 'chatgpt.com', 'capcut': 'capcut.com', 'threads': 'threads.net',
      'vk': 'vk.com', 'yandex': 'yandex.com', 'protonmail': 'proton.me',
      'coinbase': 'coinbase.com', 'bybit': 'bybit.com', 'okx': 'okx.com',
    };
    String? domain;
    for (final entry in knownDomains.entries) {
      if (key == entry.key || key.startsWith(entry.key)) { domain = entry.value; break; }
    }
    domain ??= key.isEmpty ? 'example.com' : '$key.com';
    // Use a branded Simple Icons asset where available, with a larger
    // official-site favicon as fallback for supported brands.
    // Prefer the resolved official brand site's favicon: it avoids mismatched third-party
    // icon slugs for short provider IDs (wa, go, am, op, etc.).
    final imageUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
    return CircleAvatar(
      radius: 23,
      backgroundColor: const Color(0xFF102844),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.network(imageUrl, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.network(
            slug == null ? 'https://cdn.simpleicons.org/${key.isEmpty ? 'app' : key}' : 'https://cdn.simpleicons.org/$slug',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                _serviceName(service).trim().isEmpty ? '?' : _serviceName(service).trim().characters.first.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
              ),
            ),
          )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
      final raw = snapshot.data?['services'];
      final services = raw is List
          ? raw.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      if (services.isEmpty) return _RetryState(message: 'No live services are available right now.', onRetry: () => setState(_load));
      final filteredServices = services.where((service) {
        final query = _search.trim().toLowerCase();
        if (query.isEmpty) return true;
        return ['name','title','id','code','description','category'].any((key) => (service[key] ?? '').toString().toLowerCase().contains(query))
            || _serviceName(service).toLowerCase().contains(query);
      }).toList();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Choose a service', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Find your service by its full name and official logo.', style: TextStyle(color: Color(0xFF91A8C4))),
        const SizedBox(height: 14),
        TextField(onChanged: (value) => setState(() => _search = value),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Search services', hintText: 'WhatsApp, Telegram, Instagram…')),
        const SizedBox(height: 12),
        if (filteredServices.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No services match your search.', textAlign: TextAlign.center)),
        for (final service in filteredServices)
          Card(child: InkWell(
            borderRadius: BorderRadius.circular(19),
            onTap: () {
              final id = (service['id'] ?? service['code'] ?? service['name'] ?? service['title'] ?? '').toString();
              if (id.isEmpty) return;
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CountriesPage(service: id, name: _serviceName(service))));
            },
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13), child: Row(children: [
              SizedBox(width: 54, height: 54, child: _serviceLogo(service)),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_serviceName(service), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text((service['description'] ?? service['category'] ?? 'Select to view country availability').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12, height: 1.35)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.cyan, size: 25),
            ])),
          )),
      ]);
    },
  );
}
class _CountriesPage extends StatefulWidget {
  const _CountriesPage({required this.service, required this.name});
  final String service;
  final String name;
  @override
  State<_CountriesPage> createState() => _CountriesPageState();
}
class _CountriesPageState extends State<_CountriesPage> {
  late Future<Map<String, dynamic>> _future;
  String _search = '';
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().countries(service: widget.service, token: context.read<AuthService>().accessToken); }
  Future<void> _confirmPurchase(Map<String, dynamic> country) async {
    final countryCode = (country['id'] ?? country['code'] ?? '').toString();
    if (countryCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This country has no supported purchase code.')));
      return;
    }
    final name = (country['name'] ?? country['title'] ?? countryCode).toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buy virtual number?'),
        content: Text('Request a live ${widget.service} number for $name? The server will confirm stock and price before charging your wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final auth = context.read<AuthService>();
      final result = await NumelixaRepository().purchase(
        token: auth.accessToken!,
        country: countryCode,
        service: widget.service,
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Number purchased. Opening Activations…')),
        );
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const _OrdersPage(),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((result['error'] ?? 'The order could not be completed.').toString()),
        ));
      }
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Network error. Please retry.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Countries · ${widget.name}')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
        final raw = snapshot.data?['countries'];
        final countries = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
        if (countries.isEmpty) return _RetryState(message: 'No live country availability for this service.', onRetry: () => setState(_load));
        final filteredCountries = countries.where((country) {
          final query = _search.trim().toLowerCase();
          if (query.isEmpty) return true;
          return ['name','title','id','code','country','countryCode'].any((key) => (country[key] ?? '').toString().toLowerCase().contains(query));
        }).toList();
        return ListView(padding: const EdgeInsets.all(14), children: [
          TextField(onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Search countries', hintText: 'United States, India…')),
          const SizedBox(height: 12),
          if (filteredCountries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No countries match your search.', textAlign: TextAlign.center)),
          for (final country in filteredCountries)
            Card(child: ListTile(
              leading: Text((country['flag'] ?? '🌐').toString(), style: const TextStyle(fontSize: 25)),
              title: Text((country['name'] ?? country['title'] ?? country['id'] ?? 'Country').toString()),
              subtitle: Text('Stock: ${(country['stock'] is Map ? country['stock']['count'] : country['count']) ?? '—'}'),
              trailing: Text((double.tryParse(((country['stock'] is Map ? country['stock']['usdPrice'] : null) ?? country['usdPrice'] ?? '').toString()) ?? 0) > 0 ? '\$' + (double.tryParse(((country['stock'] is Map ? country['stock']['usdPrice'] : null) ?? country['usdPrice'] ?? '').toString())!).toStringAsFixed(2) + ' USD' : 'Price unavailable', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w800)),
              onTap: () => _confirmPurchase(country),
            )),
        ]);
      },
    ),
  );
}

class _OrdersPage extends StatefulWidget {
  const _OrdersPage();
  @override
  State<_OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<_OrdersPage> {
  String _selected = 'active';
  late Future<Map<String, dynamic>> _future;
  Timer? _refreshTimer;
  bool _loadingRefresh = false;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep activation status and incoming SMS fresh while this page is open.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshQuietly());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _load() {
    _future = NumelixaRepository().orders(
      token: context.read<AuthService>().accessToken!,
      limit: 100,
    );
  }

  Future<void> _refreshQuietly() async {
    if (!mounted || _loadingRefresh) return;
    _loadingRefresh = true;
    try {
      final fresh = NumelixaRepository().orders(
        token: context.read<AuthService>().accessToken!,
        limit: 100,
      );
      await fresh;
      if (mounted) setState(() => _future = fresh);
    } catch (_) {
      // Keep the last usable order list if a background refresh temporarily fails.
    } finally {
      _loadingRefresh = false;
    }
  }

  Widget _platformLogo(String service) {
    final rawName = service.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const aliases = <String, String>{
      'wa':'whatsapp','tg':'telegram','go':'google','op':'openai','oi':'openai',
      'am':'amazon','fb':'facebook','ig':'instagram','tt':'tiktok','tw':'x',
      'ms':'microsoft','ap':'apple','ds':'discord','sn':'snapchat','li':'linkedin',
      'pp':'paypal','rd':'reddit','sp':'spotify','nf':'netflix','vb':'viber','sg':'signal',
    };
    final name = aliases[rawName] ?? rawName;
    const logos = <String, String>{
      'whatsapp': 'whatsapp/25D366', 'facebook': 'facebook/0866FF',
      'instagram': 'instagram/E4405F', 'telegram': 'telegram/26A5E4',
      'tiktok': 'tiktok/FFFFFF', 'google': 'google/4285F4',
      'discord': 'discord/5865F2', 'snapchat': 'snapchat/FFFC00',
      'reddit': 'reddit/FF4500', 'netflix': 'netflix/E50914',
      'amazon': 'amazon/FF9900', 'microsoft': 'microsoft/737373',
      'apple': 'apple/FFFFFF', 'x': 'x/FFFFFF', 'twitter': 'x/FFFFFF',
      'uber': 'uber/FFFFFF', 'airbnb': 'airbnb/FF5A5F', 'spotify': 'spotify/1DB954',
      'linkedin': 'linkedin/0A66C2', 'pinterest': 'pinterest/BD081C',
      'twitch': 'twitch/9146FF', 'steam': 'steam/FFFFFF', 'signal': 'signal/3A76F0',
      'viber': 'viber/7360F2', 'wechat': 'wechat/07C160', 'line': 'line/00C300',
      'paypal': 'paypal/003087', 'binance': 'binance/F0B90B', 'ebay': 'ebay/E53238',
      'tinder': 'tinder/FF6B6B', 'bumble': 'bumble/FFC629', 'slack': 'slack/4A154B',
      'zoom': 'zoom/0B5CFF', 'notion': 'notion/FFFFFF', 'canva': 'canva/00C4CC',
      'figma': 'figma/F24E1E', 'openai': 'openai/FFFFFF', 'chatgpt': 'openai/FFFFFF',
    };
    const domains = <String, String>{
      'whatsapp': 'whatsapp.com', 'facebook': 'facebook.com', 'instagram': 'instagram.com',
      'telegram': 'telegram.org', 'tiktok': 'tiktok.com', 'google': 'google.com',
      'discord': 'discord.com', 'snapchat': 'snapchat.com', 'reddit': 'reddit.com',
      'netflix': 'netflix.com', 'amazon': 'amazon.com', 'microsoft': 'microsoft.com',
      'apple': 'apple.com', 'spotify': 'spotify.com', 'linkedin': 'linkedin.com',
      'pinterest': 'pinterest.com', 'twitch': 'twitch.tv', 'steam': 'steampowered.com',
      'signal': 'signal.org', 'viber': 'viber.com', 'wechat': 'wechat.com',
      'line': 'line.me', 'paypal': 'paypal.com', 'binance': 'binance.com',
      'ebay': 'ebay.com', 'tinder': 'tinder.com', 'bumble': 'bumble.com',
      'slack': 'slack.com', 'zoom': 'zoom.us', 'notion': 'notion.so',
      'canva': 'canva.com', 'figma': 'figma.com', 'openai': 'openai.com',
      'chatgpt': 'chatgpt.com',
    };
    String? slug;
    for (final entry in logos.entries) {
      if (name == entry.key || name.startsWith(entry.key)) { slug = entry.value; break; }
    }
    String? domain;
    for (final entry in domains.entries) {
      if (name == entry.key || name.startsWith(entry.key)) { domain = entry.value; break; }
    }
    domain ??= name.isEmpty ? 'example.com' : '$name.com';
    final imageUrl = 'https://www.google.com/s2/favicons?domain=$domain&sz=128';
    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFF102844),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Image.network(imageUrl, width: 26, height: 26, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Image.network(
            slug == null ? 'https://cdn.simpleicons.org/$name' : 'https://cdn.simpleicons.org/$slug',
            width: 26, height: 26, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
          )),
      ),
    );
  }

  String _platformName(String raw) {
    final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const names = <String, String>{
      'wa': 'WhatsApp', 'whatsapp': 'WhatsApp',
      'fb': 'Facebook', 'facebook': 'Facebook',
      'ig': 'Instagram', 'instagram': 'Instagram',
      'tg': 'Telegram', 'telegram': 'Telegram',
      'tt': 'TikTok', 'tiktok': 'TikTok',
      'googlevoice': 'Google Voice', 'google': 'Google',
      'ms': 'Microsoft', 'microsoft': 'Microsoft',
      'discord': 'Discord', 'snapchat': 'Snapchat',
      'reddit': 'Reddit', 'netflix': 'Netflix', 'amazon': 'Amazon',
      'apple': 'Apple', 'x': 'X', 'twitter': 'X',
      'spotify': 'Spotify', 'linkedin': 'LinkedIn',
      'pinterest': 'Pinterest', 'twitch': 'Twitch', 'steam': 'Steam',
    };
    if (names.containsKey(key)) return names[key]!;
    return raw.trim().split(RegExp(r'[_\-\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _smsCode(Map<String, dynamic> order) {
    final code = (order['code'] ?? '').toString().trim();
    if (code.isNotEmpty) return code;
    final sms = (order['fullSms'] ?? '').toString();
    return RegExp(r'(?<!\d)\d{4,8}(?!\d)').firstMatch(sms)?.group(0) ?? '';
  }

  DateTime? _codeReceivedAt(Map<String, dynamic> order) {
    for (final key in ['codeReceivedAt', 'smsReceivedAt', 'receivedAt', 'completedAt', 'updatedAt', 'createdAt']) {
      final raw = order[key];
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw.toString());
      if (parsed != null) return parsed.toLocal();
    }
    return null;
  }

  bool _isCanceled(String status) => status.toLowerCase().contains('cancel');

  bool _isSuccessful(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toLowerCase().replaceAll('_', ' ').trim();
    final code = _smsCode(order);
    if (code.isEmpty) return false;
    final terminal = ['success', 'successful', 'completed', 'complete', 'finished', 'received']
        .any((v) => status == v || status.contains(v));
    if (!terminal) return false;
    final receivedAt = _codeReceivedAt(order);
    // Keep the received code under Activations for ten minutes, then archive it.
    if (receivedAt == null) return false;
    return DateTime.now().difference(receivedAt) >= const Duration(minutes: 10);
  }

  bool _isActive(Map<String, dynamic> order) =>
      !_isCanceled((order['status'] ?? '').toString()) && !_isSuccessful(order);

  Future<void> _copyText(String value, String successMessage) async {
    if (value.trim().isEmpty || value == 'Number unavailable') return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
  }

  Future<void> _getCode(Map<String, dynamic> order) async {
    final id = (order['id'] ?? order['_id'] ?? '').toString();
    if (id.isEmpty) return;
    try {
      final result = await NumelixaRepository().checkSms(
        token: context.read<AuthService>().accessToken!,
        orderId: id,
      );
      if (!mounted) return;
      final code = (result['code'] ?? result['smsCode'] ?? '').toString().trim();
      if (code.isNotEmpty) {
        await Clipboard.setData(ClipboardData(text: code));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SMS code received and copied.')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No SMS code yet. The activation will keep checking.')));
      }
      setState(_load);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check this activation. Try again.')));
    }
  }

  void _showNewCodeInfo() {
    showDialog<void>(context: context, builder: (_) => const _NewCodeInfoDialog());
  }

  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final id = (order['id'] ?? order['_id'] ?? '').toString();
    if (id.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel activation?'),
        content: const Text('The app will request cancellation from Numelixa. Any refund depends on the server confirming a successful cancellation.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep number')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel activation')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await NumelixaRepository().cancelOrder(
        token: context.read<AuthService>().accessToken!,
        orderId: id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation request sent. Refreshing activations…')));
      setState(_load);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      if (mounted) setState(_load);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation could not be confirmed. No refund is assumed.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activations')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
        }
        final raw = snapshot.data?['orders'];
        final orders = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        final filtered = orders.where((order) {
          final status = (order['status'] ?? '').toString();
          if (_selected == 'active') return _isActive(order);
          if (_selected == 'successful') return _isSuccessful(order);
          return _isCanceled(status);
        }).toList()
          ..sort((a, b) {
            final aa = DateTime.tryParse((a['createdAt'] ?? '').toString());
            final bb = DateTime.tryParse((b['createdAt'] ?? '').toString());
            return (bb ?? DateTime.fromMillisecondsSinceEpoch(0))
                .compareTo(aa ?? DateTime.fromMillisecondsSinceEpoch(0));
          });
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'active', label: Text('Activations')),
                ButtonSegment(value: 'successful', label: Text('Successful')),
                ButtonSegment(value: 'canceled', label: Text('Canceled')),
              ],
              selected: {_selected},
              onSelectionChanged: (value) => setState(() => _selected = value.first),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
              ? _RetryState(
                  message: _selected == 'active'
                    ? 'New numbers stay here while waiting for SMS. You can copy the number or cancel the activation.'
                    : _selected == 'successful'
                      ? 'Activations with a received code older than 10 minutes appear here.'
                      : 'Canceled activations appear here.',
                  onRetry: () => setState(_load),
                  empty: true,
                )
              : RefreshIndicator(
                  onRefresh: _refreshQuietly,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final order in filtered)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  _platformLogo((order['service'] ?? '').toString()),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(
                                    _platformName((order['service'] ?? 'Virtual number').toString()),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                                  )),
                                  Text(
                                    _selected == 'active'
                                      ? (_smsCode(order).isEmpty ? 'Waiting for SMS' : 'Code received')
                                      : _selected == 'successful' ? 'Successful' : 'Canceled',
                                    style: TextStyle(
                                      color: _selected == 'active'
                                        ? AppTheme.cyan
                                        : _selected == 'successful' ? AppTheme.mint : const Color(0xFFFF788C),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ]),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(child: SelectableText(
                                    (order['phone'] ?? order['phoneNumber'] ?? order['number'] ?? 'Number unavailable').toString(),
                                    style: const TextStyle(fontSize: 18, color: AppTheme.cyan, fontWeight: FontWeight.w800),
                                  )),
                                  IconButton(
                                    tooltip: 'Copy number',
                                    onPressed: () => _copyText((order['phone'] ?? order['phoneNumber'] ?? order['number'] ?? '').toString(), 'Number copied.'),
                                    icon: const Icon(Icons.copy_rounded),
                                  ),
                                ]),
                                const SizedBox(height: 5),
                                Row(children: [const Text('Country: '), Expanded(child: Text((order['country'] ?? order['countryCode'] ?? '—').toString()))]),
                                if (_smsCode(order).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    const Text('SMS code: ', style: TextStyle(color: Color(0xFF91A8C4))),
                                    Expanded(child: SelectableText(_smsCode(order), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                                    IconButton(
                                      tooltip: 'Copy SMS code',
                                      onPressed: () => _copyText(_smsCode(order), 'SMS code copied.'),
                                      icon: const Icon(Icons.copy_rounded),
                                    ),
                                  ]),
                                  if (_selected == 'active')
                                    Text('This code stays in Activations for up to 10 minutes before moving to Successful.',
                                      style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12)),
                                ] else if (_selected == 'active') ...[
                                  const SizedBox(height: 8),
                                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                                    onPressed: () => _getCode(order),
                                    icon: const Icon(Icons.sms_outlined),
                                    label: const Text('Check for SMS code'),
                                  )),
                                ],
                                if (_selected == 'active') ...[
                                  const SizedBox(height: 8),
                                  Row(children: [
                                    Expanded(child: OutlinedButton.icon(
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                                        builder: (_) => _OrderDetailPage(orderId: (order['id'] ?? order['_id'] ?? '').toString()),
                                      )),
                                      icon: const Icon(Icons.open_in_new_rounded),
                                      label: const Text('Details'),
                                    )),
                                    const SizedBox(width: 10),
                                    Expanded(child: FilledButton.tonalIcon(
                                      onPressed: () => _cancelOrder(order),
                                      icon: const Icon(Icons.cancel_outlined),
                                      label: const Text('Cancel'),
                                    )),
                                  ]),
                                ],
                                if (_selected == 'successful') ...[
                                  const SizedBox(height: 10),
                                  SizedBox(width: double.infinity, child: OutlinedButton.icon(
                                    onPressed: _showNewCodeInfo,
                                    icon: const Icon(Icons.auto_awesome_rounded),
                                    label: const Text('Get New Code'),
                                  )),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
          ),
        ]);
      },
    ),
  );
}

class _NewCodeInfoDialog extends StatefulWidget {
  const _NewCodeInfoDialog();
  @override
  State<_NewCodeInfoDialog> createState() => _NewCodeInfoDialogState();
}

class _NewCodeInfoDialogState extends State<_NewCodeInfoDialog> {
  static const _services = ['WhatsApp', 'Telegram', 'Google', 'Instagram', 'TikTok', 'Facebook', 'Microsoft'];
  late final PageController _controller = PageController(viewportFraction: .42);
  Timer? _timer;
  int _page = 0;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || !_controller.hasClients) return;
      _page = (_page + 1) % _services.length;
      _controller.animateToPage(_page, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }
  @override
  void dispose() { _timer?.cancel(); _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: const Color(0xFF071329),
    title: const Text('Get a new verification code'),
    content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(height: 94, child: PageView.builder(
        controller: _controller,
        itemCount: _services.length,
        onPageChanged: (value) => _page = value,
        itemBuilder: (context, index) => Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Container(
          decoration: BoxDecoration(color: const Color(0xFF102844), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF23415F))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.apps_rounded, color: AppTheme.cyan, size: 27),
            const SizedBox(height: 7),
            Text(_services[index], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ]),
        )),
      )),
      const SizedBox(height: 15),
      const Icon(Icons.info_outline_rounded, color: AppTheme.cyan, size: 30),
      const SizedBox(height: 9),
      const Text('This completed activation has already received its SMS code. A second code cannot be retrieved from the same number.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA7B7D0), height: 1.5)),
      const SizedBox(height: 9),
      const Text('This service preview is view-only. To receive another code, choose a service and purchase a new number.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF91A8C4), fontSize: 12, height: 1.45)),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}

class _ActiveNumbersPage extends StatelessWidget {
  const _ActiveNumbersPage();
  @override
  Widget build(BuildContext context) => _ProtectedListPage(
    title: 'Active numbers',
    load: (repo, token) => repo.orders(token: token, limit: 100, status: 'waiting'),
    listKey: 'orders',
    empty: 'You have no active waiting numbers.',
    onItemTap: (item) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _OrderDetailPage(orderId: (item['id'] ?? '').toString()))),
    itemTitle: (item) => '${item['service'] ?? 'Virtual number'} · ${item['phone'] ?? 'Number pending'}',
    itemSubtitle: (item) => '${item['country'] ?? ''} • Waiting for SMS',
  );
}

class _OrderDetailPage extends StatefulWidget {
  const _OrderDetailPage({required this.orderId});
  final String orderId;
  @override
  State<_OrderDetailPage> createState() => _OrderDetailPageState();
}
class _OrderDetailPageState extends State<_OrderDetailPage> {
  late Future<Map<String, dynamic>> _future;
  bool _working = false;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().order(token: context.read<AuthService>().accessToken!, id: widget.orderId); }

  Future<void> _checkSms() async {
    setState(() => _working = true);
    try {
      final result = await NumelixaRepository().checkSms(token: context.read<AuthService>().accessToken!, orderId: widget.orderId);
      if (!mounted) return;
      final code = (result['code'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(code.isEmpty ? 'No SMS received yet. Try again shortly.' : 'Verification code received.')));
      setState(_load);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(_load);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not check SMS. Please retry.')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Cancel number?'),
      content: const Text('Numelixa will request cancellation from the provider. A refund is only recorded when cancellation succeeds.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep number')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel number')),
      ],
    ));
    if (confirm != true || !mounted) return;
    setState(() => _working = true);
    try {
      await NumelixaRepository().cancelOrder(token: context.read<AuthService>().accessToken!, orderId: widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation confirmed by Numelixa.')));
      setState(_load);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(_load);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cancellation could not be confirmed. No refund is assumed.')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Order details')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
        final order = snapshot.data?['order'];
        if (order is! Map) return _RetryState(message: 'Order details are unavailable.', onRetry: () => setState(_load), empty: true);
        final code = (order['code'] ?? '').toString();
        final status = (order['status'] ?? 'unknown').toString();
        return ListView(padding: const EdgeInsets.all(18), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((order['service'] ?? 'Virtual number').toString(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: SelectableText((order['phone'] ?? order['number'] ?? 'Number unavailable').toString(), style: const TextStyle(fontSize: 19, color: AppTheme.cyan, fontWeight: FontWeight.w700))),
              IconButton(tooltip: 'Copy number', icon: const Icon(Icons.copy_rounded), onPressed: () async {
                final number = (order['phone'] ?? order['number'] ?? '').toString();
                final messenger = ScaffoldMessenger.of(context);
                if (number.isNotEmpty) {
                  await Clipboard.setData(ClipboardData(text: number));
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('Number copied.')));
                }
              }),
            ]),
            const SizedBox(height: 14),
            _DetailLine(label: 'Country', value: (order['country'] ?? '').toString()),
            _DetailLine(label: 'Status', value: status),
            _DetailLine(label: 'Price', value: '${order['price'] ?? 0} coins'),
            _DetailLine(label: 'Created', value: (order['createdAt'] ?? '').toString()),
            _DetailLine(label: 'Expires', value: (order['expiresAt'] ?? '').toString()),
          ]))),
          const SizedBox(height: 14),
          Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('SMS verification', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
              if (code.isNotEmpty) IconButton(tooltip: 'Copy SMS code', icon: const Icon(Icons.copy_rounded), onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: code));
                if (!mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text('SMS code copied.')));
              }),
            ]),
            const SizedBox(height: 12),
            Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
              decoration: BoxDecoration(color: const Color(0xFF08243A), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF1677FF).withValues(alpha: .35))),
              child: Column(children: [
                Text(code.isEmpty ? 'Waiting for your code' : code, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: code.isEmpty ? 15 : 32, letterSpacing: code.isEmpty ? 0 : 5, fontWeight: FontWeight.w900, color: code.isEmpty ? const Color(0xFF91A8C4) : AppTheme.mint)),
                if (code.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('SMS code copied.')));
                  }, icon: const Icon(Icons.copy_rounded), label: const Text('Copy verification code')),
                ],
              ]),
            ),
            if ((order['fullSms'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text((order['fullSms']).toString(), style: const TextStyle(color: Color(0xFFB2C7DD))),
            ],
          ]))),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _working ? null : _checkSms, icon: const Icon(Icons.refresh_rounded), label: Text(_working ? 'Please wait…' : 'Check for SMS')),
          if (status == 'waiting') ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _working ? null : _cancelOrder, icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel number')),
          ],
        ]);
      },
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
    SizedBox(width: 92, child: Text(label, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12))),
    Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(fontWeight: FontWeight.w600))),
  ]));
}

class _WalletPage extends StatefulWidget {
  const _WalletPage();
  @override
  State<_WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<_WalletPage> with WidgetsBindingObserver {
  late Future<Map<String, dynamic>> _transactions;
  late Future<Map<String, dynamic>> _balance;
  late Future<Map<String, dynamic>> _assets;
  final TextEditingController _localPhone = TextEditingController();
  final TextEditingController _ethiopiaPhone = TextEditingController();
  final TextEditingController _ethiopiaPayerName = TextEditingController();
  final TextEditingController _amountController = TextEditingController(text: '5.00');
  final TextEditingController _cryptoSearch = TextEditingController();
  double _minTopupUsd = 1;
  double _maxTopupUsd = 10000;
  String _localMethod = 'waafi';
  String? _currency;
  String? _network;
  bool _creating = false;
  bool _localPaymentsOpen = false;
  bool _ethiopiaPaymentsOpen = false;
  Map<String, dynamic> _ethiopiaMethods = {};
  String _ethiopiaMethod = 'coopay_ebirr';
  double _ethiopiaSwipe = 0;
  Map<String, dynamic>? _ethiopiaOrder;
  bool _checkingEthiopiaPayment = false;
  Timer? _ethiopiaPaymentTimer;
  String _paymentMethod = 'crypto';
  bool _cryptoStep = false;
  String? _pendingLocalOrderId;
  bool _checkingLocalPayment = false;
  Timer? _localPaymentTimer;
  final ScreenshotController _qrScreenshot = ScreenshotController();
  Timer? _depositTimer;
  Timer? _depositStatusTimer;
  bool _checkingDepositStatus = false;
  String _depositStatus = 'pending';
  int _depositSecondsLeft = 0;
  StateSetter? _updateDepositDialog;

  @override
  void dispose() { _localPhone.dispose(); _ethiopiaPhone.dispose(); _ethiopiaPayerName.dispose(); _amountController.dispose(); _cryptoSearch.dispose(); _depositTimer?.cancel(); _depositStatusTimer?.cancel(); _localPaymentTimer?.cancel(); _ethiopiaPaymentTimer?.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); _load(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pendingLocalOrderId != null) _verifyLocalPayment();
      if (_ethiopiaOrder != null && _ethiopiaOrder?['status'] != 'paid') _verifyEthiopiaPayment();
    }
  }

  void _load() {
    final token = context.read<AuthService>().accessToken!;
    NumelixaRepository().localPaymentStatus().then((data) { if (mounted) setState(() => _localPaymentsOpen = data['ok'] == true && data['open'] == true && data['configured'] == true); }).catchError((_) { if (mounted) setState(() => _localPaymentsOpen = false); });
    final repo = NumelixaRepository();
    repo.ethiopiaPaymentMethods().then((data) {
      final methods = data['methods'] is Map ? Map<String, dynamic>.from(data['methods']) : <String, dynamic>{};
      final availableMethods = methods.entries.where((entry) => entry.value is Map && entry.value['open'] == true && (entry.value['receiver'] ?? '').toString().trim().isNotEmpty).map((entry) => entry.key).toList();
      final available = data['ok'] == true && (double.tryParse((data['etbPerUsd'] ?? '0').toString()) ?? 0) > 0 && availableMethods.isNotEmpty;
      if (mounted) setState(() { _ethiopiaMethods = methods; _ethiopiaPaymentsOpen = available; if (availableMethods.isNotEmpty && !availableMethods.contains(_ethiopiaMethod)) _ethiopiaMethod = availableMethods.first; });
    }).catchError((_) { if (mounted) setState(() => _ethiopiaPaymentsOpen = false); });
    _transactions = repo.transactions(token: token);
    _balance = repo.balance(token: token);
    _assets = repo.depositAssets(token: token);
    repo.walletPricing(token: token).then((data) {
      final pricing = data['pricing'];
      if (!mounted) return;
      final minimum = double.tryParse((pricing is Map ? pricing['minTopupUsd'] : null)?.toString() ?? '') ?? 1;
      final maximum = double.tryParse((pricing is Map ? pricing['maxTopupUsd'] : null)?.toString() ?? '') ?? 10000;
      setState(() {
        _minTopupUsd = minimum > 0 ? minimum : 1;
        _maxTopupUsd = maximum >= _minTopupUsd ? maximum : 10000;
        final current = double.tryParse(_amountController.text) ?? 5;
        if (current < _minTopupUsd || current > _maxTopupUsd) _amountController.text = _minTopupUsd.toStringAsFixed(2);
      });
    }).catchError((_) {});
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) =>
      value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  double get _selectedUsd => double.tryParse(_amountController.text.trim()) ?? 0;
  bool get _validAmount => _selectedUsd.isFinite && (_selectedUsd * 100).roundToDouble() == _selectedUsd * 100 && _selectedUsd >= _minTopupUsd && _selectedUsd <= _maxTopupUsd;

  Future<void> _createLocalPayment() async {
    if (_creating || !_validAmount) return;
    if (_localPhone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter the phone number linked to your mobile wallet.')));
      return;
    }
    setState(() => _creating = true);
    try {
      final auth = context.read<AuthService>();
      final result = await NumelixaRepository().createLocalPayment(
        token: auth.accessToken!,
        amountUsd: _selectedUsd,
        method: _localMethod,
        phone: _localPhone.text.trim(),
      );
      if (result['ok'] != true || (result['orderId'] ?? '').toString().isEmpty) {
        throw ApiException((result['error'] ?? 'Unable to send the payment request.').toString());
      }
      final orderId = result['orderId'].toString();
      final status = (result['status'] ?? 'pending').toString();
      if (status == 'paid') {
        if (mounted) {
          setState(() { _balance = NumelixaRepository().balance(token: auth.accessToken!); _transactions = NumelixaRepository().transactions(token: auth.accessToken!); });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment confirmed. Your USD wallet has been updated.')));
          await _showOfficialReceipt(orderId);
        }
        return;
      }
      if (status == 'failed') throw ApiException((result['message'] ?? 'Payment was declined. Check your mobile wallet and try again.').toString());
      _pendingLocalOrderId = orderId;
      _localPaymentTimer?.cancel();
      _localPaymentTimer = Timer.periodic(const Duration(seconds: 7), (_) => _verifyLocalPayment());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment request sent. Approve it on your phone; Numelixa will check the result automatically.')));
      await _verifyLocalPayment();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to start payment. Check your connection and try again.')));
    } finally { if (mounted) setState(() => _creating = false); }
  }

  Future<void> _verifyLocalPayment() async {
    final orderId = _pendingLocalOrderId;
    final token = context.read<AuthService>().accessToken;
    if (orderId == null || orderId.isEmpty || token == null || _checkingLocalPayment) return;
    _checkingLocalPayment = true;
    try {
      final repo = NumelixaRepository();
      final result = await repo.verifyLocalPayment(token: token, orderId: orderId);
      if (result['ok'] == true && result['status'] == 'paid') {
        _localPaymentTimer?.cancel();
        _localPaymentTimer = null;
        _pendingLocalOrderId = null;
        if (mounted) {
          setState(() {
            _balance = repo.balance(token: token);
            _transactions = repo.transactions(token: token);
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Local payment confirmed. Your wallet has been refreshed.')));
          await _showOfficialReceipt(orderId);
        }
      } else if (result['ok'] == true && result['status'] == 'failed') {
        _localPaymentTimer?.cancel();
        _localPaymentTimer = null;
        _pendingLocalOrderId = null;
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The local payment was not completed. You can try again.')));
      }
    } catch (_) {
      // Keep the order pending and retry on the next timer tick or app resume.
    } finally {
      _checkingLocalPayment = false;
    }
  }

  Widget _receiptLine(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 112, child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w800))), Expanded(child: Text(value.isEmpty ? '—' : value, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF102A4C), fontSize: 10, fontWeight: FontWeight.w800)))]));
  Future<void> _showOfficialReceipt(String reference) async {
    final token = context.read<AuthService>().accessToken;
    if (token == null || reference.trim().isEmpty || !mounted) return;
    try {
      final response = await NumelixaRepository().walletReceipt(token: token, reference: reference.trim());
      final raw = response['receipt'];
      if (response['ok'] != true || raw is! Map) throw const ApiException('The verified receipt is not available yet.');
      if (!mounted) return;
      await showPaymentReceipt(context, receipt: Map<String, dynamic>.from(raw), fallbackReference: reference);
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your payment is confirmed, but the official receipt could not be loaded. Open Wallet history and try again.')));
    }
  }


  Future<void> _createEthiopiaPayment() async {
    if (_creating || !_validAmount) return;
    final phone = _ethiopiaPhone.text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^251'), '0');
    if (!RegExp(r'^0[79][0-9]{8}$').hasMatch(phone)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter your Ethiopian payment phone number as 09XXXXXXXX.')));
      return;
    }
    setState(() => _creating = true);
    try {
      final token = context.read<AuthService>().accessToken!;
      final result = await NumelixaRepository().createEthiopiaPayment(
        token: token, amountUsd: _selectedUsd, method: _ethiopiaMethod,
        payerPhone: phone, payerName: _ethiopiaPayerName.text.trim(),
      );
      if (result['ok'] != true || (result['orderId'] ?? '').toString().isEmpty) {
        throw ApiException((result['error'] ?? 'Unable to create the Ethiopia payment order.').toString());
      }
      _ethiopiaPaymentTimer?.cancel();
      setState(() { _ethiopiaOrder = Map<String, dynamic>.from(result); _ethiopiaSwipe = 0; });
      _ethiopiaPaymentTimer = Timer.periodic(const Duration(seconds: 5), (_) => _verifyEthiopiaPayment());
      await _verifyEthiopiaPayment();
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to prepare the Ethiopia payment. Please retry.')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _verifyEthiopiaPayment() async {
    final orderId = (_ethiopiaOrder?['orderId'] ?? '').toString();
    final token = context.read<AuthService>().accessToken;
    if (orderId.isEmpty || token == null || _checkingEthiopiaPayment || _ethiopiaOrder?['status'] == 'paid') return;
    _checkingEthiopiaPayment = true;
    try {
      final repo = NumelixaRepository();
      final result = await repo.ethiopiaPaymentStatus(token: token, orderId: orderId);
      if (result['ok'] == true && result['status'] == 'paid') {
        _ethiopiaPaymentTimer?.cancel();
        _ethiopiaPaymentTimer = null;
        if (mounted) {
          setState(() { _ethiopiaOrder = {...?_ethiopiaOrder, 'status': 'paid'}; _balance = repo.balance(token: token); _transactions = repo.transactions(token: token); });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment verified. Your wallet has been credited.')));
          _showOfficialReceipt(orderId);
        }
      } else if (result['ok'] == true && (result['status'] == 'rejected' || result['status'] == 'failed')) {
        _ethiopiaPaymentTimer?.cancel();
        _ethiopiaPaymentTimer = null;
        if (mounted) setState(() { _ethiopiaOrder = {...?_ethiopiaOrder, 'status': result['status']}; });
      } else if (mounted && result['verification'] is Map) {
        setState(() { _ethiopiaOrder = {...?_ethiopiaOrder, 'verification': result['verification']}; });
      }
    } catch (_) {
      // Keep checking. A temporary network failure never marks a payment as paid.
    } finally {
      _checkingEthiopiaPayment = false;
    }
  }

  Future<void> _createDeposit(Map<String, dynamic> asset) async {
    if (_currency == null || _network == null || _creating || !_validAmount) return;
    setState(() => _creating = true);
    try {
      final auth = context.read<AuthService>();
      final result = await NumelixaRepository().createDeposit(
        token: auth.accessToken!, amountUsd: _selectedUsd, currency: _currency!, network: _network!);
      if (!mounted) return;
      if (result['ok'] != true || (result['address'] ?? '').toString().isEmpty) {
        throw ApiException((result['error'] ?? 'Unable to create a deposit request.').toString());
      }
      await _showDeposit(result);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to create the deposit request. Please retry.')));
    } finally {
      if (mounted) setState(() { _creating = false; _load(); });
    }
  }

  Future<void> _checkCryptoDeposit(String orderId) async {
    final token = context.read<AuthService>().accessToken;
    if (token == null || orderId.isEmpty || _checkingDepositStatus || _depositStatus == 'paid') return;
    _checkingDepositStatus = true;
    try {
      final repo = NumelixaRepository();
      final result = await repo.depositStatus(token: token, orderId: orderId);
      final status = (result['status'] ?? 'pending').toString();
      if (!mounted) return;
      if (status == 'paid') {
        _depositStatus = 'paid';
        _depositStatusTimer?.cancel();
        setState(() { _balance = repo.balance(token: token); _transactions = repo.transactions(token: token); });
        _updateDepositDialog?.call(() {});
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        await _showOfficialReceipt(orderId);
      } else {
        _depositStatus = status;
        _updateDepositDialog?.call(() {});
      }
    } catch (_) {
      // A temporary status lookup failure is never treated as payment success.
    } finally {
      _checkingDepositStatus = false;
    }
  }

  Future<void> _showDeposit(Map<String, dynamic> payment) async {
    final address = (payment['address'] ?? '').toString();
    final amount = (payment['amount'] ?? '').toString();
    final currency = (payment['currency'] ?? _currency ?? '').toString().toUpperCase();
    final network = (payment['networkName'] ?? payment['network'] ?? _network ?? '').toString();
    final orderId = (payment['orderId'] ?? '').toString();
    final expiresAt = DateTime.tryParse((payment['expiresAt'] ?? '').toString());
    _depositTimer?.cancel();
    _depositStatusTimer?.cancel();
    _depositStatus = 'pending';
    void refreshTimer() {
      final left = expiresAt == null ? 0 : expiresAt.difference(DateTime.now()).inSeconds;
      final next = left.clamp(0, 86400);
      if (mounted && next != _depositSecondsLeft) {
        setState(() => _depositSecondsLeft = next);
        _updateDepositDialog?.call(() {});
      }
    }
    refreshTimer();
    _depositTimer = Timer.periodic(const Duration(seconds: 1), (_) => refreshTimer());
    _depositStatusTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkCryptoDeposit(orderId));
    String amountText() => amount;
    String timerText() => '${(_depositSecondsLeft ~/ 60).toString().padLeft(2, '0')}:${(_depositSecondsLeft % 60).toString().padLeft(2, '0')}';
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, setDialogState) {
      _updateDepositDialog = setDialogState;
      return AlertDialog(
        backgroundColor: const Color(0xFF081B36),
        title: const Text('Complete your deposit'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Send exactly $amount $currency on $network. Sending a different amount or network may delay crediting.', style: const TextStyle(color: Color(0xFFA7B7D0), height: 1.45)),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF101D32), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF263B5A))), child: Column(children: [
            const Text('TIME LEFT TO PAY', style: TextStyle(color: Color(0xFF91A8C4), fontSize: 11, letterSpacing: 1.2)),
            const SizedBox(height: 4),
            Text(expiresAt == null ? 'Check expiry in payment details' : timerText(), style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: _depositSecondsLeft <= 120 ? const Color(0xFFFFBA72) : AppTheme.mint)),
            if (expiresAt != null && _depositSecondsLeft == 0) const Text('This request may have expired. Check its status before creating another.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFFFBA72), fontSize: 12)),
          ])),
          const SizedBox(height: 14),
          const Text('Exact amount', style: TextStyle(fontWeight: FontWeight.w700)),
          SelectableText('${amountText()} $currency', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.mint)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: amountText()));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exact amount copied.')));
          }, icon: const Icon(Icons.copy_rounded), label: const Text('Copy exact amount'))),
          const SizedBox(height: 8),
          const Text('Scan to copy deposit address', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Center(child: Screenshot(controller: _qrScreenshot, child: Container(color: Colors.white, padding: const EdgeInsets.all(12), child: QrImageView(data: address, size: 210, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.H)))),
          Center(child: TextButton.icon(onPressed: () async {
            try {
              final bytes = await _qrScreenshot.capture(pixelRatio: 3);
              if (bytes == null) throw Exception('QR image unavailable');
              await Gal.putImageBytes(bytes, name: 'numelixa-deposit-${orderId.isEmpty ? 'qr' : orderId}.png');
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR code saved to your gallery.')));
            } catch (_) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save QR code. Please allow photo access and try again.')));
            }
          }, icon: const Icon(Icons.download_rounded), label: const Text('Download QR code'))),
          const Text('Deposit address', style: TextStyle(fontWeight: FontWeight.w700)),
          SelectableText(address, style: const TextStyle(color: AppTheme.cyan, height: 1.4)),
          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () async {
            await Clipboard.setData(ClipboardData(text: address));
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deposit address copied.')));
          }, icon: const Icon(Icons.copy_rounded), label: const Text('Copy address'))),
          if ((payment['memo'] ?? '').toString().isNotEmpty) ...[
            const Text('Memo / tag', style: TextStyle(fontWeight: FontWeight.w700)),
            SelectableText((payment['memo']).toString()),
          ],
          const SizedBox(height: 8),
          Text('Request: $orderId', style: const TextStyle(fontSize: 11, color: Color(0xFF91A8C4))),
          const Text('The wallet is credited only after the payment is confirmed.', style: TextStyle(fontSize: 12, color: Color(0xFF91A8C4))),
          if (_depositStatus == 'paid') const Padding(padding: EdgeInsets.only(top: 10), child: Text('Payment verified · Your wallet has been credited.', style: TextStyle(color: AppTheme.mint, fontWeight: FontWeight.w900))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
          FilledButton(
            onPressed: _depositStatus == 'paid'
              ? () async { Navigator.of(dialogContext).pop(); await _showOfficialReceipt(orderId); }
              : _checkingDepositStatus ? null : () => _checkCryptoDeposit(orderId),
            child: Text(_depositStatus == 'paid' ? 'View official payment receipt' : _checkingDepositStatus ? 'Checking payment…' : 'Check payment'),
          ),
        ],
      );
    }));
    _depositTimer?.cancel();
    _depositStatusTimer?.cancel();
    _updateDepositDialog = null;
  }

  Widget _localPaymentBadge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(.14),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withOpacity(.35)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .15)),
  );

  Widget _localPaymentLogo(String method) {
    final normalized = method.toLowerCase();
    final label = normalized == 'waafi' ? 'W' : normalized == 'edahab' ? 'eD' : 'P';
    final colors = normalized == 'waafi'
        ? const [Color(0xFF10B8A5), Color(0xFF087183)]
        : normalized == 'edahab'
            ? const [Color(0xFFFFD95B), Color(0xFFF29B25)]
            : const [Color(0xFF2C7BFF), Color(0xFF663CFF)];
    return Container(
      width: 28, height: 28, alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        gradient: LinearGradient(colors: colors),
      ),
      child: Text(label, style: TextStyle(
        color: normalized == 'edahab' ? const Color(0xFF17213A) : Colors.white,
        fontSize: 10, fontWeight: FontWeight.w900,
      )),
    );
  }

  Widget _coinLogo(Map<String, dynamic> asset) {
    final coin = (asset['coin'] ?? '').toString().toLowerCase();
    final primary = 'https://raw.githubusercontent.com/spothq/cryptocurrency-icons/master/128/color/$coin.png';
    final fallback = 'https://assets.coincap.io/assets/icons/$coin@2x.png';
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        primary, width: 25, height: 25, fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Image.network(
          fallback, width: 25, height: 25, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.currency_bitcoin_rounded, size: 23, color: AppTheme.cyan),
        ),
      ),
    );
  }

  Widget _networkLogo(String network) {
    final key = network.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const aliases = <String, String>{
      'eth':'ethereum','erc20':'ethereum','ethereum':'ethereum',
      'trc20':'tron','tron':'tron','bep20':'binance','bsc':'binance','bnbsmartchain':'binance',
      'polygon':'polygon','matic':'polygon','sol':'solana','solana':'solana',
      'avaxc':'avalanche','avalanchec':'avalanche','arbitrum':'arbitrum','arb':'arbitrum',
      'optimism':'optimism','op':'optimism','ton':'ton','bitcoin':'bitcoin','btc':'bitcoin',
      'litecoin':'litecoin','ltc':'litecoin','doge':'dogecoin','dogecoin':'dogecoin',
      'base':'coinbase','xrp':'xrpl','ripple':'xrpl','aptos':'aptos','sui':'sui',
    };
    final slug = aliases[key] ?? aliases.entries.firstWhere((e) => key.contains(e.key), orElse: () => const MapEntry('', '')).value;
    final url = slug.isEmpty ? '' : 'https://cdn.simpleicons.org/$slug';
    return Container(
      width: 27, height: 27, padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF102844), borderRadius: BorderRadius.circular(9), border: Border.all(color: const Color(0xFF23415F))),
      child: url.isEmpty
        ? const Icon(Icons.hub_rounded, size: 17, color: AppTheme.cyan)
        : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.hub_rounded, size: 17, color: AppTheme.cyan)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wallet')),
    body: RefreshIndicator(onRefresh: () async => setState(_load), child: ListView(
      padding: const EdgeInsets.all(14), children: [
        FutureBuilder<Map<String, dynamic>>(future: _balance, builder: (context, snapshot) {
          final value = snapshot.data?['balance'];
          return Container(
            padding: const EdgeInsets.all(21),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF174477), Color(0xFF0C2749), Color(0xFF07162B)]),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2C659B)),
              boxShadow: const [BoxShadow(color: Color(0x331677FF), blurRadius: 26, offset: Offset(0, 12))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: const Color(0x2237DFFF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.account_balance_wallet_rounded, color: AppTheme.cyan)),
                const SizedBox(width: 11),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NUMELIXA WALLET', style: TextStyle(color: Color(0xFF8FDFFF), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                  SizedBox(height: 4),
                  Text('Available balance', style: TextStyle(color: Color(0xFFB5C9E2), fontSize: 12, fontWeight: FontWeight.w600)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: const Color(0x2237DFFF), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x554FCBFF))), child: const Text('USD', style: TextStyle(color: Color(0xFFB9EFFF), fontSize: 10, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 19),
              Text(snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : value == null ? '—' : '\$${(double.tryParse(value.toString()) ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1.1)),
              if (snapshot.hasError) Padding(padding: const EdgeInsets.only(top: 7), child: Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFFFF788C), fontSize: 11))),
            ]),
          );
        }),
        const SizedBox(height: 8),
        const Text('Add funds', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('1. Choose how much to add.  2. Choose how to pay.  3. Follow the payment instructions.', style: TextStyle(color: Color(0xFF91A8C4), height: 1.5)),
        const SizedBox(height: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('1. Enter your top-up amount', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 10),
            TextField(controller: _amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true), enabled: !_creating, onChanged: (_) => setState(() {}), decoration: InputDecoration(prefixText: '\$ ', suffixText: 'USD', labelText: 'Amount you want to add', hintText: _minTopupUsd.toStringAsFixed(2), helperText: 'Minimum \$' + _minTopupUsd.toStringAsFixed(2) + ' · Maximum \$' + _maxTopupUsd.toStringAsFixed(2), errorText: _validAmount ? null : 'Enter an amount within the allowed limits.')),
            const SizedBox(height: 12),
            const Text('Quick amounts', style: TextStyle(color: Color(0xFF91A8C4), fontSize: 11, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final preset in <double>[5, 10, 25, 50].where((value) => value >= _minTopupUsd && value <= _maxTopupUsd))
                ChoiceChip(
                  label: Text('\$${preset.toStringAsFixed(0)}'),
                  selected: (_selectedUsd - preset).abs() < 0.001,
                  onSelected: _creating ? null : (selected) { if (selected) { _amountController.text = preset.toStringAsFixed(2); setState(() {}); } },
                  selectedColor: const Color(0xFF123C62),
                  backgroundColor: const Color(0xFF091A30),
                  labelStyle: TextStyle(color: (_selectedUsd - preset).abs() < 0.001 ? AppTheme.cyan : const Color(0xFFA7B7D0), fontWeight: FontWeight.w800, fontSize: 12),
                  side: BorderSide(color: (_selectedUsd - preset).abs() < 0.001 ? AppTheme.cyan : const Color(0xFF29435F)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
            ]),
            const SizedBox(height: 10),
            const SizedBox(height: 8),
            Text('Your top-up: \$' + _selectedUsd.toStringAsFixed(2) + ' USD', style: const TextStyle(color: Color(0xFFA7B7D0), fontSize: 12)),
          ]))),
          if (_localPaymentsOpen || _ethiopiaPaymentsOpen || _paymentMethod == 'crypto') ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('2. Choose payment type', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 9),
              Row(children: [
                Expanded(child: _PaymentChoiceCard(selected: _paymentMethod == 'crypto', icon: Icons.currency_bitcoin_rounded, title: 'Crypto Payment', subtitle: 'USDT and other supported coins', onTap: () => setState(() { _paymentMethod = 'crypto'; _cryptoStep = false; }))),
                const SizedBox(width: 10), Expanded(child: _PaymentChoiceCard(selected: _paymentMethod == 'local', enabled: _localPaymentsOpen, icon: Icons.account_balance_wallet_rounded, title: 'Somalia', subtitle: _localPaymentsOpen ? 'Waafi · EVC · ZAAD · SAHAL · eDahab · Premier' : 'Somalia mobile money is currently closed', onTap: () => setState(() { _paymentMethod = 'local'; _cryptoStep = false; }))),
              ]),
              if (_ethiopiaPaymentsOpen) ...[const SizedBox(height: 10), _PaymentChoiceCard(selected: _paymentMethod == 'ethiopia', icon: Icons.account_balance_rounded, title: 'Ethiopia Payment', subtitle: 'eBirr and Ethiopian bank transfers', onTap: () => setState(() { _paymentMethod = 'ethiopia'; _cryptoStep = false; }))],
              const SizedBox(height: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF091A30), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFF243A56))), child: Row(children: [
                Image.network('https://cdn.simpleicons.org/visa/1A1F71', width: 34, height: 24, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('VISA', style: TextStyle(fontWeight: FontWeight.w900))),
                const SizedBox(width: 8),
                Image.network('https://cdn.simpleicons.org/mastercard/EB001B', width: 30, height: 24, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Text('MC', style: TextStyle(fontWeight: FontWeight.w900))),
                const SizedBox(width: 12),
                const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Visa / Mastercard', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 3),
                  Text('Card payments are coming soon', style: TextStyle(fontSize: 11, color: Color(0xFF91A8C4))),
                ])),
                const Text('COMING SOON', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Color(0xFFFFCF83))),
              ])),
              if (_paymentMethod == 'crypto' && !_cryptoStep) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _creating ? null : () => setState(() { _cryptoStep = true; _currency = null; _network = null; }),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Continue to coins & networks'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: AppTheme.cyan, foregroundColor: const Color(0xFF031021), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                ),
              ],
            ]))),
          ],
          if (_localPaymentsOpen && _paymentMethod == 'local') ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('3. Local wallet details', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppTheme.cyan)),
              const SizedBox(height: 7),
              Text('Amount: \$' + _selectedUsd.toStringAsFixed(2) + ' USD', style: const TextStyle(color: Color(0xFFA7B7D0), fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _localMethod,
                decoration: const InputDecoration(labelText: 'Choose mobile wallet'),
                items: [
                  DropdownMenuItem(value: 'waafi', child: Row(children: [_localPaymentLogo('waafi'), const SizedBox(width: 8), const Expanded(child: Text('Waafi · EVC Plus · ZAAD · SAHAL'))])),
                  DropdownMenuItem(value: 'edahab', child: Row(children: [_localPaymentLogo('edahab'), const SizedBox(width: 8), const Expanded(child: Text('eDahab'))])),
                  DropdownMenuItem(value: 'premier', child: Row(children: [_localPaymentLogo('premier'), const SizedBox(width: 8), const Expanded(child: Text('Premier Wallet'))])),
                ],
                onChanged: _creating ? null : (value) { if (value != null) setState(() => _localMethod = value); },
              ),
              if (_localMethod == 'waafi') ...[
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  _localPaymentBadge('WAAFI', const Color(0xFF42DCC7)),
                  _localPaymentBadge('EVC PLUS', const Color(0xFF6DB5FF)),
                  _localPaymentBadge('ZAAD', const Color(0xFFC3A2FF)),
                  _localPaymentBadge('SAHAL', const Color(0xFFFFD18A)),
                ]),
              ],
              const SizedBox(height: 10),
              TextField(controller: _localPhone, enabled: !_creating, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Mobile wallet phone number', hintText: '+252 6X XXX XXXX', prefixIcon: Icon(Icons.phone_android_rounded))),
              const SizedBox(height: 8),
              const Text('A payment request will be sent to your phone. Approve it there, then this screen checks the payment automatically.', style: TextStyle(fontSize: 12, color: Color(0xFF91A8C4), height: 1.45)),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: _creating || !_validAmount ? null : _createLocalPayment, icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.lock_rounded), label: Text(_creating ? 'Sending payment request…' : 'Pay \$' + _selectedUsd.toStringAsFixed(2) + ' USD')),
              if (_pendingLocalOrderId != null) Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton.icon(onPressed: _checkingLocalPayment ? null : _verifyLocalPayment, icon: const Icon(Icons.refresh_rounded), label: Text(_checkingLocalPayment ? 'Checking payment…' : 'Check payment status'))),
            ]))),
          ],
          if (_paymentMethod == 'ethiopia' && _ethiopiaPaymentsOpen) ...[
            const SizedBox(height: 12),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Ethiopia · Secure local payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.cyan)),
              const SizedBox(height: 6),
              Text('Selected amount: \$' + _selectedUsd.toStringAsFixed(2) + ' USD', style: const TextStyle(color: Color(0xFFA7B7D0), fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _ethiopiaMethods.containsKey(_ethiopiaMethod) && (_ethiopiaMethods[_ethiopiaMethod] is Map) && _ethiopiaMethods[_ethiopiaMethod]['open'] == true ? _ethiopiaMethod : null,
                decoration: const InputDecoration(labelText: 'Payment service'),
                items: _ethiopiaMethods.entries.where((entry) => entry.value is Map && entry.value['open'] == true && (entry.value['receiver'] ?? '').toString().trim().isNotEmpty).map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text((entry.value['name'] ?? entry.key).toString()))).toList(),
                onChanged: _creating ? null : (value) { if (value != null) setState(() => _ethiopiaMethod = value); },
              ),
              const SizedBox(height: 10),
              TextField(controller: _ethiopiaPayerName, enabled: !_creating, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Payment account name (optional)', hintText: 'Enter the name shown in your payment SMS')),
              const SizedBox(height: 10),
              TextField(controller: _ethiopiaPhone, enabled: !_creating, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Your Ethiopian payment phone', hintText: '09XXXXXXXX', prefixIcon: Icon(Icons.phone_android_rounded))),
              if (_ethiopiaOrder == null) ...[
                const SizedBox(height: 14),
                Text('Swipe to prepare payment · \$' + _selectedUsd.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w800)),
                SliderTheme(data: SliderTheme.of(context).copyWith(activeTrackColor: AppTheme.cyan, inactiveTrackColor: const Color(0xFF243A56), thumbColor: AppTheme.mint, overlayColor: AppTheme.cyan.withOpacity(.14), trackHeight: 8, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11), overlayShape: const RoundSliderOverlayShape(overlayRadius: 20)), child: Slider(value: _ethiopiaSwipe, min: 0, max: 1, onChanged: _creating ? null : (value) => setState(() => _ethiopiaSwipe = value), onChangeEnd: (value) { if (value >= .98) _createEthiopiaPayment(); })),
                const Text('Once the order is created, SMS matching runs automatically. No manual confirmation is required when your payment arrives.', style: TextStyle(color: Color(0xFF91A8C4), fontSize: 12, height: 1.45)),
              ] else ...[
                const Divider(height: 24),
                Container(
                  padding: const EdgeInsets.all(17),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD7E0EA)), boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 18, offset: Offset(0, 7))]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: const Color(0xFF102A4C), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.verified_rounded, color: Colors.white, size: 22)),
                      const SizedBox(width: 9),
                      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('NUMELIXA', style: TextStyle(color: Color(0xFF102A4C), fontWeight: FontWeight.w900, letterSpacing: 1.4)), Text('PAYMENT ACKNOWLEDGEMENT', style: TextStyle(color: Color(0xFF64748B), fontSize: 9, letterSpacing: 1.1, fontWeight: FontWeight.w800))])),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFFFF3D8), borderRadius: BorderRadius.circular(30)), child: const Text('PENDING', style: TextStyle(color: Color(0xFF98620B), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .7))),
                    ]),
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),
                    const Text('PAYMENT SUBMITTED', style: TextStyle(color: Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                    Text(((_ethiopiaOrder!['amountEtb'] ?? '0').toString()) + ' ETB', style: const TextStyle(color: Color(0xFF102A4C), fontSize: 29, fontWeight: FontWeight.w900)),
                    Text('USD ' + ((_ethiopiaOrder!['amountUsd'] ?? _selectedUsd).toString()), style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _receiptLine('PAYMENT METHOD', (_ethiopiaOrder!['methodName'] ?? 'Ethiopia local payment').toString()),
                    _receiptLine('SENDER NUMBER', (_ethiopiaOrder!['payerPhone'] ?? _ethiopiaPhone.text).toString()),
                    _receiptLine('RECEIVER NUMBER', (_ethiopiaOrder!['receiverPhone'] ?? '').toString()),
                    _receiptLine('REFERENCE', (_ethiopiaOrder!['orderId'] ?? '').toString()),
                    _receiptLine('DATE', DateTime.now().toLocal().toString().split('.').first),
                    const Divider(height: 22, color: Color(0xFFE2E8F0)),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('NUMELIXA REVIEW SEAL', style: TextStyle(color: Color(0xFF64748B), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .8)),
                        const SizedBox(height: 5),
                        Text(_ethiopiaOrder!['status'] == 'paid' ? 'Verified and credited' : 'Awaiting automatic SMS verification', style: const TextStyle(color: Color(0xFF102A4C), fontWeight: FontWeight.w800, fontSize: 12)),
                        const Text('This acknowledgement is not a final payment confirmation until verification succeeds.', style: TextStyle(color: Color(0xFF64748B), fontSize: 9, height: 1.4)),
                      ])),
                      Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF1677FF), width: 2.2), color: const Color(0xFFEFF6FF)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.verified_user_rounded, color: Color(0xFF1677FF), size: 25), Text('NUMELIXA', style: TextStyle(color: Color(0xFF1677FF), fontSize: 7, fontWeight: FontWeight.w900)), Text('SEAL', style: TextStyle(color: Color(0xFF1677FF), fontSize: 7, fontWeight: FontWeight.w900))])),
                    ]),
                    const SizedBox(height: 12),
                    Center(child: QrImageView(data: (_ethiopiaOrder!['orderId'] ?? '').toString(), size: 62, backgroundColor: Colors.white)),
                    const Center(child: Text('KEEP THIS PAYMENT REFERENCE', style: TextStyle(color: Color(0xFF64748B), fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .8))),
                  ]),
                ),
                const SizedBox(height: 14),
                Text((_ethiopiaOrder!['methodName'] ?? 'Ethiopia payment').toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(((_ethiopiaOrder!['amountEtb'] ?? '').toString()) + ' ETB', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: AppTheme.mint)),
                SelectableText('Receiver: ' + (_ethiopiaOrder!['receiverPhone'] ?? '').toString(), style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w800)),
                if ((_ethiopiaOrder!['instructions'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_ethiopiaOrder!['instructions'].toString(), style: const TextStyle(color: Color(0xFFA7B7D0), height: 1.5))),
                const SizedBox(height: 12),
                Row(children: [Icon(_ethiopiaOrder!['status'] == 'paid' ? Icons.check_circle_rounded : Icons.sync_rounded, color: _ethiopiaOrder!['status'] == 'paid' ? AppTheme.mint : AppTheme.cyan), const SizedBox(width: 8), Expanded(child: Text(_ethiopiaOrder!['status'] == 'paid' ? 'Payment verified · Wallet credited' : 'Waiting for payment SMS verification', style: const TextStyle(fontWeight: FontWeight.w800)))]),
                if (_ethiopiaOrder!['verification'] is Map && _ethiopiaOrder!['status'] != 'paid') Padding(padding: const EdgeInsets.only(top: 8), child: Text('Latest check: ' + ((_ethiopiaOrder!['verification'] as Map)['reason'] ?? 'Checking').toString().replaceAll('_', ' '), style: const TextStyle(color: Color(0xFFFFCA78), fontSize: 12))),
                if (_ethiopiaOrder!['status'] == 'paid') FilledButton.icon(onPressed: () => _showOfficialReceipt((_ethiopiaOrder!['orderId'] ?? '').toString()), icon: const Icon(Icons.receipt_long_rounded), label: const Text('View official payment receipt')),
                if (_ethiopiaOrder!['status'] == 'paid') TextButton.icon(onPressed: () => setState(() { _ethiopiaOrder = null; _load(); }), icon: const Icon(Icons.check_circle_outline), label: const Text('Start another top-up')),
              ],
            ]))),
          ],
          if (_paymentMethod == 'crypto' && _cryptoStep) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _creating ? null : () => setState(() { _cryptoStep = false; }), icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back to payment options'))),
            FutureBuilder<Map<String, dynamic>>(future: _assets, builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
              if (snapshot.hasError) return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFFFF788C))),
                TextButton(onPressed: () => setState(_load), child: const Text('Retry payment options')),
              ])));
              final assets = _asMaps(snapshot.data?['assets']);
              if (assets.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No deposit assets are available right now.')));
              final visibleAssets = assets.where((asset) => ((asset['coin'] ?? '').toString() + ' ' + (asset['name'] ?? '').toString()).toLowerCase().contains(_cryptoSearch.text.trim().toLowerCase())).toList();
              final selectedAsset = assets.firstWhere((asset) => asset['coin'] == _currency, orElse: () => assets.first);
              final coin = (selectedAsset['coin'] ?? '').toString();
              final networks = _asMaps(selectedAsset['networks']);
              if (_currency != coin) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() { _currency = coin; _network = null; }); });
              if (networks.isNotEmpty && !networks.any((network) => network['network'] == _network)) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _network = (networks.first['network'] ?? '').toString()); });
              return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('3. Choose cryptocurrency', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                TextField(controller: _cryptoSearch, decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: 'Search Bitcoin, USDT, Ethereum…', suffixIcon: _cryptoSearch.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _cryptoSearch.clear()))), onChanged: (_) => setState(() {})),
                const SizedBox(height: 10),
                if (visibleAssets.isEmpty)
                  const Padding(padding: EdgeInsets.all(12), child: Text('No matching cryptocurrency. Try another name or symbol.', style: TextStyle(color: Color(0xFF91A8C4))))
                else
                  GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: visibleAssets.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisExtent: 70, crossAxisSpacing: 9, mainAxisSpacing: 9), itemBuilder: (context, index) {
                    final asset = visibleAssets[index];
                    final symbol = (asset['coin'] ?? '').toString();
                    final name = (asset['name'] ?? symbol).toString();
                    final selected = coin == symbol;
                    final networkCount = _asMaps(asset['networks']).length;
                    return Material(color: selected ? const Color(0xFF10385A) : const Color(0xFF091A30), borderRadius: BorderRadius.circular(14), child: InkWell(borderRadius: BorderRadius.circular(14), onTap: () => setState(() { _currency = symbol; _network = null; }), child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: selected ? AppTheme.cyan : const Color(0xFF243A56), width: selected ? 1.5 : 1)), child: Row(children: [_coinLogo(asset), const SizedBox(width: 8), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(symbol, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)), Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 10)), Text(networkCount.toString() + ' networks', style: const TextStyle(color: AppTheme.cyan, fontSize: 9))])), if (selected) const Icon(Icons.check_circle_rounded, color: AppTheme.cyan, size: 17)]))));
                  }),
                const SizedBox(height: 12),
                const Text('4. Choose network', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(initialValue: networks.any((network) => network['network'] == _network) ? _network : null, decoration: const InputDecoration(), items: networks.map((network) => DropdownMenuItem<String>(value: (network['network'] ?? '').toString(), child: Row(mainAxisSize: MainAxisSize.min, children: [_networkLogo((network['networkName'] ?? network['network'] ?? '').toString()), const SizedBox(width: 9), Flexible(child: Text((network['networkName'] ?? network['network'] ?? '').toString(), overflow: TextOverflow.ellipsis))]))).toList(), onChanged: (value) => setState(() => _network = value)),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: _creating || _network == null || !_validAmount ? null : () => _createDeposit(selectedAsset), icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_card_rounded), label: Text(_creating ? 'Creating deposit…' : 'Create deposit request')),
              ])));
            }),
          ],
        ]),
        const SizedBox(height: 20),
        const Text('Transaction history', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(future: _transactions, builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
          final items = _asMaps(snapshot.data?['transactions']);
          if (items.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No transactions found yet.')));
          return Column(children: items.map((item) {
            final isCredit = item['type'] == 'credit';
            final amount = double.tryParse((item['amountUsd'] ?? 0).toString()) ?? 0;
            final reference = (item['reference'] ?? '').toString();
            final date = (item['createdAt'] ?? '').toString();
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: isCredit && reference.isNotEmpty ? () => _showOfficialReceipt(reference) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                  child: Row(children: [
                    Container(width: 44, height: 44, decoration: BoxDecoration(
                      gradient: LinearGradient(colors: isCredit ? const [Color(0xFF087D75), Color(0xFF12B99B)] : const [Color(0xFF285B9E), Color(0xFF5140B8)]),
                      borderRadius: BorderRadius.circular(14),
                    ), child: Icon(isCredit ? Icons.south_west_rounded : Icons.north_east_rounded, color: Colors.white, size: 21)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((item['description'] ?? item['type'] ?? 'Transaction').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(date, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 10)),
                      if (isCredit && reference.isNotEmpty) const Padding(padding: EdgeInsets.only(top: 4), child: Text('Tap to view official receipt', style: TextStyle(color: AppTheme.cyan, fontSize: 9, fontWeight: FontWeight.w800))),
                    ])),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text((isCredit ? '+' : '−') + 'USD ' + amount.toStringAsFixed(2), style: TextStyle(color: isCredit ? AppTheme.mint : const Color(0xFFFFA5B4), fontWeight: FontWeight.w900, fontSize: 12)),
                      const SizedBox(height: 5),
                      Text((item['type'] ?? 'transaction').toString().toUpperCase(), style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: .7)),
                    ]),
                  ]),
                ),
              ),
            );
          }).toList());
        }),
      ],
    )),
  );
}

class _PaymentChoiceCard extends StatelessWidget {
  const _PaymentChoiceCard({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap, this.enabled = true});
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: !enabled ? const Color(0xFF071426) : selected ? const Color(0xFF102D4E) : const Color(0xFF08182D),
          gradient: selected ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF153F68), Color(0xFF0B203A)]) : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? AppTheme.cyan : const Color(0xFF203A57), width: selected ? 1.5 : 1),
          boxShadow: selected ? const [BoxShadow(color: Color(0x2237DFFF), blurRadius: 18, offset: Offset(0, 6))] : const [],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 39, height: 39, decoration: BoxDecoration(color: selected ? const Color(0x3337DFFF) : const Color(0xFF10233B), borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: !enabled ? const Color(0xFF60748D) : selected ? AppTheme.cyan : const Color(0xFFA7B7D0), size: 21)),
            const Spacer(),
            if (selected) const Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 18),
          ]),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, height: 1.35, color: Color(0xFF91A8C4))),
        ]),
      ),
    ),
  );
}

class _NotificationsPage extends StatelessWidget {
  const _NotificationsPage();
  @override
  Widget build(BuildContext context) => _ProtectedListPage(
    title: 'Notifications',
    load: (repo, token) => repo.notifications(token: token),
    listKey: 'notifications',
    empty: 'You are all caught up.',
    itemTitle: (item) => (item['title'] ?? 'Numelixa update').toString(),
    itemSubtitle: (item) => (item['message'] ?? '').toString(),
  );
}

typedef _LoadList = Future<Map<String, dynamic>> Function(NumelixaRepository, String);
typedef _ItemText = String Function(Map<String, dynamic>);
class _ProtectedListPage extends StatefulWidget {
  const _ProtectedListPage({required this.title, required this.load, required this.listKey, required this.empty, required this.itemTitle, required this.itemSubtitle, this.onItemTap});
  final String title, listKey, empty;
  final _LoadList load;
  final _ItemText itemTitle, itemSubtitle;
  final ValueChanged<Map<String, dynamic>>? onItemTap;
  @override
  State<_ProtectedListPage> createState() => _ProtectedListPageState();
}
class _ProtectedListPageState extends State<_ProtectedListPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = widget.load(NumelixaRepository(), context.read<AuthService>().accessToken!); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
        final raw = snapshot.data?[widget.listKey];
        final items = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
        if (items.isEmpty) return _RetryState(message: widget.empty, onRetry: () => setState(_load), empty: true);
        return RefreshIndicator(onRefresh: () async => setState(_load), child: ListView(padding: const EdgeInsets.all(12), children: [
          for (final item in items)
            Card(child: ListTile(
              leading: Icon(widget.title == 'Notifications' ? Icons.notifications_none_rounded : Icons.receipt_long_rounded, color: AppTheme.cyan),
              title: Text(widget.itemTitle(item), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(widget.itemSubtitle(item), maxLines: 3, overflow: TextOverflow.ellipsis),
              onTap: widget.onItemTap == null ? null : () => widget.onItemTap!(item),
            )),
        ]));
      },
    ),
  );
}

class _AccountPage extends StatefulWidget {
  const _AccountPage();
  @override
  State<_AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<_AccountPage> {
  final ImagePicker _picker = ImagePicker();
  bool _photoBusy = false;

  ImageProvider<Object>? _avatarProvider(Map<String, dynamic> user) {
    final value = (user['avatarDataUrl'] ?? user['avatarUrl'] ?? '').toString();
    if (value.startsWith('data:image/') && value.contains(',')) {
      try { return MemoryImage(base64Decode(value.substring(value.indexOf(',') + 1))); } catch (_) { return null; }
    }
    if (value.startsWith('https://') || value.startsWith('http://')) return NetworkImage(value);
    return null;
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(source: source, maxWidth: 640, maxHeight: 640, imageQuality: 72);
    if (file == null || !mounted) return;
    setState(() => _photoBusy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > 450 * 1024) throw const ApiException('Profile photo must be smaller than 450 KB.');
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png') ? 'image/png' : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      await context.read<AuthService>().uploadProfilePhoto('data:$mime;base64,${base64Encode(bytes)}');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update profile photo. Try again.')));
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _showPhotoOptions() async {
    await showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () { Navigator.pop(sheetContext); _pickPhoto(ImageSource.camera); }),
        ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () { Navigator.pop(sheetContext); _pickPhoto(ImageSource.gallery); }),
      ],
    )));
  }

  Future<void> _changePassword() async {
    final auth = context.read<AuthService>();
    try {
      await auth.requestPasswordChangeCode();
      if (!mounted) return;
      final changed = await showDialog<bool>(context: context, builder: (_) => const _PasswordChangeDialog());
      if (changed == true && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully.')));
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send the password code. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user ?? const <String, dynamic>{};
    final avatar = _avatarProvider(user);
    return ListView(padding: const EdgeInsets.all(18), children: [
      const SizedBox(height: 12),
      Center(child: Stack(children: [
        CircleAvatar(radius: 42, backgroundColor: const Color(0xFF123C64), backgroundImage: avatar,
          child: avatar == null ? const Icon(Icons.person_outline_rounded, size: 40, color: AppTheme.cyan) : null),
        Positioned(right: 0, bottom: 0, child: Material(
          color: AppTheme.cyan, shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Change profile photo',
            onPressed: _photoBusy ? null : _showPhotoOptions,
            icon: _photoBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt_rounded, color: Color(0xFF03121F), size: 19),
          ),
        )),
      ])),
      const SizedBox(height: 12),
      Text((user['name'] ?? 'Numelixa user').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      Text((user['email'] ?? user['phone'] ?? 'Phone number not added').toString(), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF91A8C4))),
      const SizedBox(height: 22),
      Card(child: ListTile(
        leading: const Icon(Icons.verified_user_outlined, color: AppTheme.cyan),
        title: Text((user['phone'] ?? '').toString().isNotEmpty ? 'Verified phone account' : 'Secure email account'),
        subtitle: Text((user['phone'] ?? user['email'] ?? 'Account verified by Numelixa').toString()),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.badge_rounded, color: AppTheme.cyan),
        title: const Text('Your Numelixa ID'),
        subtitle: SelectableText((user['publicId'] ?? 'ID unavailable').toString(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, letterSpacing: 1.2)),
        trailing: IconButton(tooltip: 'Copy account ID', icon: const Icon(Icons.copy_rounded), onPressed: () async { await Clipboard.setData(ClipboardData(text: (user['publicId'] ?? '').toString())); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numelixa ID copied.'))); }),
      )),
      Card(child: ListTile(leading: const Icon(Icons.card_giftcard_rounded, color: AppTheme.violet), title: const Text('Referral rewards'), subtitle: const Text('Invite friends and withdraw earned rewards.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ReferralRewardsPage(accessToken: auth.accessToken!))))),
      if ((user['role'] ?? '').toString() == 'admin')
        Card(child: ListTile(leading: const Icon(Icons.admin_panel_settings_rounded, color: AppTheme.mint), title: const Text('Admin control center'), subtitle: const Text('Users, payments, referrals and system overview.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _AdminControlPage(accessToken: auth.accessToken!))))),
      Card(child: ListTile(leading: const Icon(Icons.devices_other_rounded, color: AppTheme.cyan), title: const Text('Your devices'), subtitle: const Text('View signed-in devices, location and recent activity.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _DevicesPage())))),
      if ((user['email'] ?? '').toString().isNotEmpty)
        Card(child: ListTile(leading: const Icon(Icons.password_rounded, color: AppTheme.cyan), title: const Text('Change password'), subtitle: const Text('Verify a code sent to your email.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: _changePassword)),
      Card(child: SwitchListTile(
        secondary: const Icon(Icons.fingerprint_rounded, color: AppTheme.cyan),
        title: const Text('Biometric app lock'),
        subtitle: Text(auth.biometricEnabled ? 'Fingerprint or face authentication is enabled.' : 'Require fingerprint or face authentication when reopening Numelixa.'),
        value: auth.biometricEnabled,
        onChanged: (enabled) async {
          try {
            if (enabled) {
              final ok = await auth.enableBiometricLock();
              if (ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biometric lock enabled.')));
            } else {
              await auth.disableBiometricLock();
            }
          } on ApiException catch (error) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
          } catch (_) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Biometric authentication could not be configured on this device.')));
          }
        },
      )),
      Card(child: ListTile(leading: const Icon(Icons.forum_rounded, color: AppTheme.cyan), title: const Text('Help Team Chat'), subtitle: const Text('Chat with Numelixa support'), trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16), onTap: () { final token = context.read<AuthService>().accessToken; Navigator.of(context).push(MaterialPageRoute(builder: (_) => HelpTeamScreen(accessToken: token))); })),
      Card(child: ListTile(leading: const Icon(Icons.support_agent_rounded, color: AppTheme.cyan), title: const Text('Help & support'), subtitle: const Text('support.numelixa.com'), trailing: const Icon(Icons.open_in_new_rounded), onTap: () => launchUrl(Uri.parse('https://support.numelixa.com'), mode: LaunchMode.externalApplication))),
      Card(child: ListTile(leading: const Icon(Icons.chat_rounded, color: Color(0xFF25D366)), title: const Text('WhatsApp support'), subtitle: const Text('Chat with us · +252 907 868526'), trailing: const Icon(Icons.open_in_new_rounded), onTap: () => launchUrl(Uri.parse('https://wa.me/252907868526'), mode: LaunchMode.externalApplication))),
      Card(child: ValueListenableBuilder<String>(
        valueListenable: context.read<NotificationService>().registrationStatus,
        builder: (context, status, _) => ListTile(
          leading: const Icon(Icons.notifications_active_outlined, color: AppTheme.cyan),
          title: const Text('Push notifications'),
          subtitle: Text(status),
          trailing: IconButton(
            tooltip: 'Retry notification registration',
            onPressed: () async {
              final auth = context.read<AuthService>();
              final notifications = context.read<NotificationService>();
              final permission = await notifications.requestPermission();
              if (permission.isGranted) await notifications.syncToken(auth);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          onTap: () => context.read<NotificationService>().openNotificationSettings(),
        ),
      )),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () async { await context.read<AuthService>().logout(); },
        icon: const Icon(Icons.logout_rounded), label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: const Color(0xFFFF788C)),
      ),
    ]);
  }
}

class _DevicesPage extends StatefulWidget {
  const _DevicesPage();
  @override
  State<_DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<_DevicesPage> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = context.read<AuthService>().listDevices(); }

  String _location(Map<String, dynamic> device) {
    final parts = [device['city'], device['region'], device['country']]
        .where((value) => value != null && value.toString().trim().isNotEmpty)
        .map((value) => value.toString().trim()).toList();
    return parts.isEmpty ? 'Not available' : parts.join(', ');
  }

  String _date(dynamic value) {
    if (value == null) return 'Unknown';
    final date = DateTime.tryParse(value.toString());
    if (date == null) return value.toString();
    return date.toLocal().toString().split('.').first;
  }

  Future<void> _remove(Map<String, dynamic> device) async {
    final auth = context.read<AuthService>();
    final id = (device['deviceId'] ?? device['sessionId'] ?? '').toString();
    final sessionId = (device['sessionId'] ?? '').toString();
    final isCurrent = device['current'] == true;
    final yes = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Remove device?'),
      content: Text(isCurrent ? 'This is the device you are using now. Removing it will sign you out.' : 'This device session will be revoked and must sign in again.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Remove')),
      ],
    ));
    if (yes != true || !mounted) return;
    try {
      await auth.removeDevice(id, sessionId: sessionId);
      if (isCurrent) {
        await auth.logout();
        if (mounted) Navigator.of(context).pop();
      } else if (mounted) {
        setState(_load);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device session removed.')));
      }
    } on ApiException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not remove this device.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your devices')),
    body: FutureBuilder<Map<String, dynamic>>(future: _future, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
      final raw = snapshot.data?['devices'];
      final devices = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      if (devices.isEmpty) return _RetryState(message: 'No active device sessions were found.', onRetry: () => setState(_load), empty: true);
      return RefreshIndicator(onRefresh: () async => setState(_load), child: ListView(padding: const EdgeInsets.all(12), children: [
        for (final device in devices)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.devices_rounded, color: AppTheme.cyan, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text((device['device'] ?? 'Device').toString(), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              if (device['current'] == true) const Chip(label: Text('This device')),
            ]),
            const SizedBox(height: 8),
            Text('Platform: ${device['platform'] ?? 'Unknown'} · ${device['browser'] ?? 'App'}'),
            Text('Location: ${_location(device)}'),
            Text('Signed in: ${_date(device['createdAt'])}'),
            Text('Last active: ${_date(device['lastSeenAt'])}'),
            Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _remove(device), icon: const Icon(Icons.logout_rounded), label: const Text('Remove device'))),
          ]))),
      ]));
    }),
  );
}

class _PasswordChangeDialog extends StatefulWidget {
  const _PasswordChangeDialog();
  @override
  State<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}
class _PasswordChangeDialogState extends State<_PasswordChangeDialog> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() { _code.dispose(); _password.dispose(); super.dispose(); }
  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<AuthService>().confirmPasswordChange(code: _code.text, newPassword: _password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change the password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Change password'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Enter the 6-digit code sent to your email, then choose a new password.'),
      const SizedBox(height: 12),
      TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, decoration: const InputDecoration(labelText: 'Email verification code')),
      TextField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'New password (8+ characters)')),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF788C)))),
    ])),
    actions: [
      TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Update password')),
    ],
  );
}

class _BiometricLockScreen extends StatefulWidget {
  const _BiometricLockScreen();
  @override
  State<_BiometricLockScreen> createState() => _BiometricLockScreenState();
}
class _BiometricLockScreenState extends State<_BiometricLockScreen> {
  bool _busy = false;
  String? _error;
  Future<void> _unlock() async {
    setState(() { _busy = true; _error = null; });
    try {
      final ok = await context.read<AuthService>().unlockBiometrics();
      if (!ok && mounted) setState(() => _error = 'Authentication was not completed. Try again.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Biometric authentication failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.fingerprint_rounded, size: 64, color: AppTheme.cyan),
      const SizedBox(height: 16),
      const Text('Numelixa is locked', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      const Text('Use your fingerprint or face authentication to continue.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF91A8C4))),
      if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF788C)))),
      const SizedBox(height: 18),
      FilledButton.icon(onPressed: _busy ? null : _unlock, icon: const Icon(Icons.lock_open_rounded), label: Text(_busy ? 'Checking…' : 'Unlock with biometrics')),
    ]))),
  );
}

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry, this.empty = false});
  final String message; final VoidCallback onRetry; final bool empty;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(empty ? Icons.inbox_outlined : Icons.cloud_off_rounded, size: 42, color: const Color(0xFF7185A5)),
      const SizedBox(height: 14),
      Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF91A8C4), height: 1.5)),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Try again')),
    ]),
  ));
}


class _LoginApprovalPage extends StatefulWidget {
  const _LoginApprovalPage({required this.approvalId});
  final String approvalId;
  @override
  State<_LoginApprovalPage> createState() => _LoginApprovalPageState();
}

class _LoginApprovalPageState extends State<_LoginApprovalPage> {
  late Future<Map<String, dynamic>> _future;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }
  Future<Map<String, dynamic>> _load() async {
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn || auth.accessToken == null) throw const ApiException('Sign in on this device to review this request.');
    final response = await ApiClient().get('/api/auth/login/approval?id=${Uri.encodeQueryComponent(widget.approvalId)}', accessToken: auth.accessToken);
    if (response['ok'] != true || response['approval'] is! Map) throw ApiException((response['error'] ?? 'This login request is unavailable.').toString());
    return Map<String, dynamic>.from(response['approval'] as Map);
  }
  Future<void> _answer(bool approve) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final auth = context.read<AuthService>();
      final response = await ApiClient().post('/api/auth/login/approval', accessToken: auth.accessToken, body: {'approvalId': widget.approvalId, 'approve': approve});
      if (response['ok'] != true) throw ApiException((response['error'] ?? 'Unable to submit your decision.').toString());
      if (!mounted) return;
      setState(() { _message = approve ? 'Approved. If this was your sign-in, return to the browser to continue.' : 'Denied. The browser sign-in request has been blocked.'; _future = _load(); });
    } catch (e) {
      if (mounted) setState(() => _message = e is ApiException ? e.message : 'Unable to submit your decision. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Extra Security')),
    body: SafeArea(child: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(snapshot.error.toString(), textAlign: TextAlign.center)));
        final approval = snapshot.data!;
        final pending = approval['status'] == 'pending';
        return ListView(padding: const EdgeInsets.all(20), children: [
          Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: const Color(0xFF0B1C33), border: Border.all(color: const Color(0xFF23415F))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.shield_outlined, color: Color(0xFF00D9FF), size: 36),
            const SizedBox(height: 14),
            const Text('Is this you?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('A browser is requesting access to your Numelixa account. Only approve if you started this sign-in.', style: TextStyle(color: Color(0xFFA7B7D0), height: 1.5)),
            const SizedBox(height: 18),
            _securityDetail('DEVICE', (approval['device'] ?? 'Browser').toString()),
            _securityDetail('BROWSER', (approval['browser'] ?? 'Browser').toString()),
            _securityDetail('LOCATION', [approval['city'], approval['country']].where((v) => v != null && v.toString().isNotEmpty).join(', ').isEmpty ? 'Location unavailable' : [approval['city'], approval['country']].where((v) => v != null && v.toString().isNotEmpty).join(', ')),
            _securityDetail('STATUS', (approval['status'] ?? 'unknown').toString().toUpperCase()),
          ])),
          Padding(padding: const EdgeInsets.only(top: 14), child: Text(_message ?? '', style: const TextStyle(color: Color(0xFF00D9FF)))),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _busy || !pending ? null : () => _answer(true), icon: const Icon(Icons.check_circle_outline), label: Text(_busy ? 'Please wait…' : "Yes, it's me"), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF00D9FF), foregroundColor: const Color(0xFF031022), padding: const EdgeInsets.symmetric(vertical: 16))),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _busy || !pending ? null : () => _answer(false), icon: const Icon(Icons.cancel_outlined), label: const Text('No, deny login'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF7D91), padding: const EdgeInsets.symmetric(vertical: 16))),
          const SizedBox(height: 12),
          const Text('If you did not start this login, choose “No, deny login”.', style: TextStyle(color: Color(0xFF91A8C4), height: 1.4)),
        ]);
      },
    )),
  );
  Widget _securityDetail(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 88, child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7185A5), fontWeight: FontWeight.w700))), Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)))]));
}


class _ReferralRewardsPage extends StatefulWidget {
  const _ReferralRewardsPage({required this.accessToken});
  final String accessToken;
  @override
  State<_ReferralRewardsPage> createState() => _ReferralRewardsPageState();
}
class _ReferralRewardsPageState extends State<_ReferralRewardsPage> {
  late Future<Map<String,dynamic>> _future;
  final _amount=TextEditingController(),_account=TextEditingController();
  String _method='Mobile wallet';bool _busy=false;String _message='';
  @override void initState(){super.initState();_load();}
  @override void dispose(){_amount.dispose();_account.dispose();super.dispose();}
  void _load(){_future=ApiClient().get('/api/referrals',accessToken:widget.accessToken);}
  Future<void> _withdraw() async {
    setState(()=>_busy=true);try{final d=await ApiClient().post('/api/referrals',accessToken:widget.accessToken,body:{'amountUsd':double.tryParse(_amount.text.trim())??0,'method':_method,'account':_account.text.trim()});if(d['ok']!=true)throw ApiException((d['error']??'Withdrawal request failed.').toString());_amount.clear();_account.clear();_message='Withdrawal request sent to Admin.';setState(_load);}on ApiException catch(e){_message=e.message;}catch(_){_message='Unable to submit withdrawal.';}finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Referral rewards')),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(s.hasError)return _RetryState(message:s.error.toString(),onRetry:()=>setState(_load));final d=s.data??{};if(d['ok']!=true)return _RetryState(message:(d['error']??'Referral account unavailable').toString(),onRetry:()=>setState(_load));final rewards=d['rewards'] is List?d['rewards'] as List:const [];final withdrawals=d['withdrawals'] is List?d['withdrawals'] as List:const [];final link=(d['link']??'').toString();return ListView(padding:const EdgeInsets.all(18),children:[Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(borderRadius:BorderRadius.circular(24),gradient:const LinearGradient(colors:[Color(0xFF123C64),Color(0xFF10162F)]),border:Border.all(color:AppTheme.glassBorder)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('YOUR REFERRAL BALANCE',style:TextStyle(color:AppTheme.mint,fontSize:11,letterSpacing:1.4,fontWeight:FontWeight.w800)),const SizedBox(height:8),Text('\$'+(double.tryParse((d['balanceUsd']??0).toString())??0).toStringAsFixed(2),style:const TextStyle(fontSize:34,fontWeight:FontWeight.w900)),const Text('Separate from your main Numelixa wallet.',style:TextStyle(color:AppTheme.muted))]),),const SizedBox(height:14),Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('YOUR INVITATION LINK',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w800,fontSize:11)),const SizedBox(height:8),SelectableText(link),Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:link.isEmpty?null:(){Clipboard.setData(ClipboardData(text:link));ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Referral link copied.')));},icon:const Icon(Icons.copy_rounded),label:const Text('Copy link'))),Text(d['enabled']==true?'Earn '+(d['commissionPercent']??0).toString()+'% after an invited member completes a verified payment.':'Referral program is currently paused.',style:const TextStyle(color:AppTheme.muted))]))),Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('WITHDRAW REFERRAL REWARDS',style:TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:12),TextField(controller:_amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount in USD')),const SizedBox(height:10),DropdownButtonFormField<String>(value:_method,decoration:const InputDecoration(labelText:'Withdrawal method'),items:const [DropdownMenuItem(value:'Mobile wallet',child:Text('Mobile wallet')),DropdownMenuItem(value:'Bank transfer',child:Text('Bank transfer')),DropdownMenuItem(value:'Other',child:Text('Other'))],onChanged:(v)=>setState(()=>_method=v??_method)),const SizedBox(height:10),TextField(controller:_account,decoration:const InputDecoration(labelText:'Phone / bank account details')),const SizedBox(height:12),FilledButton(onPressed:_busy?null:_withdraw,child:Text(_busy?'Submitting…':'Request withdrawal')),if(_message.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text(_message,style:const TextStyle(color:AppTheme.cyan)))]))),const Text('REWARD HISTORY',style:TextStyle(fontWeight:FontWeight.w800)),for(final x in rewards.whereType<Map>())ListTile(leading:const Icon(Icons.add_circle_outline,color:AppTheme.mint),title:Text('\$'+(x['amountUsd']??0).toString()+' USD'),subtitle:Text((x['description']??'Verified payment').toString()),trailing:Text((x['status']??'available').toString())),const SizedBox(height:8),const Text('WITHDRAWAL REQUESTS',style:TextStyle(fontWeight:FontWeight.w800)),for(final x in withdrawals.whereType<Map>())ListTile(leading:const Icon(Icons.outbox_rounded,color:AppTheme.violet),title:Text('\$'+(x['amountUsd']??0).toString()+' USD'),subtitle:Text((x['method']??'').toString()),trailing:Text((x['status']??'pending').toString()))]);}));
}
class _AdminControlPage extends StatefulWidget {
 const _AdminControlPage({required this.accessToken});final String accessToken;
 @override State<_AdminControlPage> createState()=>_AdminControlPageState();
}
class _AdminControlPageState extends State<_AdminControlPage>{
 late Future<Map<String,dynamic>> _stats;List<Map<String,dynamic>> _users=[];Map<String,dynamic> _referrals={};bool _busy=false,_referralsEnabled=false;String _tab='Overview',_message='',_query='',_commissionPercent='5';
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{_stats=ApiClient().get('/api/admin/stats',accessToken:widget.accessToken);try{final u=await ApiClient().get('/api/admin/users',accessToken:widget.accessToken);_users=u['users'] is List?(u['users'] as List).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():[];final r=await ApiClient().get('/api/admin/referrals',accessToken:widget.accessToken);_referrals=r;final settings=r['settings'];if(settings is Map){_referralsEnabled=settings['enabled']==true;_commissionPercent=(settings['commissionPercent']??0).toString();}}catch(e){_message=e.toString();}}
 Future<void> _credit(Map<String,dynamic> user)async{final controller=TextEditingController();final amount=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text('Add wallet funds · '+(user['email']??user['id']).toString()),content:TextField(controller:controller,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'USD amount')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text),child:const Text('Continue'))]));if(amount==null)return;setState(()=>_busy=true);try{final r=await ApiClient().post('/api/admin/users/coins',accessToken:widget.accessToken,body:{'userId':user['id'],'mode':'add','amountUsd':double.tryParse(amount)??-1});if(r['ok']!=true)throw ApiException((r['error']??'Wallet update failed').toString());_message='Wallet balance updated.';await _load();}catch(e){_message=e.toString();}finally{if(mounted)setState(()=>_busy=false);}}
 Future<void> _saveReferralSettings()async{final percent=double.tryParse(_commissionPercent)??-1;if(percent<0||percent>50){setState(()=>_message='Commission must be between 0 and 50%.');return;}setState(()=>_busy=true);try{final r=await ApiClient().post('/api/admin/referrals',accessToken:widget.accessToken,body:{'action':'settings','enabled':_referralsEnabled,'commissionPercent':percent});if(r['ok']!=true)throw ApiException((r['error']??'Unable to save referral settings').toString());_message='Referral settings saved.';await _load();}catch(e){_message=e.toString();}finally{if(mounted)setState(()=>_busy=false);}}
 Future<void> _review(Map<String,dynamic> w,String decision)async{setState(()=>_busy=true);try{final r=await ApiClient().post('/api/admin/referrals',accessToken:widget.accessToken,body:{'action':'withdrawal','withdrawalId':w['id'],'decision':decision,'note':decision=='reject'?'Rejected from Admin APK':''});if(r['ok']!=true)throw ApiException((r['error']??'Unable to review payout').toString());_message='Withdrawal updated.';await _load();}catch(e){_message=e.toString();}finally{if(mounted)setState(()=>_busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Admin control center'),actions:[IconButton(onPressed:()=>setState(_load),icon:const Icon(Icons.refresh_rounded))]),body:FutureBuilder<Map<String,dynamic>>(future:_stats,builder:(context,s){final d=s.data??{};return ListView(padding:const EdgeInsets.all(16),children:[Wrap(spacing:8,children:[for(final t in ['Overview','Users','Referrals','Withdrawals'])ChoiceChip(label:Text(t),selected:_tab==t,onSelected:(_)=>setState(()=>_tab=t))]),if(_message.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(_message,style:const TextStyle(color:AppTheme.cyan))),if(_tab=='Overview')... [for(final item in [('Users',d['users']),('Active numbers',d['activeNumbers']),('Orders today',d['todayOrders']),('Wallet coins',d['walletCoins'])])Card(child:ListTile(title:Text(item.$1),trailing:Text((item.$2??'—').toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:18))))],if(_tab=='Users')TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search_rounded),hintText:'Search user email or Numelixa ID'),onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase())),if(_tab=='Users')..._users.where((u)=>(u['id'].toString()+' '+(u['email']??'').toString()+' '+(u['name']??'').toString()).toLowerCase().contains(_query)).map((u)=>Card(child:ListTile(title:Text((u['name']??u['email']??'User').toString()),subtitle:Text('ID: '+u['id'].toString()+' · '+u['email'].toString()),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>_AdminUserDetailsPage(accessToken:widget.accessToken,userId:u['id'].toString()))),trailing:IconButton(onPressed:_busy?null:()=>_credit(u),icon:const Icon(Icons.add_card_rounded,color:AppTheme.mint))))),if(_tab=='Referrals')Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Referral program settings',style:TextStyle(fontWeight:FontWeight.w900)),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Enable referrals'),value:_referralsEnabled,onChanged:_busy?null:(v)=>setState(()=>_referralsEnabled=v)),TextFormField(initialValue:_commissionPercent,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Commission percentage (0–50%)'),onChanged:(v)=>_commissionPercent=v),const SizedBox(height:10),FilledButton(onPressed:_busy?null:_saveReferralSettings,child:const Text('Save referral settings'))]))),if(_tab=='Referrals'||_tab=='Withdrawals')...(((_referrals['withdrawals'] is List)?_referrals['withdrawals'] as List:const []).whereType<Map>().where((w)=>_tab=='Withdrawals'?w['status']=='pending':true).map((w)=>Card(child:ListTile(title:Text((w['email']??w['userId']??'User').toString()),subtitle:Text('\$'+(w['amountUsd']??0).toString()+' · '+(w['method']??'').toString()+' · '+(w['status']??'').toString()),trailing:w['status']=='pending'?Wrap(children:[IconButton(onPressed:_busy?null:()=>_review(Map<String,dynamic>.from(w),'approve'),icon:const Icon(Icons.check_circle,color:AppTheme.mint)),IconButton(onPressed:_busy?null:()=>_review(Map<String,dynamic>.from(w),'reject'),icon:const Icon(Icons.cancel,color:Color(0xFFFF788C))) ]):null)))),if(s.connectionState==ConnectionState.waiting&&d.isEmpty)const Center(child:CircularProgressIndicator())]);}));
}

class _AdminUserDetailsPage extends StatefulWidget {
 const _AdminUserDetailsPage({required this.accessToken,required this.userId});final String accessToken,userId;
 @override State<_AdminUserDetailsPage> createState()=>_AdminUserDetailsPageState();
}
class _AdminUserDetailsPageState extends State<_AdminUserDetailsPage>{
 late Future<Map<String,dynamic>> _future;
 @override void initState(){super.initState();_load();}
 void _load(){_future=ApiClient().get('/api/admin/users/'+Uri.encodeComponent(widget.userId),accessToken:widget.accessToken);}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('User history')),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());final d=s.data??{};if(d['ok']!=true)return _RetryState(message:(d['error']??'Unable to load user history').toString(),onRetry:()=>setState(_load));final u=d['user'] as Map<String,dynamic>;final payments=d['payments'] is List?d['payments'] as List:const [],transactions=d['transactions'] is List?d['transactions'] as List:const [],orders=d['orders'] is List?d['orders'] as List:const [];return ListView(padding:const EdgeInsets.all(16),children:[Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text((u['name']??'User').toString(),style:const TextStyle(fontSize:21,fontWeight:FontWeight.w900)),SelectableText('Numelixa ID: '+widget.userId),Text((u['email']??'').toString()),Text('Wallet: '+(NumberFormatHelper.money((double.tryParse((u['coins']??0).toString())??0)/100))),Text('Referral balance: '+(NumberFormatHelper.money((double.tryParse((u['referralBalanceCents']??0).toString())??0)/100)))]))),const Text('PAYMENTS',style:TextStyle(fontWeight:FontWeight.w900)),for(final p in payments.whereType<Map>())Card(child:ListTile(title:Text((p['method']??'Payment').toString()+' · '+NumberFormatHelper.money(double.tryParse((p['amountUsd']??0).toString())??0)),subtitle:Text((p['status']??'').toString()+' · '+(p['orderId']??'').toString()))),const Text('WALLET LEDGER',style:TextStyle(fontWeight:FontWeight.w900)),for(final t in transactions.whereType<Map>())Card(child:ListTile(title:Text((t['type']??'Transaction').toString()+' · '+(t['amount']??0).toString()+' credits'),subtitle:Text((t['description']??'').toString()+' · '+(t['reference']??'').toString()))),const Text('NUMBER ORDERS',style:TextStyle(fontWeight:FontWeight.w900)),for(final o in orders.whereType<Map>())Card(child:ListTile(title:Text((o['service']??'Service').toString()+' · '+(o['country']??'').toString()),subtitle:Text((o['phone']??'').toString()+' · '+(o['status']??'').toString()))) ]);}));
}
class NumberFormatHelper { static String money(double value)=>'\$'+value.toStringAsFixed(2)+' USD'; }
