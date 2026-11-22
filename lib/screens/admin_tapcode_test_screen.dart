import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../services/tapcode_service.dart';
import 'tapcode_screen.dart';

class AdminTapCodeTestScreen extends StatefulWidget {
  const AdminTapCodeTestScreen({super.key});

  @override
  State<AdminTapCodeTestScreen> createState() => _AdminTapCodeTestScreenState();
}

class _AdminTapCodeTestScreenState extends State<AdminTapCodeTestScreen> {
  Timer? _timer;
  int _selectedSeconds = 10;
  int _remaining = 10;
  bool _counting = false;
  bool _preparing = false;
  bool _ready = false;
  String? _error;
  Map<String, dynamic> _status = const {};

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await TapCodeService.instance.status();
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _status = const {'available': false});
    }
  }

  void _startTest() {
    _timer?.cancel();
    TapCodeService.instance.clearAdminTestCode().catchError((_) {});
    setState(() {
      _remaining = _selectedSeconds;
      _counting = true;
      _preparing = false;
      _ready = false;
      _error = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 1) {
        timer.cancel();
        _prepareTestCode();
      } else if (mounted) {
        setState(() => _remaining--);
      }
    });
  }

  Future<void> _prepareTestCode() async {
    if (!mounted) return;
    setState(() {
      _counting = false;
      _preparing = true;
      _remaining = 0;
    });
    final code = (Random.secure().nextInt(900000) + 100000).toString();
    try {
      await TapCodeService.instance.createAdminTestCode(code);
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _ready = true;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() {
        _preparing = false;
        _error = e.message ?? 'TapCode could not prepare the test code.';
      });
    } catch (_) {
      if (mounted) setState(() {
        _preparing = false;
        _error = 'TapCode could not prepare the test code.';
      });
    }
  }

  Future<void> _clearTest() async {
    _timer?.cancel();
    await TapCodeService.instance.clearAdminTestCode();
    if (!mounted) return;
    setState(() {
      _counting = false;
      _preparing = false;
      _ready = false;
      _remaining = _selectedSeconds;
      _error = null;
    });
  }

  Future<void> _openTapCodeSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TapCodeSettingsScreen()),
    );
    await _refreshStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Deliberately keep a ready test code when this screen/app is closed.
    // Android Autofill must be able to offer it inside another app.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nativeReady = _status['available'] == true &&
        _status['enabled'] == true &&
        _status['osEnabled'] == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test OTP for admin'),
        actions: [
          IconButton(
            tooltip: 'Refresh status',
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.password_rounded, color: AppTheme.cyan, size: 27),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'NUMELIXA TAPCODE',
                          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                      ),
                      Icon(Icons.verified_user_outlined, color: AppTheme.mint),
                    ],
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'TapCode keeps OTP suggestions ready for other apps. It does not open its own OTP screen.',
                    style: TextStyle(color: AppTheme.muted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(
                        nativeReady ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                        color: nativeReady ? AppTheme.mint : AppTheme.cyan,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          nativeReady
                              ? 'TapCode and Android Autofill are enabled'
                              : _status['enabled'] == true
                                  ? 'Select Numelixa in Android Autofill settings'
                                  : 'TapCode setup is required before testing',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (!nativeReady) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _openTapCodeSettings,
                      icon: const Icon(Icons.settings_rounded),
                      label: const Text('Open TapCode setup'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'TEST TIMER',
            style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.2),
          ),
          const SizedBox(height: 9),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Choose when the test suggestion becomes available', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final seconds in [1, 10, 30])
                        ChoiceChip(
                          label: Text('$seconds sec'),
                          selected: _selectedSeconds == seconds,
                          onSelected: _counting || _preparing || _ready
                              ? null
                              : (_) => setState(() {
                                    _selectedSeconds = seconds;
                                    _remaining = seconds;
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_counting || _preparing)
                    Column(
                      children: [
                        SizedBox(
                          width: 82,
                          height: 82,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: _counting ? _remaining / _selectedSeconds : null,
                                strokeWidth: 5,
                                backgroundColor: AppTheme.muted.withOpacity(.16),
                                color: AppTheme.cyan,
                              ),
                              Center(
                                child: Text(
                                  _preparing ? '…' : '$_remaining',
                                  style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(_preparing ? 'Preparing the external Autofill suggestion…' : 'Waiting for test OTP…'),
                      ],
                    )
                  else if (_ready)
                    const Column(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 48),
                        SizedBox(height: 8),
                        Text('TEST OTP READY', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        SizedBox(height: 8),
                        Text(
                          'Now leave Numelixa and open another app or website with an OTP field. Tap that field. Android should show the Numelixa TapCode suggestion in its Autofill bar or bottom sheet.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.5),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'The temporary test suggestion remains available for up to 3 minutes, even after Numelixa is closed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.muted, fontSize: 11, height: 1.45),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'This test creates a temporary OTP for Android Autofill. It does not create a text field inside Numelixa or send a real SMS.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.45),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Color(0xFFFF788C), fontSize: 12)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _counting || _preparing
                          ? null
                          : _ready
                              ? _clearTest
                              : _startTest,
                      icon: Icon(_ready ? Icons.delete_outline_rounded : Icons.play_arrow_rounded),
                      label: Text(_ready ? 'Clear test suggestion' : 'Start test timer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How the real feature works', style: TextStyle(fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  Text(
                    '• A real OTP received for an active Numelixa order is securely stored on this device.\n'
                    '• When you focus an OTP field in another app, Android asks Numelixa TapCode for suggestions.\n'
                    '• Choose the Numelixa suggestion in the system Autofill bar or bottom sheet to fill the code.\n'
                    '• Android and the other app control when the Autofill prompt appears; Numelixa does not force a popup over other apps.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.55),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
