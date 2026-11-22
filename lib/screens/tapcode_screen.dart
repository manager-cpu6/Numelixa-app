import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/tapcode_service.dart';

class TapCodeSettingsScreen extends StatefulWidget {
  const TapCodeSettingsScreen({super.key});
  @override State<TapCodeSettingsScreen> createState() => _TapCodeSettingsScreenState();
}

class _TapCodeSettingsScreenState extends State<TapCodeSettingsScreen> with WidgetsBindingObserver {
  Map<String, dynamic> _status = const {};
  bool _loading = true, _busy = false, _autoCopy = false;
  bool _overlayPromptShown = false, _pendingOverlayRequest = false;
  String? _error;

  @override void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh().then((_) => _promptForOverlayOnSettingsOpen());
  }

  @override void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOverlayRequest) {
      _pendingOverlayRequest = false;
      _refresh().then((_) async {
        if (_status['overlayPermission'] == true) {
          await TapCodeService.instance.setOverlayEnabled(true);
          await _refresh();
        }
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final values = await Future.wait([
        TapCodeService.instance.status(),
        TapCodeService.instance.autoCopyEnabled(),
      ]);
      if (!mounted) return;
      setState(() {
        _status = values[0] as Map<String, dynamic>;
        _autoCopy = values[1] as bool;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'Native TapCode integration is unavailable in this build.';
      });
    }
  }

  String get _label {
    if (_error != null || _status['available'] == false) return 'Temporarily unavailable';
    if (_status['enabled'] == true && _status['osEnabled'] == true) {
      return _status['hasCodes'] == true ? 'Ready' : 'Enabled';
    }
    if (_status['enabled'] == true) return 'Setup required';
    return 'Not enabled';
  }

  Color get _color => switch (_label) {
    'Ready' => AppTheme.mint,
    'Enabled' => AppTheme.cyan,
    'Setup required' => AppTheme.warning,
    'Temporarily unavailable' => const Color(0xFFFF788C),
    _ => AppTheme.muted,
  };

  Future<void> _promptForOverlayOnSettingsOpen() async {
    if (!mounted || _overlayPromptShown || _status['overlayAvailable'] != true ||
        _status['overlayPermission'] == true) return;
    _overlayPromptShown = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable floating OTP popup?'),
        content: const Text(
          'Numelixa can show a small OTP card above other apps when a code for your active order arrives. '
          'Android requires you to approve “Display over other apps” in system settings. '
          'The popup only shows Numelixa order codes and never reads or controls WhatsApp.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Not now')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _pendingOverlayRequest = true;
              setState(() => _busy = true);
              try {
                final alreadyGranted = await TapCodeService.instance.requestOverlayPermission();
                if (alreadyGranted) {
                  await TapCodeService.instance.setOverlayEnabled(true);
                  await _refresh();
                }
              } catch (_) {
                if (mounted) setState(() => _error = 'Android could not open overlay permission settings.');
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
            child: const Text('Allow floating popup'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableAutofill() async {
    setState(() => _busy = true);
    try {
      await TapCodeService.instance.enable();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open Android Autofill settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disableAutofill() async {
    setState(() => _busy = true);
    try {
      await TapCodeService.instance.disable();
      await TapCodeService.instance.setOverlayEnabled(false);
      await _refresh();
    } catch (_) {
      if (mounted) setState(() => _error = 'TapCode could not be disabled. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifications() async {
    final p = await Permission.notification.status;
    if (!p.isGranted) {
      await context.read<NotificationService>().requestPermission();
    } else {
      await context.read<NotificationService>().openNotificationSettings();
    }
  }

  @override Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Numelixa Autofill')),
      body: const Center(child: CircularProgressIndicator()));
    final enabled = _status['enabled'] == true;
    final osEnabled = _status['osEnabled'] == true;
    final overlayPermission = _status['overlayPermission'] == true;
    final overlayEnabled = _status['overlayEnabled'] == true;
    return Scaffold(
      appBar: AppBar(title: const Text('Numelixa Autofill'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.glassBorder),
            gradient: const LinearGradient(colors: [Color(0xFF102D55), Color(0xFF09172B)]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.bolt_rounded, color: AppTheme.cyan, size: 27),
              SizedBox(width: 10),
              Text('NUMELIXA AUTOFILL', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1)),
            ]),
            const SizedBox(height: 14),
            const Text('Your verification code, right where you need it.',
              style: TextStyle(fontSize: 21, height: 1.25, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Use Android Autofill or an optional floating OTP card without switching apps.',
              style: TextStyle(color: AppTheme.muted, height: 1.45)),
            const SizedBox(height: 18),
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(_label, style: TextStyle(color: _color, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (_status['hasCodes'] == true) const Text('Active code available',
                style: TextStyle(color: AppTheme.mint, fontSize: 11)),
            ]),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: _busy ? null : (enabled && osEnabled ? _disableAutofill : _enableAutofill),
              icon: Icon(enabled && osEnabled ? Icons.power_settings_new_rounded : Icons.security_rounded),
              label: Text(_busy ? 'Please wait…' : enabled && osEnabled ? 'Disable Android Autofill' : 'Set up Android Autofill'),
            )),
          ]),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFFF788C)))),
        const SizedBox(height: 20),
        const _Heading('FLOATING OTP POPUP'),
        Card(child: Column(children: [
          SwitchListTile(
            value: overlayEnabled && overlayPermission,
            onChanged: _busy ? null : (value) async {
              if (value && !overlayPermission) {
                _pendingOverlayRequest = true;
                await TapCodeService.instance.requestOverlayPermission();
                return;
              }
              await TapCodeService.instance.setOverlayEnabled(value);
              await _refresh();
            },
            secondary: const Icon(Icons.picture_in_picture_alt_rounded, color: AppTheme.cyan),
            title: const Text('Show floating OTP popup'),
            subtitle: Text(overlayPermission
              ? 'Permission granted. A compact card can appear when a matching order code arrives.'
              : 'Permission required. Android will ask you to allow display over other apps.'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(overlayPermission ? Icons.verified_user_rounded : Icons.lock_outline_rounded,
              color: overlayPermission ? AppTheme.mint : AppTheme.warning),
            title: Text(overlayPermission ? 'Overlay permission granted' : 'Overlay permission not granted'),
            subtitle: const Text('You can change this permission anytime in Android settings.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              _pendingOverlayRequest = true;
              await TapCodeService.instance.requestOverlayPermission();
            },
          ),
        ])),
        const SizedBox(height: 16),
        const _Heading('HOW TO SET UP'),
        const Card(child: Padding(padding: EdgeInsets.all(15), child: Column(children: [
          _Step('01', 'Enable Android Autofill', 'Choose Numelixa in Android Autofill settings.'),
          _Step('02', 'Allow floating popup', 'Approve Display over other apps when Android asks.'),
          _Step('03', 'Open Activations', 'Refresh active orders so codes can be linked to the right order.'),
          _Step('04', 'Receive your code', 'The floating card appears for a valid cached order code when the app can display overlays.'),
        ]))),
        const SizedBox(height: 16),
        const _Heading('PREFERENCES'),
        Card(child: SwitchListTile(
          value: _autoCopy,
          onChanged: _busy ? null : (value) async {
            await TapCodeService.instance.setAutoCopyEnabled(value);
            if (mounted) setState(() => _autoCopy = value);
          },
          secondary: const Icon(Icons.content_copy_rounded, color: AppTheme.cyan),
          title: const Text('Auto-copy received code'),
          subtitle: const Text('Optional and disabled by default.'),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.notifications_active_outlined, color: AppTheme.cyan),
          title: const Text('OTP arrival notifications'),
          subtitle: const Text('Uses Numelixa notification permission and verification channel.'),
          trailing: const Icon(Icons.chevron_right_rounded), onTap: _notifications,
        )),
        const SizedBox(height: 16),
        const _Heading('PRIVACY & COMPATIBILITY'),
        const Card(child: Padding(padding: EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Info(Icons.verified_user_outlined, 'Your orders only', 'Codes are associated with active orders returned by your signed-in Numelixa account.'),
          _Info(Icons.lock_outline_rounded, 'Encrypted temporary cache', 'OTP data is encrypted with Android Keystore and expires automatically.'),
          _Info(Icons.apps_rounded, 'Compatible fields only', 'Android Autofill suggestions require the other app to expose compatible fields.'),
          _Info(Icons.copy_all_rounded, 'Copy fallback', 'If Autofill is unavailable, Copy remains available from the popup or activation.'),
        ]))),
        const SizedBox(height: 12),
        const Text('Autofill requires Android 8.0 or newer. Floating windows require Android 6.0 or newer and explicit permission. Numelixa never uses Accessibility or forces code entry into another app.',
          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.5)),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text); final String text;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 9),
    child: Text(text, style: const TextStyle(color: AppTheme.muted, fontSize: 11,
      fontWeight: FontWeight.w900, letterSpacing: 1.2)),
  );
}
class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.detail);
  final String number, title, detail;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(number, style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w900)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(detail, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
      ])),
    ]),
  );
}
class _Info extends StatelessWidget {
  const _Info(this.icon, this.title, this.detail);
  final IconData icon; final String title, detail;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppTheme.cyan, size: 20), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(detail, style: const TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45)),
      ])),
    ]),
  );
}
