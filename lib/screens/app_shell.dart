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
import '../widgets/service_brand_icon.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/numelixa_repository.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';
import '../widgets/payment_receipt_dialog.dart';
import '../widgets/numelixa_verified_badge.dart';
import 'help_team_screen.dart';
import 'support_admin_screen.dart';
import 'updates_screen.dart';
import 'account_tools_screen.dart';

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
  Timer? _accessCheckTimer;
  bool _accessCheckInProgress = false;
  bool _maintenancePending = false;
  bool _updatesEnabled = false;
  bool _hideUpdates = false;
  bool _updatesConfigLoading = true;
  Map<String, dynamic>? _accessBlock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<AuthService>().addListener(_handleAuthChanged);
    appNotificationRoute.addListener(_handleNotificationRoute);
    updatesVisibilityChanged.addListener(_handleUpdatesVisibilityChanged);
    _accessCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshAccessStatus());
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


  void _handleAuthChanged() {
    if (!mounted || !_maintenancePending) return;
    final auth = context.read<AuthService>();
    if (auth.isSignedIn) _refreshAccessStatus();
  }

  void _handleUpdatesVisibilityChanged() {
    final hidden = updatesVisibilityChanged.value;
    if (hidden == null || !mounted) return;
    setState(() {
      final wasVisible = _updatesEnabled && !_hideUpdates;
      _hideUpdates = hidden;
      final isVisible = _updatesEnabled && !_hideUpdates;
      if (wasVisible && !isVisible && _index >= 3) _index -= 1;
      if (!wasVisible && isVisible && _index >= 2) _index += 1;
    });
  }

  Future<void> _refreshUpdatesConfig() async {
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn || _updatesConfigLoading && _updatesEnabled) return;
    try {
      final result = await ApiClient().get('/api/updates/preferences', accessToken: auth.accessToken);
      if (!mounted) return;
      final enabled = result['enabled'] == true;
      final hidden = result['hideUpdates'] == true;
      if (enabled != _updatesEnabled || hidden != _hideUpdates || _updatesConfigLoading) {
        setState(() {
          final wasVisible = _updatesEnabled && !_hideUpdates;
          _updatesEnabled = enabled;
          _hideUpdates = hidden;
          _updatesConfigLoading = false;
          final isVisible = _updatesEnabled && !_hideUpdates;
          if (wasVisible && !isVisible && _index >= 3) _index -= 1;
          if (!wasVisible && isVisible && _index >= 2) _index += 1;
        });
      }
    } catch (_) {
      // Keep the last known navigation state if the feature-config API is offline.
      if (_updatesConfigLoading && mounted) setState(() => _updatesConfigLoading = false);
    }
  }

  Future<void> _refreshAccessStatus() async {
    _refreshUpdatesConfig();
    if (!mounted || _accessCheckInProgress) return;
    _accessCheckInProgress = true;
    try {
      final access = await ApiClient().get('/api/mobile/access-check');
      if (!mounted) return;
      if (access['allowed'] == false) {
        final auth = context.read<AuthService>();
        if (access['reason'] == 'maintenance' && !auth.isSignedIn) {
          _maintenancePending = true;
          if (_accessBlock != null) setState(() => _accessBlock = null);
          return;
        }
        _maintenancePending = false;
        final next = Map<String, dynamic>.from(access);
        if (_accessBlock == null || _accessBlock?['reason'] != next['reason'] ||
            _accessBlock?['message'] != next['message']) {
          setState(() => _accessBlock = next);
        }
      } else {
        _maintenancePending = false;
        if (_accessBlock != null) setState(() => _accessBlock = null);
      }
    } catch (_) {
      // A temporary status endpoint outage must not unexpectedly lock users out.
    } finally {
      _accessCheckInProgress = false;
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

  Future<void> _openUpdatesNotification(String route) async {
    final parts = route.split(':');
    if (parts.length < 2 || !_updatesEnabled || _hideUpdates) {
      if (mounted) setState(() => _index = 0);
      return;
    }
    final slug = parts[1].trim();
    if (slug.isEmpty) return;
    try {
      final result = await ApiClient().get('/api/updates', accessToken: context.read<AuthService>().accessToken);
      final raw = result['channels'];
      final channels = raw is List ? raw.whereType<Map>().map((x) => Map<String,dynamic>.from(x)).toList() : <Map<String,dynamic>>[];
      final matches = channels.where((x) => (x['slug'] ?? '').toString() == slug).toList();
      final channel = matches.isEmpty ? null : matches.first;
      if (!mounted || channel == null) return;
      setState(() => _index = 2);
      final postId=parts.length>2?parts[2].trim():null;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => UpdatesChannelScreen(channel: channel,initialPostId:postId)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This channel update is temporarily unavailable.')));
    }
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
    if (route.startsWith('updates:')) {
      _openUpdatesNotification(route);
      return;
    }
    setState(() => _index = 0);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessCheckTimer?.cancel();
    context.read<AuthService>().removeListener(_handleAuthChanged);
    appNotificationRoute.removeListener(_handleNotificationRoute);
    updatesVisibilityChanged.removeListener(_handleUpdatesVisibilityChanged);
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
      await _refreshUpdatesConfig();
      if (!mounted) return;
      // Maintenance is checked before the mandatory-update prompt so the
      // maintenance-only Chat screen always takes priority.
      try {
        final earlyAccess = await ApiClient().get('/api/mobile/access-check');
        if (earlyAccess['reason'] == 'maintenance') {
          if (auth.isSignedIn) {
            if (mounted) setState(() => _accessBlock = Map<String, dynamic>.from(earlyAccess));
            return;
          }
          _maintenancePending = true;
          return;
        }
      } catch (_) {}
      await _checkForAppUpdate();
      if (!mounted) return;
      try {
        final access = await ApiClient().get('/api/mobile/access-check');
        if (access['allowed'] == false) {
          if (access['reason'] == 'maintenance' && !auth.isSignedIn) {
            _maintenancePending = true;
          } else {
            if (mounted) setState(() => _accessBlock = Map<String, dynamic>.from(access));
            return;
          }
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
    if (_accessBlock != null) return _AppUnavailableScreen(details: _accessBlock!, accessToken: auth.accessToken);
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
    final updatesVisible = _updatesEnabled && !_hideUpdates;
    final accountIndex = updatesVisible ? 5 : 4;
    final pages = <Widget>[
      const _HomePage(),
      const _CatalogPage(),
      if (updatesVisible) const UpdatesScreen(),
      const _OrdersPage(),
      const _WalletPage(),
      const _AccountPage(),
    ];
    final selectedIndex = _index.clamp(0, pages.length - 1);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: const Row(children: [
          _NumelixaLogo(size: 28),
          SizedBox(width: 10),
          Text('Numelixa', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const _NotificationsPage()),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            tooltip: 'Account',
            onPressed: () => setState(() => _index = accountIndex),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: SafeArea(child: IndexedStack(index: selectedIndex, children: pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.public_outlined), selectedIcon: Icon(Icons.public_rounded), label: 'Numbers'),
          if (updatesVisible) NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign_rounded), label: 'Updates'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
    );
  }
}

class _AppUnavailableScreen extends StatelessWidget {
  const _AppUnavailableScreen({required this.details, this.accessToken});
  final Map<String, dynamic> details;
  final String? accessToken;
  @override
  Widget build(BuildContext context) {
    final reason = (details['reason'] ?? '').toString();
    final countryBlocked = reason == 'country';
    final appVersionBlocked = reason == 'version';
    final maintenance = reason == 'maintenance';
    final number = (details['whatsapp'] ?? '252907868526').toString().replaceAll(RegExp(r'[^0-9]'), '');
    final message = maintenance
        ? 'Numelixa is under maintenance.'
        : countryBlocked
        ? 'This app is not available in your country.'
        : appVersionBlocked
          ? 'This Numelixa app version is no longer supported.'
          : reason == 'android-version'
            ? 'This app is not available on this Android version.'
            : 'This app is not available on this device.';
    final description = maintenance
        ? (details['message'] ?? 'Our team is improving Numelixa. You can still contact the Help Team while maintenance is active.').toString()
        : appVersionBlocked
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
            if (maintenance)
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: accessToken == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HelpTeamScreen(accessToken: accessToken))),
                icon: const Icon(Icons.chat_bubble_outline_rounded), label: const Text('Chat with Help Team'),
              ))
            else
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
    child: Image.asset(
      'assets/numelixa_icon_source.jpg',
      width: size, height: size, fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => const Icon(Icons.public_rounded, color: AppTheme.cyan),
    ),
  );
}
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const _NumelixaLogo(size: 82),
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
                    const Padding(padding: EdgeInsets.only(top: 7), child: Text('Advanced legacy sign-in. API keys are long-lived developer secrets. Use only on a trusted personal device; signing out does not revoke this key.', style: TextStyle(color: AppTheme.warning, fontSize: 11, height: 1.4))),
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
    final name = (auth.user?['name'] ?? auth.user?['email'] ?? 'there').toString().split(' ').first;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 30), children: [
      Container(
        padding: const EdgeInsets.fromLTRB(19, 20, 19, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF123C64), Color(0xFF0B1B34), Color(0xFF10162F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: const Color(0xFF24547B)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const _NumelixaLogo(size: 28), const SizedBox(width: 9), const Text('NUMELIXA', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 11, color: AppTheme.cyan)), const Spacer(), const Icon(Icons.public_rounded, color: AppTheme.cyan, size: 18)]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: Text('Welcome back, $name', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w900))),
            if (auth.user?['badgeVerifiedAt'] != null) const NumelixaVerifiedBadge(verified: true, size: 18),
          ]),
          const SizedBox(height: 7),
          const Text('Your numbers, messages and wallet in one secure workspace.', style: TextStyle(color: Color(0xFFB2C7DD), height: 1.45, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 14),
      const _DataCard(title: 'Available balance', icon: Icons.account_balance_wallet_outlined),
      const SizedBox(height: 20),
      const Text('QUICK ACTIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppTheme.muted)),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 9, crossAxisSpacing: 9, childAspectRatio: 1.75,
        children: [
          _HomeShortcut(icon: Icons.add_call, title: 'Get a number', subtitle: 'Browse live services', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _CatalogPage()))),
          _HomeShortcut(icon: Icons.phone_android_rounded, title: 'Active numbers', subtitle: 'Waiting activations', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _ActiveNumbersPage()))),
          _HomeShortcut(icon: Icons.receipt_long_rounded, title: 'My orders', subtitle: 'Orders and SMS', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _OrdersPage()))),
          _HomeShortcut(icon: Icons.account_balance_wallet_rounded, title: 'Wallet', subtitle: 'Balance and payments', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _WalletPage()))),
          _HomeShortcut(icon: Icons.code_rounded, title: 'Developer API', subtitle: 'API access and docs', onTap: () => launchUrl(Uri.parse('https://www.numelixa.com/developers'), mode: LaunchMode.externalApplication)),
          _HomeShortcut(icon: Icons.card_giftcard_rounded, title: 'Referral rewards', subtitle: 'Invite and earn', onTap: () => launchUrl(Uri.parse('https://www.numelixa.com/referrals'), mode: LaunchMode.externalApplication)),
        ],
      ),
      const SizedBox(height: 20),
      const _HomeNotificationsPreview(),
      const SizedBox(height: 12),
      const _RecentServicesPreview(),
      const SizedBox(height: 12),
      const _HomeUpdatesPreview(),
      const SizedBox(height: 18),
      const Text('HELP & RESOURCES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.5, color: AppTheme.muted)),
      const SizedBox(height: 9),
      const _ActionTile(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'Account, wallet and activation updates', destination: 'notifications'),
      const _ActionTile(icon: Icons.support_agent_rounded, title: 'Support Team Chat', subtitle: 'Private help from the Numelixa team', destination: 'support'),
      const _ActionTile(icon: Icons.menu_book_rounded, title: 'Help Center', subtitle: 'Guides and practical help', destination: 'clients'),
    ]);
  }
}

class _HomeShortcut extends StatelessWidget {
  const _HomeShortcut({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title, subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: InkWell(borderRadius: BorderRadius.circular(17), onTap: onTap, child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFF102844), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppTheme.cyan, size: 20)),
        const SizedBox(width: 9),
        Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9, color: AppTheme.muted)),
        ])),
      ]),
    )),
  );
}

class _HomeNotificationsPreview extends StatefulWidget {
  const _HomeNotificationsPreview();
  @override State<_HomeNotificationsPreview> createState()=>_HomeNotificationsPreviewState();
}
class _HomeNotificationsPreviewState extends State<_HomeNotificationsPreview>{
  late Future<Map<String,dynamic>> _future;
  @override void initState(){super.initState();_load();}
  void _load(){_future=NumelixaRepository().notifications(token:context.read<AuthService>().accessToken??'');}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
    if(s.connectionState==ConnectionState.waiting||s.hasError)return const SizedBox.shrink();
    final raw=s.data?['notifications'];final all=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
    final items=all.where((x){final type=(x['type']??'').toString().toLowerCase();return !type.contains('admin')&&!type.contains('broadcast');}).take(2).toList();
    if(items.isEmpty)return const SizedBox.shrink();
    return Card(child:Padding(padding:const EdgeInsets.all(13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Icon(Icons.notifications_active_outlined,color:AppTheme.cyan,size:18),const SizedBox(width:8),const Expanded(child:Text('Recent notifications',style:TextStyle(fontWeight:FontWeight.w900,fontSize:13))),TextButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const _NotificationsPage())),child:const Text('View all'))]),
      ...items.map((item)=>ListTile(key:ValueKey(item['id']??item['_id']),contentPadding:EdgeInsets.zero,dense:true,leading:const Icon(Icons.circle_notifications_outlined,color:AppTheme.cyan,size:21),title:Text((item['title']??'Numelixa notification').toString(),maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800)),subtitle:Text((item['message']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:AppTheme.muted)))),
    ])));
  });
}

class _RecentServicesPreview extends StatefulWidget {
  const _RecentServicesPreview();
  @override State<_RecentServicesPreview> createState() => _RecentServicesPreviewState();
}
class _RecentServicesPreviewState extends State<_RecentServicesPreview> {
  late Future<Map<String,dynamic>> _future;
  @override void initState(){super.initState();_load();}
  void _load(){final token=context.read<AuthService>().accessToken??'';_future=NumelixaRepository().orders(token:token,limit:12);}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
    if(s.connectionState==ConnectionState.waiting||s.hasError)return const SizedBox.shrink();
    final raw=s.data?['orders'];final orders=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
    final seen=<String>{};final recent=<Map<String,dynamic>>[];
    for(final order in orders){final id=(order['service']??order['serviceId']??order['serviceName']??'').toString();if(id.isNotEmpty&&seen.add(id)){recent.add(order);if(recent.length==4)break;}}
    if(recent.isEmpty)return const SizedBox.shrink();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('RECENTLY USED SERVICES',style:TextStyle(fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.5,color:AppTheme.muted)),
      const SizedBox(height:9),
      SizedBox(height:82,child:ListView.separated(scrollDirection:Axis.horizontal,itemCount:recent.length,separatorBuilder:(_,__)=>const SizedBox(width:9),itemBuilder:(context,index){
        final order=recent[index],id=(order['service']??order['serviceId']??'').toString(),name=(order['serviceName']??order['service']??'Service').toString();
        return InkWell(onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const _CatalogPage())),borderRadius:BorderRadius.circular(15),child:Container(width:132,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:const Color(0xFF0D1930),borderRadius:BorderRadius.circular(15),border:Border.all(color:AppTheme.glassBorder)),child:Row(children:[ServiceBrandIcon(name:name,id:id,size:34),const SizedBox(width:8),Expanded(child:Text(name,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w800)))])));
      })),
      const SizedBox(height:15),
    ]);
  });
}

class _HomeUpdatesPreview extends StatefulWidget {
  const _HomeUpdatesPreview();
  @override State<_HomeUpdatesPreview> createState() => _HomeUpdatesPreviewState();
}
class _HomeUpdatesPreviewState extends State<_HomeUpdatesPreview> {
  late Future<Map<String,dynamic>> _future;
  @override void initState(){super.initState();_load();}
  void _load(){_future=ApiClient().get('/api/updates',accessToken:context.read<AuthService>().accessToken);}
  @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
    if(s.connectionState==ConnectionState.waiting||s.hasError)return const SizedBox.shrink();
    final d=s.data??{};if(d['enabled']!=true||d['hidden']==true)return const SizedBox.shrink();
    final raw=d['channels'];final channels=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).where((x)=>x['latestPost'] is Map).take(2).toList():<Map<String,dynamic>>[];
    if(channels.isEmpty)return const SizedBox.shrink();
    return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[const Icon(Icons.campaign_rounded,color:AppTheme.cyan,size:19),const SizedBox(width:8),const Expanded(child:Text('Latest updates',style:TextStyle(fontWeight:FontWeight.w900,fontSize:14))),TextButton(onPressed:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const UpdatesScreen())),child:const Text('View all'))]),
      ...channels.map((channel){final post=Map<String,dynamic>.from(channel['latestPost'] as Map);final name=(channel['name']??'Channel').toString();final preview=(post['title']??post['body']??'New post').toString();return ListTile(key:ValueKey(channel['id']??channel['slug']),contentPadding:EdgeInsets.zero,dense:true,leading:const CircleAvatar(backgroundColor:Color(0xFF102844),child:Icon(Icons.campaign_outlined,color:AppTheme.cyan,size:18)),title:Text(name,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800)),subtitle:Text(preview,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:AppTheme.muted)),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>UpdatesChannelScreen(channel:channel,initialPostId:(post['id']??'').toString()))));}),
    ])));
  });
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
          'notifications' => const _NotificationsPage(),
          'support' => const _SupportCenterPage(),
          'clients' => const _ClientHelpPage(),
          'wallet' => const _WalletPage(),
          'updates' => const UpdatesScreen(),
          'partners' => const _PartnerCenterPage(),
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

  String _serviceKey(Map<String, dynamic> service) {
    final raw = (service['name'] ?? service['title'] ?? service['id'] ?? service['code'] ?? '').toString();
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceFirst(RegExp(r'\d+$'), '');
  }
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

  Widget _serviceLogo(Map<String, dynamic> service) => ServiceBrandIcon(
    name: _serviceName(service),
    id: (service['id'] ?? service['code'] ?? '').toString(),
    size: 46,
  );
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
      // Prioritize popular services that are actually present in the live API.
      const popularOrder = <String>[
        'whatsapp', 'telegram', 'tiktok', 'instagram', 'facebook',
        'google', 'gmail', 'youtube', 'microsoft', 'discord',
        'snapchat', 'x', 'signal', 'viber', 'wechat', 'line', 'imo',
      ];
      int serviceRank(Map<String, dynamic> service) {
        final key = _serviceKey(service);
        const aliases = <String, String>{
          'wa': 'whatsapp', 'tg': 'telegram', 'tt': 'tiktok',
          'ig': 'instagram', 'fb': 'facebook', 'go': 'google',
          'gm': 'gmail', 'yt': 'youtube', 'ms': 'microsoft',
          'ds': 'discord', 'sn': 'snapchat', 'tw': 'x',
          'li': 'linkedin', 'pp': 'paypal', 'rd': 'reddit',
          'sp': 'spotify', 'nf': 'netflix', 'vb': 'viber', 'sg': 'signal',
        };
        final canonical = aliases[key] ?? key;
        for (var i = 0; i < popularOrder.length; i++) {
          final brand = popularOrder[i];
          if (canonical == brand || canonical.startsWith(brand)) return i;
        }
        return popularOrder.length;
      }
      services.sort((a, b) => serviceRank(a).compareTo(serviceRank(b)));
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
          return ['name','title','id','code','country','countryCode','callingCode','dialCode'].any((key) => (country[key] ?? '').toString().toLowerCase().contains(query));
        }).toList();
        return ListView(padding: const EdgeInsets.all(14), children: [
          TextField(onChanged: (value) => setState(() => _search = value),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), labelText: 'Search countries', hintText: 'United States, India…')),
          const SizedBox(height: 12),
          if (filteredCountries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No countries match your search.', textAlign: TextAlign.center)),
          for (final country in filteredCountries)
            Card(child: ListTile(
              leading: (country['flag'] ?? '').toString().trim().isEmpty
                  ? const Icon(Icons.flag_outlined, color: AppTheme.muted, size: 25)
                  : Text(country['flag'].toString(), style: const TextStyle(fontSize: 25)),
              title: Text((country['name'] ?? country['title'] ?? country['id'] ?? 'Country').toString()),
              subtitle: Text([
                if ((country['callingCode'] ?? country['dialCode'] ?? '').toString().trim().isNotEmpty)
                  (country['callingCode'] ?? country['dialCode']).toString(),
                if ((country['stock'] is Map ? country['stock']['count'] : country['count']) != null)
                  'Available: ${(country['stock'] is Map ? country['stock']['count'] : country['count'])}',
              ].join(' · ')),
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
  String _search = '';
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

  Widget _platformLogo(String service) => ServiceBrandIcon(name: _platformName(service), id: service, size: 40);

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

  bool _isFailed(Map<String, dynamic> order) {
    final status = (order['status'] ?? '').toString().toLowerCase();
    return ['failed', 'failure', 'error', 'expired', 'rejected'].any((value) => status.contains(value));
  }

  bool _isActive(Map<String, dynamic> order) =>
      !_isCanceled((order['status'] ?? '').toString()) &&
      !_isSuccessful(order) && !_isFailed(order);

  String _priceLabel(Map<String, dynamic> order) {
    final raw = order['price'];
    if (raw == null) return '';
    final value = double.tryParse(raw.toString());
    final currency = (order['currency'] ?? 'USD').toString().toUpperCase();
    return value == null ? 'Price: $raw $currency' : 'Price: ${value.toStringAsFixed(2)} $currency';
  }

  String _remainingTime(Map<String, dynamic> order) {
    final raw = order['expiresAt'] ?? order['expires_at'];
    if (raw == null) return '';
    final expires = DateTime.tryParse(raw.toString())?.toLocal();
    if (expires == null) return '';
    final seconds = expires.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 'Activation expired';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return hours > 0 ? 'Expires in ${hours}h ${minutes}m' : 'Expires in ${minutes}m ${seconds % 60}s';
  }

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
          final query = _search.trim().toLowerCase();
          final searchable = [
            order['service'], order['country'], order['countryCode'],
            order['phone'], order['phoneNumber'], order['number'],
            order['id'], order['_id'], order['status'], order['code'], order['fullSms'],
          ].where((value) => value != null).join(' ').toLowerCase();
          if (query.isNotEmpty && !searchable.contains(query)) return false;
          if (_selected == 'active') return _isActive(order);
          if (_selected == 'successful') return _isSuccessful(order);
          if (_selected == 'failed') return _isFailed(order);
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
            child: Column(children: [
              TextField(
                onChanged: (value) => setState(() => _search = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search service, country, number or order ID',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.isEmpty ? null : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(() => _search = ''),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final option in const [
                    ('active', 'Active'),
                    ('successful', 'Completed'),
                    ('canceled', 'Cancelled'),
                    ('failed', 'Failed'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: ChoiceChip(
                        label: Text(option.$2),
                        selected: _selected == option.$1,
                        onSelected: (_) => setState(() => _selected = option.$1),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
          Expanded(
            child: filtered.isEmpty
              ? _RetryState(
                  message: _selected == 'active'
                    ? 'Active numbers waiting for an SMS appear here.'
                    : _selected == 'successful'
                      ? 'Completed activations appear here after the code retention period.'
                      : _selected == 'failed'
                        ? 'Failed or expired activations appear here when the server reports that status.'
                        : 'Cancelled activations appear here.',
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
                                      : _selected == 'successful' ? 'Completed'
                                        : _selected == 'failed' ? 'Failed' : 'Cancelled',
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
                                if (_priceLabel(order).isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 4), child: Text(_priceLabel(order), style: const TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w700))),
                                if (_remainingTime(order).isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 5), child: Text(_remainingTime(order), style: const TextStyle(color: AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w700))),
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
            _DetailLine(label: 'Price', value: order['price'] == null ? 'Unavailable' : '${order['price']} ${(order['currency'] ?? 'USD').toString()}'),
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
  String _transactionFilter = 'all';
  String _transactionSearch = '';

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

  String _ethiopiaDialCode() {
    final raw = _ethiopiaMethods[_ethiopiaMethod];
    final config = raw is Map ? raw : const <String, dynamic>{};
    final template = (config['ussdCode'] ?? '').toString().trim();
    final receiver = (_ethiopiaOrder?['receiverPhone'] ?? config['receiver'] ?? '').toString();
    final amount = (_ethiopiaOrder?['amountEtb'] ?? 0).toString();
    return template.replaceAll('{receiver}', receiver).replaceAll('{amount}', amount);
  }


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
  Future<void> _showTransactionDetails(Map<String, dynamic> item) async {
    final type = (item['type'] ?? 'transaction').toString();
    final reference = (item['reference'] ?? '').toString();
    final amount = double.tryParse((item['amountUsd'] ?? '').toString());
    final isCredit = type == 'credit' || type == 'refund';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: AppTheme.glassBorder, borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 18),
          const Text('Transaction details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Text((item['description'] ?? type).toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(amount == null ? 'Amount unavailable' : '${isCredit ? '+' : '−'}USD ${amount.abs().toStringAsFixed(2)}', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: isCredit ? AppTheme.mint : AppTheme.error)),
          const Divider(height: 24),
          _DetailLine(label: 'Type', value: type),
          _DetailLine(label: 'Date', value: (item['createdAt'] ?? '').toString()),
          _DetailLine(label: 'Currency', value: (item['currency'] ?? 'USD').toString()),
          _DetailLine(label: 'Balance after', value: item['balanceAfterUsd'] == null ? 'Unavailable' : 'USD ${item['balanceAfterUsd']}'),
          _DetailLine(label: 'Reference', value: reference.isEmpty ? 'Not provided' : reference),
          if (type == 'credit' && reference.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () { Navigator.pop(sheetContext); _showOfficialReceipt(reference); }, icon: const Icon(Icons.receipt_long_rounded), label: const Text('View official receipt')),
          ],
        ]),
      )),
    );
  }

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
                LayoutBuilder(builder: (context, constraints) {
                  final trackWidth = constraints.maxWidth;
                  const handleWidth = 50.0;
                  final left = (_ethiopiaSwipe * (trackWidth - handleWidth)).clamp(0.0, trackWidth - handleWidth).toDouble();
                  void update(Offset point) { setState(() => _ethiopiaSwipe = ((point.dx - handleWidth / 2) / (trackWidth - handleWidth)).clamp(0.0, 1.0).toDouble()); }
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: _creating ? null : (details) => update(details.localPosition),
                    onHorizontalDragUpdate: _creating ? null : (details) => update(details.localPosition),
                    onHorizontalDragEnd: _creating ? null : (_) { if (_ethiopiaSwipe >= .98) { _createEthiopiaPayment(); } else { setState(() => _ethiopiaSwipe = 0); } },
                    child: Container(height: 54, decoration: BoxDecoration(color: const Color(0xFF102B47), borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFF315C7F))),
                      child: Stack(children: [
                        Center(child: Text(_creating ? 'Preparing secure payment…' : 'SWIPE TO PREPARE PAYMENT', style: const TextStyle(color: Color(0xFF9FB8D2), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1))),
                        Positioned(left: left, top: 4, bottom: 4, width: handleWidth, child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFF1677FF)]), borderRadius: BorderRadius.circular(13), boxShadow: const [BoxShadow(color: Color(0x441677FF), blurRadius: 12, offset: Offset(0, 4))]), child: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF031021), size: 27))),
                      ]),
                    ),
                  );
                }),
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
                Row(children: [
                  Expanded(child: SelectableText('Receiver: ' + (_ethiopiaOrder!['receiverPhone'] ?? '').toString(), style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Copy receiver number', onPressed: () async { await Clipboard.setData(ClipboardData(text: (_ethiopiaOrder!['receiverPhone'] ?? '').toString())); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receiver number copied.'))); }, icon: const Icon(Icons.copy_rounded, color: AppTheme.cyan)),
                ]),
                if (_ethiopiaDialCode().isNotEmpty && _ethiopiaOrder!['status'] != 'paid')
                  FilledButton.icon(onPressed: () => launchUrl(Uri.parse('tel:${Uri.encodeComponent(_ethiopiaDialCode())}')), icon: const Icon(Icons.phone_in_talk_rounded), label: const Text('Open USSD dialer')),
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
        const Text('This is your wallet ledger. Pending and failed payment requests are not included in this transaction endpoint.', style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.4)),
        const SizedBox(height: 8),
        TextField(onChanged: (value) => setState(() => _transactionSearch = value), decoration: InputDecoration(hintText: 'Search description or reference', prefixIcon: const Icon(Icons.search_rounded), suffixIcon: _transactionSearch.isEmpty ? null : IconButton(onPressed: () => setState(() => _transactionSearch = ''), icon: const Icon(Icons.close_rounded)))),
        const SizedBox(height: 8),
        Wrap(spacing: 7, children: [for (final option in const [('all','All'),('credit','Added'),('debit','Spent'),('refund','Refunds')]) ChoiceChip(label: Text(option.$2), selected: _transactionFilter == option.$1, onSelected: (_) => setState(() => _transactionFilter = option.$1))]),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>>(future: _transactions, builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
          if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
          final items = _asMaps(snapshot.data?['transactions']);
          final query = _transactionSearch.trim().toLowerCase();
          final filteredItems = items.where((item) {
            final type = (item['type'] ?? '').toString().toLowerCase();
            if (_transactionFilter != 'all' && type != _transactionFilter) return false;
            final searchable = '${item['description'] ?? ''} ${item['reference'] ?? ''} ${item['createdAt'] ?? ''}'.toLowerCase();
            return query.isEmpty || searchable.contains(query);
          }).toList();
          if (items.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No wallet ledger transactions have been recorded yet.')));
          if (filteredItems.isEmpty) return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No transactions match these filters.')));
          return Column(children: filteredItems.map((item) {
            final transactionType = (item['type'] ?? '').toString().toLowerCase();
            final isCredit = transactionType == 'credit' || transactionType == 'refund';
            final amount = double.tryParse((item['amountUsd'] ?? 0).toString()) ?? 0;
            final reference = (item['reference'] ?? '').toString();
            final date = (item['createdAt'] ?? '').toString();
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showTransactionDetails(item),
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

IconData _notificationIconFor(Map<String, dynamic> item) {
  final text = (item['title'] ?? '').toString() + ' ' + (item['message'] ?? '').toString();
  final normalized = text.toLowerCase();
  if (RegExp(r'payment|purchase|wallet|deposit|top.?up|credit|refund|checkout|transaction').hasMatch(normalized)) return Icons.account_balance_wallet_rounded;
  if (RegExp(r'order|activation|number|service').hasMatch(normalized)) return Icons.sim_card_rounded;
  if (RegExp(r'sms|verification|code|otp').hasMatch(normalized)) return Icons.sms_rounded;
  if (RegExp(r'security|login|password|device').hasMatch(normalized)) return Icons.shield_rounded;
  return Icons.notifications_active_rounded;
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
              leading: Icon(widget.title == 'Notifications' ? _notificationIconFor(item) : Icons.receipt_long_rounded, color: AppTheme.cyan),
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
      await context.read<AuthService>().uploadProfilePhoto('data:' + mime + ';base64,' + base64Encode(bytes));
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
  Future<void> _openWeb(String path) async {
    final uri = Uri.parse('https://www.numelixa.com' + path);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyPublicId(String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Numelixa ID copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user ?? const <String, dynamic>{};
    final avatar = _avatarProvider(user);
    final name = (user['name'] ?? 'Numelixa user').toString();
    final email = (user['email'] ?? user['phone'] ?? 'Numelixa account').toString();
    final publicIdRaw = (user['publicId'] ?? user['numelixaId'] ?? '').toString();
    final publicId = RegExp(r'^\d{7}$').hasMatch(publicIdRaw) ? publicIdRaw : '';
    final verified = user['verified_at'] != null || user['phoneVerifiedAt'] != null;
    final isAdmin = (user['role'] ?? '').toString() == 'admin';
    final isMerchant = user['merchantEnabled'] == true || (user['role'] ?? '').toString() == 'merchant';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [
            Center(child: Stack(children: [
              CircleAvatar(radius: 39, backgroundColor: const Color(0xFF123C64), backgroundImage: avatar,
                child: avatar == null ? const Icon(Icons.person_outline_rounded, size: 36, color: AppTheme.cyan) : null),
              Positioned(right: 0, bottom: 0, child: Material(
                color: AppTheme.cyan, shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Change profile photo',
                  onPressed: _photoBusy ? null : _showPhotoOptions,
                  icon: _photoBusy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt_rounded, color: Color(0xFF03121F), size: 18),
                ),
              )),
            ])),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              if (user['badgeVerifiedAt'] != null) const SizedBox(width: 6),
              NumelixaVerifiedBadge(verified: user['badgeVerifiedAt'] != null, size: 18),
            ]),
            const SizedBox(height: 4),
            Text(email, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(verified ? Icons.verified_rounded : Icons.pending_outlined, size: 15, color: verified ? AppTheme.mint : AppTheme.warning),
              const SizedBox(width: 5),
              Text(verified ? 'Account verified' : 'Verification pending', style: TextStyle(color: verified ? AppTheme.mint : AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            if (publicId.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: const Color(0xFF0D1930), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.glassBorder)),
                child: Row(children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.cyan, size: 19),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NUMELIXA ID', style: TextStyle(color: AppTheme.muted, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    const SizedBox(height: 2),
                    Text(publicId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ])),
                  IconButton(tooltip: 'Copy Numelixa ID', onPressed: () => _copyPublicId(publicId), icon: const Icon(Icons.copy_rounded, color: AppTheme.cyan, size: 19)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 12),
      const _DataCard(title: 'Available balance', icon: Icons.account_balance_wallet_outlined),
      const SizedBox(height: 16),
      const Padding(padding: EdgeInsets.only(left: 5,bottom: 9),child:Text('QUICK ACCESS',style:TextStyle(fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.5,color:AppTheme.muted))),
      GridView.count(
        crossAxisCount:2,shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
        mainAxisSpacing:9,crossAxisSpacing:9,childAspectRatio:1.75,
        children:[
          _HomeShortcut(icon:Icons.add_call,title:'Get a Number',subtitle:'Browse live services',onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const _CatalogPage()))),
          _HomeShortcut(icon:Icons.receipt_long_rounded,title:'My Orders',subtitle:'Orders and SMS codes',onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const _OrdersPage()))),
          _HomeShortcut(icon:Icons.account_balance_wallet_rounded,title:'Wallet',subtitle:'Balance and payments',onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>const _WalletPage()))),
          _HomeShortcut(icon:Icons.code_rounded,title:'Developer API',subtitle:'API access and docs',onTap:()=>_openWeb('/developers')),
        ],
      ),
      const SizedBox(height: 16),
      if (isMerchant) ...[
        _AccountSection(title:'MERCHANT ACCOUNT',children:[
          _AccountAction(icon:Icons.storefront_rounded,title:'Merchant Dashboard',subtitle:'Transfers and merchant activity',onTap:()=>_openWeb('/merchant')),
        ]),
        const SizedBox(height:14),
      ],
      if (isAdmin) ...[
        const SizedBox(height: 12),
        _AccountSection(title: 'ADMINISTRATION', children: [
          _AccountAction(icon: Icons.admin_panel_settings_rounded, title: 'Admin control center', subtitle: 'Users, payments, referrals and operations', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _AdminControlPage(accessToken: auth.accessToken!)))),
          _AccountAction(icon: Icons.campaign_rounded, title: 'Updates management', subtitle: 'Manage channels, posts and real analytics', onTap: () => _openWeb('/admin/updates')),
          _AccountAction(icon: Icons.handshake_outlined, title: 'Partner enquiries', subtitle: 'Review and respond to partnership requests', onTap: () => _openWeb('/admin/partner-inquiries')),
        ]),
      ],
      const SizedBox(height: 16),
      _AccountSection(title: 'ACCOUNT & IDENTITY', children: [
        _AccountAction(icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Notifications, appearance and account security', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountSettingsScreen()))),
        _AccountAction(icon: Icons.devices_rounded, title: 'Your devices', subtitle: 'Active sessions and sign out other devices', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountDevicesScreen()))),
        _AccountAction(icon: Icons.security_rounded, title: 'Security activity', subtitle: 'Account protection and recent security information', onTap: () => _openWeb('/security')),
        _AccountAction(icon: Icons.password_rounded, title: 'Change password', subtitle: 'Verify the change with your email code', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPasswordScreen()))),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'REWARDS', children: [
        _AccountAction(icon: Icons.card_giftcard_rounded, title: 'Referral rewards', subtitle: 'Your referral code, rewards and withdrawal status', onTap: () => _openWeb('/referrals')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'OFFICIAL SUPPORT', children: [
        _AccountAction(icon: Icons.forum_rounded, title: 'Help Team Chat', subtitle: 'Private one-to-one chat with the official Numelixa team', trailing: const NumelixaVerifiedBadge(verified: true, size: 17), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HelpTeamScreen(accessToken: auth.accessToken)))),
        _AccountAction(icon: Icons.confirmation_number_outlined, title: 'Support Ticket', subtitle: 'Create and track a support request', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _SupportCenterPage()))),
        _AccountAction(icon: Icons.chat_rounded, title: 'WhatsApp Support', subtitle: 'Contact the configured support team', iconColor: const Color(0xFF25D366), onTap: () => launchUrl(Uri.parse('https://wa.me/252907868526'), mode: LaunchMode.externalApplication)),
        _AccountAction(icon: Icons.help_outline_rounded, title: 'Help Center', subtitle: 'Guides and frequently asked questions', onTap: () => _openWeb('/clients')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'DEVELOPER & RESOURCES', children: [
        _AccountAction(icon: Icons.code_rounded, title: 'Developer Portal', subtitle: 'API access and developer tools', onTap: () => _openWeb('/developers')),
        _AccountAction(icon: Icons.menu_book_rounded, title: 'API Documentation', subtitle: 'Verified API routes and integration examples', onTap: () => _openWeb('/developers/docs')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'LEGAL & PRIVACY', children: [
        _AccountAction(icon: Icons.gavel_rounded, title: 'Legal Center', subtitle: 'Official policies and account information', onTap: () => _openWeb('/legal')),
        _AccountAction(icon: Icons.description_outlined, title: 'Terms of Service', subtitle: 'Terms governing use of Numelixa', onTap: () => _openWeb('/terms')),
        _AccountAction(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', subtitle: 'How account and service data is handled', onTap: () => _openWeb('/privacy')),
        _AccountAction(icon: Icons.receipt_long_outlined, title: 'Refund Policy', subtitle: 'Refund eligibility and procedures', onTap: () => _openWeb('/refunds')),
        _AccountAction(icon: Icons.cookie_outlined, title: 'Cookie Policy', subtitle: 'Website cookie information', onTap: () => _openWeb('/cookies')),
        _AccountAction(icon: Icons.rule_rounded, title: 'Acceptable Use', subtitle: 'Permitted and prohibited platform use', onTap: () => _openWeb('/acceptable-use')),
        _AccountAction(icon: Icons.delete_outline_rounded, title: 'Account deletion', subtitle: 'Official account deletion request process', iconColor: const Color(0xFFFF788C), onTap: () => _openWeb('/account-deletion')),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async { await auth.logout(); },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: const Color(0xFFFF788C)),
      ),
    ]);
  }
}
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 5, bottom: 8),
        child: Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.35)),
      ),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const Divider(height: 1, indent: 54),
          ],
        ]),
      ),
    ],
  );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor = AppTheme.cyan,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color iconColor;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    minLeadingWidth: 30,
    leading: Icon(icon, color: iconColor, size: 21),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.3)),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.muted, size: 20),
    onTap: onTap,
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


class _ResourcePageFrame extends StatelessWidget {
  const _ResourcePageFrame({required this.title, required this.subtitle, required this.icon, required this.children});
  final String title, subtitle;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: AppTheme.cyan, size: 25)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: AppTheme.muted, height: 1.45)),
          ])),
        ]),
      ),
      const SizedBox(height: 18),
      ...children,
    ]),
  );
}

class _SupportCenterPage extends StatefulWidget {
  const _SupportCenterPage();
  @override
  State<_SupportCenterPage> createState() => _SupportCenterPageState();
}
class _SupportCenterPageState extends State<_SupportCenterPage> {
  final _contact = TextEditingController(), _subject = TextEditingController(), _message = TextEditingController();
  String _channel = 'email', _category = 'Account';
  bool _loading = false, _sending = false, _canSubmit = true;
  Map<String, dynamic>? _ticket;
  String? _error, _notice;
  @override
  void initState() { super.initState(); _contact.text = (context.read<AuthService>().user?['email'] ?? '').toString(); _refreshTicket(); }
  @override
  void dispose() { _contact.dispose(); _subject.dispose(); _message.dispose(); super.dispose(); }
  Future<void> _refreshTicket() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try { final d = await ApiClient().get('/api/support', accessToken: context.read<AuthService>().accessToken); if (mounted) setState(() { _ticket = d['ticket'] is Map ? Map<String,dynamic>.from(d['ticket']) : null; _canSubmit = d['canSubmit'] != false; }); }
    on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Support status is temporarily unavailable.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _submit() async {
    if (_sending) return;
    if (_contact.text.trim().isEmpty || _subject.text.trim().length < 4 || _message.text.trim().length < 15) { setState(() => _error = 'Enter contact details, a subject and at least 15 characters describing the issue.'); return; }
    setState(() { _sending = true; _error = null; _notice = null; });
    try {
      final d = await ApiClient().post('/api/support', accessToken: context.read<AuthService>().accessToken, body: {'channel':_channel,'contact':_contact.text.trim(),'subject':'$_category · ${_subject.text.trim()}','message':_message.text.trim()});
      if (d['ok'] != true) throw ApiException((d['error'] ?? 'The request was not confirmed.').toString());
      if (!mounted) return;
      setState(() { _subject.clear(); _message.clear(); _notice = 'Your support request was received.'; });
      await _refreshTicket();
    } on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Could not confirm the request. Check your connection and try again.'); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support Center'), actions:[IconButton(tooltip:'Refresh ticket status',onPressed:_loading?null:_refreshTicket,icon:const Icon(Icons.refresh_rounded))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(16,10,16,28), children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:AppTheme.panel,borderRadius:BorderRadius.circular(22),border:Border.all(color:AppTheme.glassBorder)),child:const Row(children:[Icon(Icons.support_agent_rounded,color:AppTheme.cyan,size:34),SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('We are here to help',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Send a private request or use an official support channel.',style:TextStyle(color:AppTheme.muted,height:1.4,fontSize:12))]))])),
      if(_ticket!=null) Card(child:ListTile(leading:const Icon(Icons.confirmation_number_outlined,color:AppTheme.cyan),title:Text((_ticket!['subject']??'Your support request').toString(),maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('Ticket ${(_ticket!['id']??'').toString()} · ${(_ticket!['status']??'received').toString()}'))),
      if(_notice!=null) Padding(padding:const EdgeInsets.all(8),child:Text(_notice!,style:const TextStyle(color:AppTheme.mint,fontWeight:FontWeight.w700))),
      if(_error!=null) Padding(padding:const EdgeInsets.all(8),child:Text(_error!,style:const TextStyle(color:AppTheme.error))),
      const SizedBox(height:8),const Text('Contact Support',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:_category,decoration:const InputDecoration(labelText:'Issue category'),items:const ['Account','Number activation','SMS delivery','Wallet / payment','Orders','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:_sending?null:(v){if(v!=null)setState(()=>_category=v);}),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue:_channel,decoration:const InputDecoration(labelText:'Preferred reply channel'),items:const [DropdownMenuItem(value:'email',child:Text('Email')),DropdownMenuItem(value:'whatsapp',child:Text('WhatsApp')),DropdownMenuItem(value:'telegram',child:Text('Telegram'))],onChanged:_sending?null:(v){if(v!=null)setState(()=>_channel=v);}),
        const SizedBox(height:10),
        TextField(controller:_contact,enabled:!_sending,keyboardType:_channel=='email'?TextInputType.emailAddress:TextInputType.text,decoration:InputDecoration(labelText:_channel=='email'?'Email address':_channel=='whatsapp'?'WhatsApp number with country code':'Telegram username')),
        const SizedBox(height:10),TextField(controller:_subject,enabled:!_sending,maxLength:90,decoration:const InputDecoration(labelText:'Subject')),
        TextField(controller:_message,enabled:!_sending,minLines:4,maxLines:7,maxLength:3000,decoration:const InputDecoration(labelText:'Describe the issue',hintText:'Include an order or payment reference if relevant. Never include your password or OTP code.')),
        const SizedBox(height:10),if (!_canSubmit) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('You already have an active support request. Continue the conversation in Help Team Chat or wait for the current request to close.', style: TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4))),
        FilledButton.icon(onPressed:_sending || !_canSubmit ? null : _submit,icon:_sending?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send_rounded),label:Text(_sending?'Sending request…':_canSubmit?'Submit support request':'Active ticket already open')),
      ]))),
      Card(child:ListTile(leading:const Icon(Icons.forum_rounded,color:AppTheme.cyan),title:const Text('Private Help Team Chat'),subtitle:const Text('Continue a support conversation inside Numelixa.'),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>HelpTeamScreen(accessToken:context.read<AuthService>().accessToken))))),
      Card(child:ListTile(leading:const Icon(Icons.chat_rounded,color:Color(0xFF25D366)),title:const Text('WhatsApp Support'),subtitle:const Text('+252 907 868526'),trailing:const Icon(Icons.open_in_new_rounded),onTap:()=>launchUrl(Uri.parse('https://wa.me/252907868526'),mode:LaunchMode.externalApplication))),
      Card(child:ListTile(leading:const Icon(Icons.email_outlined,color:AppTheme.cyan),title:const Text('Email Support'),subtitle:const Text('support@numelixa.com'),trailing:IconButton(tooltip:'Copy support email',icon:const Icon(Icons.copy_rounded),onPressed:()async{await Clipboard.setData(const ClipboardData(text:'support@numelixa.com'));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Support email copied.')));}),onTap:()=>launchUrl(Uri(scheme:'mailto',path:'support@numelixa.com',queryParameters:{'subject':'Numelixa Support Request'})))),
      Card(child:ListTile(leading:const Icon(Icons.help_outline_rounded,color:AppTheme.cyan),title:const Text('Online Help Center & FAQ'),subtitle:const Text('Open official support articles and troubleshooting.'),trailing:const Icon(Icons.open_in_new_rounded),onTap:()=>launchUrl(Uri.parse('https://support.numelixa.com/'),mode:LaunchMode.externalApplication))),
      const SizedBox(height:10),const Text('Troubleshooting',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
      const Card(child:Column(children:[ListTile(leading:Icon(Icons.sms_failed_outlined,color:AppTheme.warning),title:Text('Activation or SMS problem'),subtitle:Text('Refresh the activation, check its expiry and use Check for SMS before submitting a request.')),Divider(height:1),ListTile(leading:Icon(Icons.account_balance_wallet_outlined,color:AppTheme.cyan),title:Text('Wallet or payment issue'),subtitle:Text('Keep your payment reference, amount and approximate payment time. Do not submit a duplicate while the first payment is pending.')),Divider(height:1),ListTile(leading:Icon(Icons.person_outline_rounded,color:AppTheme.cyan),title:Text('Account issue'),subtitle:Text('Never send your password, one-time code or recovery code to support.'))])),
      const Text('Ticket details appear only when returned by the existing authenticated support API.',style:TextStyle(color:AppTheme.muted,fontSize:11,height:1.5)),
    ]),
  );
}

class _ClientHelpPage extends StatelessWidget {
  const _ClientHelpPage();
  @override
  Widget build(BuildContext context) => _ResourcePageFrame(
    title: 'For Clients',
    subtitle: 'A practical guide to using Numelixa virtual numbers.',
    icon: Icons.menu_book_rounded,
    children: [
      const Text('Getting started', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      for (final item in const [
        ('01', 'Create your account', 'Register or sign in with an available authentication method. Complete any requested email verification.'),
        ('02', 'Add funds', 'Open Wallet, choose an amount and select one of the payment methods currently available to your account.'),
        ('03', 'Choose a service', 'Open Numbers and search the live service catalog. Only services returned by Numelixa are shown.'),
        ('04', 'Select a country', 'Choose a country from the live availability list. The server validates the current price and stock when you place an order.'),
        ('05', 'Receive your SMS', 'Open Orders to view your activation. Check for an SMS code while the activation is waiting.'),
        ('06', 'Review your order', 'Use the activation details to see its current status and available actions.'),
      ])
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.$1, style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(item.$3, style: const TextStyle(color: AppTheme.muted, height: 1.45, fontSize: 12)),
          ])),
        ]))),
      const SizedBox(height: 12),
      const Text('Need troubleshooting?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      Card(child: ListTile(leading: const Icon(Icons.sms_failed_outlined, color: AppTheme.warning), title: const Text('SMS has not arrived'), subtitle: const Text('Check the activation status and use Check for SMS code. If it remains unresolved, contact Support.'), isThreeLine: true)),
      Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.cyan), title: const Text('Payment is pending'), subtitle: const Text('Refresh the payment status in Wallet. Do not submit a duplicate payment while the first request is pending.'), isThreeLine: true)),
      Card(child: ListTile(leading: const Icon(Icons.public_off_rounded, color: AppTheme.muted), title: const Text('No country or number available'), subtitle: const Text('Availability can change. Refresh the country list and try again later.'), isThreeLine: true)),
      const SizedBox(height: 14),
      const Text('Refund information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Eligible refunds for cancelled, expired or unfulfilled activations are returned to the Numelixa wallet according to the order record and published Refund Policy. Completed activations are generally not refundable. If a payment was charged but the wallet was not credited, do not pay again immediately; contact Support with your payment reference.', style: TextStyle(color: AppTheme.muted, height: 1.5)))),
      const Text('Account help', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Card(child: ListTile(leading: Icon(Icons.verified_user_outlined, color: AppTheme.cyan), title: Text('Verification and sign-in'), subtitle: Text('Check your email verification state, use the password recovery flow, and review active devices from Account → Security.'))),
      const Text('Frequently asked questions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      Card(child: ExpansionTile(title: const Text('Why has my SMS not arrived?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Check that the activation is still waiting and has not expired. Use the SMS refresh action. If the provider reports no code before expiry, contact Support with the order ID.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('Can I cancel an activation?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Cancellation is shown only where the order is eligible. The backend validates the provider and order status; a refund is not complete until the server confirms it.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('Why is a country unavailable?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Stock changes continuously. Refresh the service and country list; only current server availability can be purchased.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('What should I send to Support?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Provide your Numelixa ID and relevant order/payment reference. Never include passwords, OTP codes, recovery codes or full payment-card details.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _SupportCenterPage())), icon: const Icon(Icons.support_agent_rounded), label: const Text('Contact Support')),
    ],
  );
}

class _PartnerCenterPage extends StatelessWidget {
  const _PartnerCenterPage();
  static const _email='support@numelixa.com';
  Future<void> _emailTeam(BuildContext context) async {
    final uri=Uri(scheme:'mailto',path:_email,queryParameters:{'subject':'Numelixa partnership enquiry'});
    if(!await launchUrl(uri)&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No email app is available. Copy the address or use Support online.')));
  }
  @override
  Widget build(BuildContext context)=>_ResourcePageFrame(title:'For Partners',subtitle:'Explore business, technical and integration opportunities with Numelixa.',icon:Icons.handshake_outlined,children:[
    for(final item in const [(Icons.business_outlined,'Business partnerships','For organizations interested in collaboration and platform services.'),(Icons.settings_ethernet_rounded,'API partnerships','For products and platforms evaluating server-to-server integration.'),(Icons.storefront_outlined,'Reseller opportunities','For businesses interested in discussing distribution opportunities.'),(Icons.hub_outlined,'Technical partnerships','For infrastructure, telecom and technology integration enquiries.')])
      Card(child:ListTile(leading:Icon(item.$1,color:AppTheme.cyan),title:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(item.$3,style:const TextStyle(color:AppTheme.muted,height:1.4)),isThreeLine:true)),
    const Card(child:Padding(padding:EdgeInsets.all(15),child:Text('Affiliate programme availability is not confirmed. Contact the team to ask whether a programme is available; this page does not promise commissions or approval.',style:TextStyle(color:AppTheme.muted,height:1.5)))),
    Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Row(children:[Icon(Icons.email_outlined,color:AppTheme.cyan),SizedBox(width:9),Text('Official contact',style:TextStyle(fontWeight:FontWeight.w900))]),
      const SizedBox(height:8),const SelectableText(_email,style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),Row(children:[
        Expanded(child:OutlinedButton.icon(onPressed:()async{await Clipboard.setData(const ClipboardData(text:_email));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Email address copied.')));},icon:const Icon(Icons.copy_rounded),label:const Text('Copy email'))),
        const SizedBox(width:9),Expanded(child:FilledButton.icon(onPressed:()=>_emailTeam(context),icon:const Icon(Icons.mail_outline_rounded),label:const Text('Email team'))),
      ]),
      const Text('This is the verified public support address; no separate partner or affiliate email was found.',style:TextStyle(color:AppTheme.muted,fontSize:11,height:1.4)),
    ]))),
    FilledButton.icon(onPressed:()=>launchUrl(Uri.parse('https://support.numelixa.com/'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.support_agent_rounded),label:const Text('Open Support Center')),
  ]);
}


).hasMatch(publicIdRaw) ? publicIdRaw : '';
    final isMerchant = user['merchantEnabled'] == true || (user['role'] ?? '').toString() == 'merchant';
    final verified = user['verified_at'] != null || user['phoneVerifiedAt'] != null;
    final isAdmin = (user['role'] ?? '').toString() == 'admin';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 32), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [
            Center(child: Stack(children: [
              CircleAvatar(radius: 39, backgroundColor: const Color(0xFF123C64), backgroundImage: avatar,
                child: avatar == null ? const Icon(Icons.person_outline_rounded, size: 36, color: AppTheme.cyan) : null),
              Positioned(right: 0, bottom: 0, child: Material(
                color: AppTheme.cyan, shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Change profile photo',
                  onPressed: _photoBusy ? null : _showPhotoOptions,
                  icon: _photoBusy ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.camera_alt_rounded, color: Color(0xFF03121F), size: 18),
                ),
              )),
            ])),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
              if (user['badgeVerifiedAt'] != null) const SizedBox(width: 6),
              NumelixaVerifiedBadge(verified: user['badgeVerifiedAt'] != null, size: 18),
            ]),
            const SizedBox(height: 4),
            Text(email, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(verified ? Icons.verified_rounded : Icons.pending_outlined, size: 15, color: verified ? AppTheme.mint : AppTheme.warning),
              const SizedBox(width: 5),
              Text(verified ? 'Account verified' : 'Verification pending', style: TextStyle(color: verified ? AppTheme.mint : AppTheme.warning, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            if (publicId.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                decoration: BoxDecoration(color: const Color(0xFF0D1930), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.glassBorder)),
                child: Row(children: [
                  const Icon(Icons.badge_outlined, color: AppTheme.cyan, size: 19),
                  const SizedBox(width: 9),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('NUMELIXA ID', style: TextStyle(color: AppTheme.muted, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                    const SizedBox(height: 2),
                    Text(publicId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                  ])),
                  IconButton(tooltip: 'Copy Numelixa ID', onPressed: () => _copyPublicId(publicId), icon: const Icon(Icons.copy_rounded, color: AppTheme.cyan, size: 19)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      if (isAdmin) ...[
        const SizedBox(height: 12),
        _AccountSection(title: 'ADMINISTRATION', children: [
          _AccountAction(icon: Icons.admin_panel_settings_rounded, title: 'Admin control center', subtitle: 'Users, payments, referrals and operations', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _AdminControlPage(accessToken: auth.accessToken!)))),
          _AccountAction(icon: Icons.campaign_rounded, title: 'Updates management', subtitle: 'Manage channels, posts and real analytics', onTap: () => _openWeb('/admin/updates')),
          _AccountAction(icon: Icons.handshake_outlined, title: 'Partner enquiries', subtitle: 'Review and respond to partnership requests', onTap: () => _openWeb('/admin/partner-inquiries')),
        ]),
      ],
      const SizedBox(height: 16),
      _AccountSection(title: 'ACCOUNT & IDENTITY', children: [
        _AccountAction(icon: Icons.settings_outlined, title: 'Settings', subtitle: 'Notifications, appearance and account security', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountSettingsScreen()))),
        _AccountAction(icon: Icons.devices_rounded, title: 'Your devices', subtitle: 'Active sessions and sign out other devices', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountDevicesScreen()))),
        _AccountAction(icon: Icons.security_rounded, title: 'Security activity', subtitle: 'Account protection and recent security information', onTap: () => _openWeb('/security')),
        _AccountAction(icon: Icons.password_rounded, title: 'Change password', subtitle: 'Verify the change with your email code', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPasswordScreen()))),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'REWARDS', children: [
        _AccountAction(icon: Icons.card_giftcard_rounded, title: 'Referral rewards', subtitle: 'Your referral code, rewards and withdrawal status', onTap: () => _openWeb('/referrals')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'OFFICIAL SUPPORT', children: [
        _AccountAction(icon: Icons.forum_rounded, title: 'Help Team Chat', subtitle: 'Private one-to-one chat with the official Numelixa team', trailing: const NumelixaVerifiedBadge(verified: true, size: 17), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HelpTeamScreen(accessToken: auth.accessToken)))),
        _AccountAction(icon: Icons.confirmation_number_outlined, title: 'Support Ticket', subtitle: 'Create and track a support request', onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _SupportCenterPage()))),
        _AccountAction(icon: Icons.chat_rounded, title: 'WhatsApp Support', subtitle: 'Contact the configured support team', iconColor: const Color(0xFF25D366), onTap: () => launchUrl(Uri.parse('https://wa.me/252907868526'), mode: LaunchMode.externalApplication)),
        _AccountAction(icon: Icons.help_outline_rounded, title: 'Help Center', subtitle: 'Guides and frequently asked questions', onTap: () => _openWeb('/clients')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'DEVELOPER & RESOURCES', children: [
        _AccountAction(icon: Icons.code_rounded, title: 'Developer Portal', subtitle: 'API access and developer tools', onTap: () => _openWeb('/developers')),
        _AccountAction(icon: Icons.menu_book_rounded, title: 'API Documentation', subtitle: 'Verified API routes and integration examples', onTap: () => _openWeb('/developers/docs')),
      ]),
      const SizedBox(height: 14),
      _AccountSection(title: 'LEGAL & PRIVACY', children: [
        _AccountAction(icon: Icons.gavel_rounded, title: 'Legal Center', subtitle: 'Official policies and account information', onTap: () => _openWeb('/legal')),
        _AccountAction(icon: Icons.description_outlined, title: 'Terms of Service', subtitle: 'Terms governing use of Numelixa', onTap: () => _openWeb('/terms')),
        _AccountAction(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', subtitle: 'How account and service data is handled', onTap: () => _openWeb('/privacy')),
        _AccountAction(icon: Icons.receipt_long_outlined, title: 'Refund Policy', subtitle: 'Refund eligibility and procedures', onTap: () => _openWeb('/refunds')),
        _AccountAction(icon: Icons.cookie_outlined, title: 'Cookie Policy', subtitle: 'Website cookie information', onTap: () => _openWeb('/cookies')),
        _AccountAction(icon: Icons.rule_rounded, title: 'Acceptable Use', subtitle: 'Permitted and prohibited platform use', onTap: () => _openWeb('/acceptable-use')),
        _AccountAction(icon: Icons.delete_outline_rounded, title: 'Account deletion', subtitle: 'Official account deletion request process', iconColor: const Color(0xFFFF788C), onTap: () => _openWeb('/account-deletion')),
      ]),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () async { await auth.logout(); },
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: const Color(0xFFFF788C)),
      ),
    ]);
  }
}
class _AccountSection extends StatelessWidget {
  const _AccountSection({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 5, bottom: 8),
        child: Text(title, style: const TextStyle(color: AppTheme.muted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.35)),
      ),
      Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const Divider(height: 1, indent: 54),
          ],
        ]),
      ),
    ],
  );
}

class _AccountAction extends StatelessWidget {
  const _AccountAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.iconColor = AppTheme.cyan,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color iconColor;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    minLeadingWidth: 30,
    leading: Icon(icon, color: iconColor, size: 21),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
    subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.3)),
    trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: AppTheme.muted, size: 20),
    onTap: onTap,
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


class _ResourcePageFrame extends StatelessWidget {
  const _ResourcePageFrame({required this.title, required this.subtitle, required this.icon, required this.children});
  final String title, subtitle;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(padding: const EdgeInsets.fromLTRB(18, 12, 18, 28), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 48, height: 48, decoration: BoxDecoration(color: AppTheme.blue.withValues(alpha: .16), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: AppTheme.cyan, size: 25)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -.4)),
            const SizedBox(height: 5),
            Text(subtitle, style: const TextStyle(color: AppTheme.muted, height: 1.45)),
          ])),
        ]),
      ),
      const SizedBox(height: 18),
      ...children,
    ]),
  );
}

class _SupportCenterPage extends StatefulWidget {
  const _SupportCenterPage();
  @override
  State<_SupportCenterPage> createState() => _SupportCenterPageState();
}
class _SupportCenterPageState extends State<_SupportCenterPage> {
  final _contact = TextEditingController(), _subject = TextEditingController(), _message = TextEditingController();
  String _channel = 'email', _category = 'Account';
  bool _loading = false, _sending = false, _canSubmit = true;
  Map<String, dynamic>? _ticket;
  String? _error, _notice;
  @override
  void initState() { super.initState(); _contact.text = (context.read<AuthService>().user?['email'] ?? '').toString(); _refreshTicket(); }
  @override
  void dispose() { _contact.dispose(); _subject.dispose(); _message.dispose(); super.dispose(); }
  Future<void> _refreshTicket() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; });
    try { final d = await ApiClient().get('/api/support', accessToken: context.read<AuthService>().accessToken); if (mounted) setState(() { _ticket = d['ticket'] is Map ? Map<String,dynamic>.from(d['ticket']) : null; _canSubmit = d['canSubmit'] != false; }); }
    on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Support status is temporarily unavailable.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  Future<void> _submit() async {
    if (_sending) return;
    if (_contact.text.trim().isEmpty || _subject.text.trim().length < 4 || _message.text.trim().length < 15) { setState(() => _error = 'Enter contact details, a subject and at least 15 characters describing the issue.'); return; }
    setState(() { _sending = true; _error = null; _notice = null; });
    try {
      final d = await ApiClient().post('/api/support', accessToken: context.read<AuthService>().accessToken, body: {'channel':_channel,'contact':_contact.text.trim(),'subject':'$_category · ${_subject.text.trim()}','message':_message.text.trim()});
      if (d['ok'] != true) throw ApiException((d['error'] ?? 'The request was not confirmed.').toString());
      if (!mounted) return;
      setState(() { _subject.clear(); _message.clear(); _notice = 'Your support request was received.'; });
      await _refreshTicket();
    } on ApiException catch (e) { if (mounted) setState(() => _error = e.message); }
    catch (_) { if (mounted) setState(() => _error = 'Could not confirm the request. Check your connection and try again.'); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Support Center'), actions:[IconButton(tooltip:'Refresh ticket status',onPressed:_loading?null:_refreshTicket,icon:const Icon(Icons.refresh_rounded))]),
    body: ListView(padding: const EdgeInsets.fromLTRB(16,10,16,28), children:[
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:AppTheme.panel,borderRadius:BorderRadius.circular(22),border:Border.all(color:AppTheme.glassBorder)),child:const Row(children:[Icon(Icons.support_agent_rounded,color:AppTheme.cyan,size:34),SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('We are here to help',style:TextStyle(fontSize:19,fontWeight:FontWeight.w900)),SizedBox(height:4),Text('Send a private request or use an official support channel.',style:TextStyle(color:AppTheme.muted,height:1.4,fontSize:12))]))])),
      if(_ticket!=null) Card(child:ListTile(leading:const Icon(Icons.confirmation_number_outlined,color:AppTheme.cyan),title:Text((_ticket!['subject']??'Your support request').toString(),maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('Ticket ${(_ticket!['id']??'').toString()} · ${(_ticket!['status']??'received').toString()}'))),
      if(_notice!=null) Padding(padding:const EdgeInsets.all(8),child:Text(_notice!,style:const TextStyle(color:AppTheme.mint,fontWeight:FontWeight.w700))),
      if(_error!=null) Padding(padding:const EdgeInsets.all(8),child:Text(_error!,style:const TextStyle(color:AppTheme.error))),
      const SizedBox(height:8),const Text('Contact Support',style:TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
      Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        DropdownButtonFormField<String>(initialValue:_category,decoration:const InputDecoration(labelText:'Issue category'),items:const ['Account','Number activation','SMS delivery','Wallet / payment','Orders','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:_sending?null:(v){if(v!=null)setState(()=>_category=v);}),
        const SizedBox(height:10),
        DropdownButtonFormField<String>(initialValue:_channel,decoration:const InputDecoration(labelText:'Preferred reply channel'),items:const [DropdownMenuItem(value:'email',child:Text('Email')),DropdownMenuItem(value:'whatsapp',child:Text('WhatsApp')),DropdownMenuItem(value:'telegram',child:Text('Telegram'))],onChanged:_sending?null:(v){if(v!=null)setState(()=>_channel=v);}),
        const SizedBox(height:10),
        TextField(controller:_contact,enabled:!_sending,keyboardType:_channel=='email'?TextInputType.emailAddress:TextInputType.text,decoration:InputDecoration(labelText:_channel=='email'?'Email address':_channel=='whatsapp'?'WhatsApp number with country code':'Telegram username')),
        const SizedBox(height:10),TextField(controller:_subject,enabled:!_sending,maxLength:90,decoration:const InputDecoration(labelText:'Subject')),
        TextField(controller:_message,enabled:!_sending,minLines:4,maxLines:7,maxLength:3000,decoration:const InputDecoration(labelText:'Describe the issue',hintText:'Include an order or payment reference if relevant. Never include your password or OTP code.')),
        const SizedBox(height:10),if (!_canSubmit) const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('You already have an active support request. Continue the conversation in Help Team Chat or wait for the current request to close.', style: TextStyle(color: AppTheme.warning, fontSize: 12, height: 1.4))),
        FilledButton.icon(onPressed:_sending || !_canSubmit ? null : _submit,icon:_sending?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.send_rounded),label:Text(_sending?'Sending request…':_canSubmit?'Submit support request':'Active ticket already open')),
      ]))),
      Card(child:ListTile(leading:const Icon(Icons.forum_rounded,color:AppTheme.cyan),title:const Text('Private Help Team Chat'),subtitle:const Text('Continue a support conversation inside Numelixa.'),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>HelpTeamScreen(accessToken:context.read<AuthService>().accessToken))))),
      Card(child:ListTile(leading:const Icon(Icons.chat_rounded,color:Color(0xFF25D366)),title:const Text('WhatsApp Support'),subtitle:const Text('+252 907 868526'),trailing:const Icon(Icons.open_in_new_rounded),onTap:()=>launchUrl(Uri.parse('https://wa.me/252907868526'),mode:LaunchMode.externalApplication))),
      Card(child:ListTile(leading:const Icon(Icons.email_outlined,color:AppTheme.cyan),title:const Text('Email Support'),subtitle:const Text('support@numelixa.com'),trailing:IconButton(tooltip:'Copy support email',icon:const Icon(Icons.copy_rounded),onPressed:()async{await Clipboard.setData(const ClipboardData(text:'support@numelixa.com'));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Support email copied.')));}),onTap:()=>launchUrl(Uri(scheme:'mailto',path:'support@numelixa.com',queryParameters:{'subject':'Numelixa Support Request'})))),
      Card(child:ListTile(leading:const Icon(Icons.help_outline_rounded,color:AppTheme.cyan),title:const Text('Online Help Center & FAQ'),subtitle:const Text('Open official support articles and troubleshooting.'),trailing:const Icon(Icons.open_in_new_rounded),onTap:()=>launchUrl(Uri.parse('https://support.numelixa.com/'),mode:LaunchMode.externalApplication))),
      const SizedBox(height:10),const Text('Troubleshooting',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900)),
      const Card(child:Column(children:[ListTile(leading:Icon(Icons.sms_failed_outlined,color:AppTheme.warning),title:Text('Activation or SMS problem'),subtitle:Text('Refresh the activation, check its expiry and use Check for SMS before submitting a request.')),Divider(height:1),ListTile(leading:Icon(Icons.account_balance_wallet_outlined,color:AppTheme.cyan),title:Text('Wallet or payment issue'),subtitle:Text('Keep your payment reference, amount and approximate payment time. Do not submit a duplicate while the first payment is pending.')),Divider(height:1),ListTile(leading:Icon(Icons.person_outline_rounded,color:AppTheme.cyan),title:Text('Account issue'),subtitle:Text('Never send your password, one-time code or recovery code to support.'))])),
      const Text('Ticket details appear only when returned by the existing authenticated support API.',style:TextStyle(color:AppTheme.muted,fontSize:11,height:1.5)),
    ]),
  );
}

class _ClientHelpPage extends StatelessWidget {
  const _ClientHelpPage();
  @override
  Widget build(BuildContext context) => _ResourcePageFrame(
    title: 'For Clients',
    subtitle: 'A practical guide to using Numelixa virtual numbers.',
    icon: Icons.menu_book_rounded,
    children: [
      const Text('Getting started', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      for (final item in const [
        ('01', 'Create your account', 'Register or sign in with an available authentication method. Complete any requested email verification.'),
        ('02', 'Add funds', 'Open Wallet, choose an amount and select one of the payment methods currently available to your account.'),
        ('03', 'Choose a service', 'Open Numbers and search the live service catalog. Only services returned by Numelixa are shown.'),
        ('04', 'Select a country', 'Choose a country from the live availability list. The server validates the current price and stock when you place an order.'),
        ('05', 'Receive your SMS', 'Open Orders to view your activation. Check for an SMS code while the activation is waiting.'),
        ('06', 'Review your order', 'Use the activation details to see its current status and available actions.'),
      ])
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.$1, style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(width: 13),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.$2, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(item.$3, style: const TextStyle(color: AppTheme.muted, height: 1.45, fontSize: 12)),
          ])),
        ]))),
      const SizedBox(height: 12),
      const Text('Need troubleshooting?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      Card(child: ListTile(leading: const Icon(Icons.sms_failed_outlined, color: AppTheme.warning), title: const Text('SMS has not arrived'), subtitle: const Text('Check the activation status and use Check for SMS code. If it remains unresolved, contact Support.'), isThreeLine: true)),
      Card(child: ListTile(leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.cyan), title: const Text('Payment is pending'), subtitle: const Text('Refresh the payment status in Wallet. Do not submit a duplicate payment while the first request is pending.'), isThreeLine: true)),
      Card(child: ListTile(leading: const Icon(Icons.public_off_rounded, color: AppTheme.muted), title: const Text('No country or number available'), subtitle: const Text('Availability can change. Refresh the country list and try again later.'), isThreeLine: true)),
      const SizedBox(height: 14),
      const Text('Refund information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('Eligible refunds for cancelled, expired or unfulfilled activations are returned to the Numelixa wallet according to the order record and published Refund Policy. Completed activations are generally not refundable. If a payment was charged but the wallet was not credited, do not pay again immediately; contact Support with your payment reference.', style: TextStyle(color: AppTheme.muted, height: 1.5)))),
      const Text('Account help', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Card(child: ListTile(leading: Icon(Icons.verified_user_outlined, color: AppTheme.cyan), title: Text('Verification and sign-in'), subtitle: Text('Check your email verification state, use the password recovery flow, and review active devices from Account → Security.'))),
      const Text('Frequently asked questions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      Card(child: ExpansionTile(title: const Text('Why has my SMS not arrived?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Check that the activation is still waiting and has not expired. Use the SMS refresh action. If the provider reports no code before expiry, contact Support with the order ID.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('Can I cancel an activation?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Cancellation is shown only where the order is eligible. The backend validates the provider and order status; a refund is not complete until the server confirms it.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('Why is a country unavailable?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Stock changes continuously. Refresh the service and country list; only current server availability can be purchased.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      Card(child: ExpansionTile(title: const Text('What should I send to Support?'), children: const [Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: Text('Provide your Numelixa ID and relevant order/payment reference. Never include passwords, OTP codes, recovery codes or full payment-card details.', style: TextStyle(color: AppTheme.muted, height: 1.5)))])),
      FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _SupportCenterPage())), icon: const Icon(Icons.support_agent_rounded), label: const Text('Contact Support')),
    ],
  );
}

class _PartnerCenterPage extends StatelessWidget {
  const _PartnerCenterPage();
  static const _email='support@numelixa.com';
  Future<void> _emailTeam(BuildContext context) async {
    final uri=Uri(scheme:'mailto',path:_email,queryParameters:{'subject':'Numelixa partnership enquiry'});
    if(!await launchUrl(uri)&&context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('No email app is available. Copy the address or use Support online.')));
  }
  @override
  Widget build(BuildContext context)=>_ResourcePageFrame(title:'For Partners',subtitle:'Explore business, technical and integration opportunities with Numelixa.',icon:Icons.handshake_outlined,children:[
    for(final item in const [(Icons.business_outlined,'Business partnerships','For organizations interested in collaboration and platform services.'),(Icons.settings_ethernet_rounded,'API partnerships','For products and platforms evaluating server-to-server integration.'),(Icons.storefront_outlined,'Reseller opportunities','For businesses interested in discussing distribution opportunities.'),(Icons.hub_outlined,'Technical partnerships','For infrastructure, telecom and technology integration enquiries.')])
      Card(child:ListTile(leading:Icon(item.$1,color:AppTheme.cyan),title:Text(item.$2,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text(item.$3,style:const TextStyle(color:AppTheme.muted,height:1.4)),isThreeLine:true)),
    const Card(child:Padding(padding:EdgeInsets.all(15),child:Text('Affiliate programme availability is not confirmed. Contact the team to ask whether a programme is available; this page does not promise commissions or approval.',style:TextStyle(color:AppTheme.muted,height:1.5)))),
    Card(child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Row(children:[Icon(Icons.email_outlined,color:AppTheme.cyan),SizedBox(width:9),Text('Official contact',style:TextStyle(fontWeight:FontWeight.w900))]),
      const SizedBox(height:8),const SelectableText(_email,style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w800)),
      const SizedBox(height:10),Row(children:[
        Expanded(child:OutlinedButton.icon(onPressed:()async{await Clipboard.setData(const ClipboardData(text:_email));if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Email address copied.')));},icon:const Icon(Icons.copy_rounded),label:const Text('Copy email'))),
        const SizedBox(width:9),Expanded(child:FilledButton.icon(onPressed:()=>_emailTeam(context),icon:const Icon(Icons.mail_outline_rounded),label:const Text('Email team'))),
      ]),
      const Text('This is the verified public support address; no separate partner or affiliate email was found.',style:TextStyle(color:AppTheme.muted,fontSize:11,height:1.4)),
    ]))),
    FilledButton.icon(onPressed:()=>launchUrl(Uri.parse('https://support.numelixa.com/'),mode:LaunchMode.externalApplication),icon:const Icon(Icons.support_agent_rounded),label:const Text('Open Support Center')),
  ]);
}


