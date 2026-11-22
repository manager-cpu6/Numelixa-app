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
  final _fieldController = TextEditingController();
  final _fieldFocus = FocusNode();
  Timer? _timer;
  int _selectedSeconds = 10;
  int _remaining = 10;
  String _testCode = '';
  bool _counting = false;
  bool _preparing = false;
  bool _ready = false;
  bool _passed = false;
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
    _fieldController.clear();
    _fieldFocus.unfocus();
    setState(() {
      _remaining = _selectedSeconds;
      _counting = true;
      _preparing = false;
      _ready = false;
      _passed = false;
      _error = null;
      _testCode = '';
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
        _testCode = code;
        _preparing = false;
        _ready = true;
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _fieldFocus.requestFocus();
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

  void _onCodeChanged(String value) {
    if (!_ready || _passed || value != _testCode) return;
    setState(() => _passed = true);
    HapticFeedback.mediumImpact();
    TapCodeService.instance.clearAdminTestCode().catchError((_) {});
  }

  Future<void> _openTapCodeSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TapCodeSettingsScreen()),
    );
    await _refreshStatus();
  }

  void _reset() {
    _timer?.cancel();
    TapCodeService.instance.clearAdminTestCode().catchError((_) {});
    _fieldController.clear();
    _fieldFocus.unfocus();
    setState(() {
      _counting = false;
      _preparing = false;
      _ready = false;
      _passed = false;
      _testCode = '';
      _error = null;
      _remaining = _selectedSeconds;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    TapCodeService.instance.clearAdminTestCode().catchError((_) {});
    _fieldController.dispose();
    _fieldFocus.dispose();
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
                    'Run a local test to confirm Android can offer and fill a Numelixa OTP suggestion.',
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
                  const Text('Choose when the test OTP should arrive', style: TextStyle(fontWeight: FontWeight.w700)),
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
                        Text(_preparing ? 'Preparing test suggestion…' : 'Waiting for test OTP…'),
                      ],
                    )
                  else if (_passed)
                    const Column(
                      children: [
                        Icon(Icons.check_circle_rounded, color: AppTheme.mint, size: 48),
                        SizedBox(height: 8),
                        Text('Autofill test passed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                        Text('The test code was entered into the focused field.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                      ],
                    )
                  else if (_ready)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('TEST CODE READY', style: TextStyle(color: AppTheme.cyan, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                        const SizedBox(height: 8),
                        const Text('Tap the Numelixa TapCode suggestion above your keyboard to fill this field.', style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.4)),
                        const SizedBox(height: 14),
                        AutofillGroup(
                          child: TextField(
                            controller: _fieldController,
                            focusNode: _fieldFocus,
                            autofocus: true,
                            autofillHints: const ['smsOTPCode'],
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: 6,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: 8),
                            decoration: const InputDecoration(
                              labelText: 'Android OTP test field',
                              hintText: '••••••',
                              counterText: '',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                            ),
                            onChanged: _onCodeChanged,
                          ),
                        ),
                      ],
                    )
                  else
                    const Text(
                      'A temporary six-digit test code will be created after the timer. It does not use a real order or send an SMS.',
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
                          : _ready || _passed
                              ? _reset
                              : _startTest,
                      icon: Icon(_ready || _passed ? Icons.restart_alt_rounded : Icons.play_arrow_rounded),
                      label: Text(_ready || _passed ? 'Run another test' : 'Start test timer'),
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
                  Text('What this test verifies', style: TextStyle(fontWeight: FontWeight.w900)),
                  SizedBox(height: 8),
                  Text(
                    '• Creates a temporary test-only OTP on this device.\n'
                    '• Opens a real Android Autofill-aware field inside Numelixa.\n'
                    '• Keeps the test code unavailable to other apps and real customer orders.\n'
                    '• Removes the test code when you leave this screen or finish the test.',
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
