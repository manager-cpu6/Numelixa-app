import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../core/theme/app_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _booted = false;
  final _pages = const [
    _OverviewPage(), _FeaturePage(title: 'Buy number', icon: Icons.add_call, detail: 'Connects to the Numelixa number-order API when mobile authentication is available.'), 
    _FeaturePage(title: 'Messages', icon: Icons.sms_outlined, detail: 'SMS and order updates will appear here when connected to your account.'),
    _FeaturePage(title: 'Wallet', icon: Icons.account_balance_wallet_outlined, detail: 'Wallet values must always come from the server.')
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_booted) return;
    _booted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = context.read<AuthService>();
      await auth.restore();
      final notifications = context.read<NotificationService>();
      await notifications.initialize(auth: auth);
      await notifications.requestPermission();
      await notifications.syncToken(auth);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(children: [
        Icon(Icons.public, color: AppTheme.mint, size: 25),
        SizedBox(width: 9),
        Text('Numelixa', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -.5)),
      ]),
      actions: [
        IconButton(onPressed: () => setState(() => _index = 2),
          icon: const Icon(Icons.notifications_none_rounded), tooltip: 'Notifications'),
        const SizedBox(width: 6),
      ],
    ),
    body: SafeArea(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: _pages[_index])),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (value) => setState(() => _index = value),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.add_call), label: 'Buy'),
        NavigationDestination(icon: Icon(Icons.sms_outlined), label: 'Messages'),
        NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Wallet'),
      ],
    ),
  );
}

class _OverviewPage extends StatelessWidget {
  const _OverviewPage();
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
    children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: const LinearGradient(colors: [Color(0xFF123C64), Color(0xFF0B1B34), Color(0xFF10162F)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: const Color(0xFF24547B)),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('GLOBAL VIRTUAL NUMBERS', style: TextStyle(color: AppTheme.mint, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
          SizedBox(height: 13),
          Text('Numbers, without\nthe noise.', style: TextStyle(fontSize: 29, height: 1.12, fontWeight: FontWeight.w800)),
          SizedBox(height: 10),
          Text('Your connected space for virtual numbers and verification.', style: TextStyle(color: Color(0xFFB2C7DD), height: 1.45)),
        ]),
      ),
      const SizedBox(height: 20),
      const Text('Quick access', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      const Row(children: [
        Expanded(child: _QuickCard(icon: Icons.add_call, title: 'Buy number', caption: 'Choose a service')),
        SizedBox(width: 12),
        Expanded(child: _QuickCard(icon: Icons.sms_outlined, title: 'Messages', caption: 'View verification')),
      ]),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(17), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, color: AppTheme.cyan),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Secure by design', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 5),
          Text('Account balances and orders must be verified by Numelixa services, never by the app itself.', style: TextStyle(color: Color(0xFF9FB2CA), height: 1.4)),
        ])),
      ]))),
      const SizedBox(height: 14),
      const Text('Mobile account sign-in and live service data require a supported mobile API session. This app does not pretend that browser cookies are mobile tokens.', style: TextStyle(color: Color(0xFF8198B5), height: 1.5, fontSize: 12)),
    ],
  );
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.title, required this.caption});
  final IconData icon;
  final String title;
  final String caption;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: AppTheme.cyan, size: 25),
      const SizedBox(height: 15),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(caption, style: const TextStyle(color: Color(0xFF91A8C4), fontSize: 12)),
    ]),
  ));
}

class _FeaturePage extends StatelessWidget {
  const _FeaturePage({required this.title, required this.icon, required this.detail});
  final String title;
  final IconData icon;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(28),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 74, height: 74, decoration: BoxDecoration(color: AppTheme.panel, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFF23415F))), child: Icon(icon, size: 34, color: AppTheme.cyan)),
      const SizedBox(height: 20),
      Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF9FB2CA), height: 1.5)),
    ]),
  ));
}
