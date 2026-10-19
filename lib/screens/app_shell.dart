import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/numelixa_repository.dart';
import 'package:url_launcher/url_launcher.dart';

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
    if (route.startsWith('login_approval:')) {
      final approvalId = route.substring('login_approval:'.length).trim();
      if (approvalId.isNotEmpty) {
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _LoginApprovalPage(approvalId: approvalId)));
      }
    } else if (route == 'orders') {
      setState(() => _index = 2);
    } else if (route == 'wallet') {
      setState(() => _index = 3);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _NotificationsPage()));
    }
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
      final auth = context.read<AuthService>();
      await auth.restore();
      if (!mounted) return;
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
    if (!auth.isReady) {
      return const _SplashScreen();
    }
    if (!auth.isSignedIn) return const _AuthScreen();
    if (auth.biometricLocked) return const _BiometricLockScreen();
    if (auth.needsEmailVerification) return const _EmailVerificationScreen();
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
          Icon(Icons.public_rounded, color: AppTheme.mint, size: 25),
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
        child: const Icon(Icons.public_rounded, color: Colors.white, size: 46),
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
  bool _showApiKey = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); _apiKey.dispose();
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
    return Scaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(
              width: 78, height: 78, alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(26),
                gradient: const LinearGradient(colors: [Color(0xFF1677FF), Color(0xFF00D9FF)]),
                boxShadow: const [BoxShadow(color: Color(0x331677FF), blurRadius: 28, offset: Offset(0, 8))]),
              child: const Icon(Icons.public_rounded, size: 42, color: Colors.white),
            )),
            const SizedBox(height: 26),
            const Text('Welcome to Numelixa', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.7)),
            const SizedBox(height: 8),
            const Text('Global virtual numbers, with a secure account and instant SMS updates.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA7B7D0), height: 1.5)),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(child: FilledButton.tonal(
                onPressed: auth.isValidating ? null : () => setState(() { _creating = false; _error = null; }),
                child: const Text('Log in'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(
                onPressed: auth.isValidating ? null : () => setState(() { _creating = true; _error = null; }),
                child: const Text('Create account'))),
            ]),
            if (_creating) ...[
              const SizedBox(height: 16),
              TextField(controller: _name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded))),
            ],
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              autocorrect: false, autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined))),
            const SizedBox(height: 12),
            TextField(controller: _password, obscureText: _obscurePassword,
              autofillHints: [_creating ? AutofillHints.newPassword : AutofillHints.password],
              decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword))),
              onSubmitted: (_) => auth.isValidating ? null : _submit()),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF788C), height: 1.4)),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: auth.isValidating ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: auth.isValidating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_creating ? 'Create account' : 'Log in securely')),
            if (!_creating) Align(alignment: Alignment.centerRight,
              child: TextButton(onPressed: auth.isValidating ? null : _forgotPassword, child: const Text('Forgot password?'))),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: auth.isValidating ? null : _google,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => setState(() { _showApiKey = !_showApiKey; _error = null; }),
              icon: const Icon(Icons.key_rounded, size: 17),
              label: Text(_showApiKey ? 'Hide developer API-key login' : 'Use developer API key instead')),
            if (_showApiKey) ...[
              TextField(controller: _apiKey, obscureText: true, autocorrect: false,
                decoration: const InputDecoration(labelText: 'Numelixa API key', hintText: 'nx_live_…')),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: auth.isValidating ? null : _apiKeyLogin, child: const Text('Connect API key')),
            ],
            const SizedBox(height: 12),
            const Text('By continuing, you agree to use Numelixa responsibly. Your session is stored securely on this device.',
              textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7185A5), height: 1.5, fontSize: 11)),
          ],
        )),
      ))),
    );
  }
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
      const _ActionTile(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'Account and order updates', destination: 'notifications'),
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
            Text(value == null ? 'Balance unavailable' : '$value coins', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
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
    final key = _serviceKey(service);
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
          Card(child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            leading: _serviceLogo(service),
            title: Text(_serviceName(service), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text((service['description'] ?? service['category'] ?? 'Select to view country availability').toString()),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              final id = (service['id'] ?? service['code'] ?? service['name'] ?? service['title'] ?? '').toString();
              if (id.isEmpty) return;
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CountriesPage(service: id)));
            },
          )),
      ]);
    },
  );
}
class _CountriesPage extends StatefulWidget {
  const _CountriesPage({required this.service});
  final String service;
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
    appBar: AppBar(title: Text('Countries · ${widget.service}')),
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
              trailing: Text((country['stock'] is Map ? country['stock']['sellCoins'] : null)?.toString() ?? '—', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700)),
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
    final name = service.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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

class _WalletPageState extends State<_WalletPage> {
  late Future<Map<String, dynamic>> _transactions;
  late Future<Map<String, dynamic>> _balance;
  late Future<Map<String, dynamic>> _assets;
  int _coins = 36;
  String? _currency;
  String? _network;
  bool _creating = false;

  @override
  void initState() { super.initState(); _load(); }

  void _load() {
    final token = context.read<AuthService>().accessToken!;
    final repo = NumelixaRepository();
    _transactions = repo.transactions(token: token);
    _balance = repo.balance(token: token);
    _assets = repo.depositAssets(token: token);
  }

  List<Map<String, dynamic>> _asMaps(dynamic value) =>
      value is List ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

  Future<void> _createDeposit(Map<String, dynamic> asset) async {
    if (_currency == null || _network == null || _creating) return;
    setState(() => _creating = true);
    try {
      final auth = context.read<AuthService>();
      final result = await NumelixaRepository().createDeposit(
        token: auth.accessToken!, coins: _coins, currency: _currency!, network: _network!);
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

  Future<void> _showDeposit(Map<String, dynamic> payment) async {
    final address = (payment['address'] ?? '').toString();
    final amount = (payment['amount'] ?? '').toString();
    final currency = (payment['currency'] ?? _currency ?? '').toString();
    final network = (payment['networkName'] ?? payment['network'] ?? _network ?? '').toString();
    final orderId = (payment['orderId'] ?? '').toString();
    await showDialog<void>(context: context, barrierDismissible: false, builder: (dialogContext) => AlertDialog(
      title: const Text('Complete your deposit'),
      content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Text('Send exactly $amount $currency on $network. Sending a different amount or network may delay crediting.', style: const TextStyle(color: Color(0xFFA7B7D0), height: 1.45)),
        const SizedBox(height: 14),
        const Text('Exact amount', style: TextStyle(fontWeight: FontWeight.w700)),
        SelectableText('$amount $currency', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppTheme.mint)),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () async {
          await Clipboard.setData(ClipboardData(text: amount));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Exact amount copied.')));
        }, icon: const Icon(Icons.copy_rounded), label: const Text('Copy amount'))),
        const SizedBox(height: 8),
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
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
        FilledButton(onPressed: () async {
          final token = context.read<AuthService>().accessToken!;
          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(dialogContext);
          try {
            final status = await NumelixaRepository().depositStatus(token: token, orderId: orderId);
            final state = (status['status'] ?? 'pending').toString();
            if (!mounted) return;
            messenger.showSnackBar(SnackBar(content: Text(
              state == 'paid' ? 'Payment confirmed. Your wallet is being updated.' : 'Payment status: $state. Check again after sending.')));
            if (state == 'paid') {
              navigator.pop();
              setState(_load);
            }
          } catch (_) {
            if (mounted) messenger.showSnackBar(const SnackBar(content: Text('Could not refresh payment status. Try again shortly.')));
          }
        }, child: const Text('Check payment')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Wallet')),
    body: RefreshIndicator(onRefresh: () async => setState(_load), child: ListView(
      padding: const EdgeInsets.all(14), children: [
        FutureBuilder<Map<String, dynamic>>(future: _balance, builder: (context, snapshot) {
          final value = snapshot.data?['balance'];
          return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Available balance', style: TextStyle(color: Color(0xFFA7B7D0))),
            const SizedBox(height: 6),
            Text(snapshot.connectionState == ConnectionState.waiting ? 'Loading…' : value == null ? '—' : '$value coins',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppTheme.mint)),
            if (snapshot.hasError) Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFFFF788C))),
          ])));
        }),
        const SizedBox(height: 8),
        const Text('Add coins', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        const Text('Choose a package, asset and network. Always copy the exact amount.', style: TextStyle(color: Color(0xFF91A8C4), height: 1.4)),
        const SizedBox(height: 12),
        FutureBuilder<Map<String, dynamic>>(future: _assets, builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Card(child: Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())));
          }
          if (snapshot.hasError) {
            return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Text(snapshot.error.toString(), style: const TextStyle(color: Color(0xFFFF788C))),
              TextButton(onPressed: () => setState(_load), child: const Text('Retry payment options')),
            ])));
          }
          final assets = _asMaps(snapshot.data?['assets']);
          if (assets.isEmpty) {
            return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No deposit assets are available right now.')));
          }
          final selectedAsset = assets.firstWhere((a) => a['coin'] == _currency, orElse: () => assets.first);
          final coin = (selectedAsset['coin'] ?? '').toString();
          final networks = _asMaps(selectedAsset['networks']);
          if (_currency != coin) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() { _currency = coin; _network = null; });
              }
            });
          }
          if (networks.isNotEmpty && !networks.any((n) => n['network'] == _network)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _network = (networks.first['network'] ?? '').toString());
              }
            });
          }
          return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Coin package', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(initialValue: _coins, decoration: const InputDecoration(),
              items: const [
                DropdownMenuItem(value: 36, child: Text('36 coins · \$0.77')),
                DropdownMenuItem(value: 75, child: Text('75 coins · \$1.65')),
                DropdownMenuItem(value: 250, child: Text('250 coins · \$5.49')),
                DropdownMenuItem(value: 499, child: Text('499 coins · \$10.99')),
              ], onChanged: (value) { if (value != null) setState(() => _coins = value); }),
            const SizedBox(height: 12),
            const Text('Cryptocurrency', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(initialValue: coin, decoration: const InputDecoration(),
              items: assets.map((a) => DropdownMenuItem<String>(
                value: (a['coin'] ?? '').toString(),
                child: Text('${a['name'] ?? a['coin']} (${a['coin']})'),
              )).toList(),
              onChanged: (value) => setState(() { _currency = value; _network = null; })),
            const SizedBox(height: 12),
            const Text('Network', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(initialValue: networks.any((n) => n['network'] == _network) ? _network : null,
              decoration: const InputDecoration(),
              items: networks.map((n) => DropdownMenuItem<String>(value: (n['network'] ?? '').toString(),
                child: Text((n['networkName'] ?? n['network'] ?? '').toString()))).toList(),
              onChanged: (value) => setState(() => _network = value)),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: _creating || _network == null ? null : () => _createDeposit(selectedAsset),
              icon: _creating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add_card_rounded),
              label: Text(_creating ? 'Creating deposit…' : 'Create deposit request')),
          ])));
        }),
        const SizedBox(height: 20),
        const Text('Transaction history', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(future: _transactions, builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
          final items = _asMaps(snapshot.data?['transactions']);
          if (items.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No transactions found yet.')));
          return Column(children: items.map((item) => Card(child: ListTile(
            leading: const Icon(Icons.receipt_long_rounded, color: AppTheme.cyan),
            title: Text((item['description'] ?? item['type'] ?? 'Transaction').toString()),
            subtitle: Text('${item['createdAt'] ?? ''}'),
            trailing: Text('${item['amount'] ?? 0} coins', style: const TextStyle(fontWeight: FontWeight.w800)),
          ))).toList());
        }),
      ],
    )),
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
      Text((user['email'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF91A8C4))),
      const SizedBox(height: 22),
      const Card(child: ListTile(leading: Icon(Icons.verified_user_outlined, color: AppTheme.cyan), title: Text('Secure API session'), subtitle: Text('Bearer credential verified by Numelixa.'))),
      Card(child: ListTile(leading: const Icon(Icons.devices_other_rounded, color: AppTheme.cyan), title: const Text('Your devices'), subtitle: const Text('View signed-in devices, location and recent activity.'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _DevicesPage())))),
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
      Card(child: ListTile(leading: const Icon(Icons.support_agent_rounded, color: AppTheme.cyan), title: const Text('Help & support'), subtitle: const Text('support.numelixa.com'), trailing: const Icon(Icons.open_in_new_rounded), onTap: () => launchUrl(Uri.parse('https://support.numelixa.com'), mode: LaunchMode.externalApplication))),
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
