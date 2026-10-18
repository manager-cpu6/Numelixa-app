import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/numelixa_repository.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _booted = false;

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
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isSignedIn) return const _ApiKeySignIn();
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
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const _NotificationsPage())),
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
          ),
          const SizedBox(width: 6),
        ],
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

class _ApiKeySignIn extends StatefulWidget {
  const _ApiKeySignIn();
  @override
  State<_ApiKeySignIn> createState() => _ApiKeySignInState();
}

class _ApiKeySignInState extends State<_ApiKeySignIn> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await context.read<AuthService>().signInWithApiKey(_controller.text);
      if (mounted) {
        final auth = context.read<AuthService>();
        await context.read<NotificationService>().syncToken(auth);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not connect. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 78, width: 78, alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [Color(0xFF1677FF), Color(0xFF00D9FF)]),
              boxShadow: const [BoxShadow(color: Color(0x331677FF), blurRadius: 28, offset: Offset(0, 8))],
            ),
            child: const Icon(Icons.public_rounded, size: 42, color: Colors.white),
          ),
          const SizedBox(height: 30),
          const Text('Welcome to Numelixa', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.7)),
          const SizedBox(height: 9),
          const Text('Your global virtual numbers, in one secure mobile app.', style: TextStyle(color: Color(0xFFA7B7D0), height: 1.5)),
          const SizedBox(height: 28),
          const Text('Connect your account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Use your personal API key to authenticate with the existing Numelixa API. Your key is stored only in Android secure storage.', style: TextStyle(color: Color(0xFF91A8C4), height: 1.45, fontSize: 13)),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Numelixa API key',
              hintText: 'nx_live_…',
              prefixIcon: Icon(Icons.key_rounded),
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF788C))),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Connect securely'),
          ),
          const SizedBox(height: 16),
          const Text('Email/password login and native Google sign-in require the backend to return a mobile bearer credential. The current web login sets a browser cookie only, so this app will not reuse website cookies.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7185A5), height: 1.5, fontSize: 11)),
        ],
      )),
    ))),
  );
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
      _DataCard(title: 'Available balance', icon: Icons.account_balance_wallet_outlined, path: 'balance'),
      const SizedBox(height: 12),
      const Text('Your workspace', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      const _ActionTile(icon: Icons.public_rounded, title: 'Browse services', subtitle: 'Explore the live catalog', destination: 'catalog'),
      const _ActionTile(icon: Icons.sms_outlined, title: 'Your orders', subtitle: 'View activations and SMS status', destination: 'orders'),
      const _ActionTile(icon: Icons.notifications_none_rounded, title: 'Notifications', subtitle: 'Account and order updates', destination: 'notifications'),
      const SizedBox(height: 14),
      const Text('Information shown here is retrieved from Numelixa APIs. If the service is unavailable, no example balance or order is substituted.', style: TextStyle(color: Color(0xFF7185A5), height: 1.5, fontSize: 12)),
    ]);
  }
}

class _DataCard extends StatefulWidget {
  const _DataCard({required this.title, required this.icon, required this.path});
  final String title, path;
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
  String? _selectedService;
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().services(token: context.read<AuthService>().accessToken); }
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _RetryState(message: snapshot.error.toString(), onRetry: () => setState(_load));
      final raw = snapshot.data?['services'];
      final services = raw is List ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];
      if (services.isEmpty) return _RetryState(message: 'No live services are available right now.', onRetry: () => setState(_load));
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Choose a service', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Live catalog from Numelixa', style: TextStyle(color: Color(0xFF91A8C4))),
        const SizedBox(height: 14),
        for (final service in services)
          Card(child: ListTile(
            leading: const Icon(Icons.verified_user_outlined, color: AppTheme.cyan),
            title: Text((service['name'] ?? service['title'] ?? service['id'] ?? service['code'] ?? 'Service').toString()),
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
  @override
  void initState() { super.initState(); _load(); }
  void _load() { _future = NumelixaRepository().countries(service: widget.service, token: context.read<AuthService>().accessToken); }
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
        return ListView(padding: const EdgeInsets.all(14), children: [
          for (final country in countries)
            Card(child: ListTile(
              leading: Text((country['flag'] ?? '🌐').toString(), style: const TextStyle(fontSize: 25)),
              title: Text((country['name'] ?? country['title'] ?? country['id'] ?? 'Country').toString()),
              subtitle: Text('Stock: ${(country['stock'] is Map ? country['stock']['count'] : country['count']) ?? '—'}'),
              trailing: Text((country['stock'] is Map ? country['stock']['sellCoins'] : null)?.toString() ?? '—', style: const TextStyle(color: AppTheme.cyan, fontWeight: FontWeight.w700)),
            )),
        ]);
      },
    ),
  );
}

class _OrdersPage extends StatelessWidget {
  const _OrdersPage();
  @override
  Widget build(BuildContext context) => _ProtectedListPage(
    title: 'Your orders',
    load: (repo, token) => repo.orders(token: token, limit: 100),
    listKey: 'orders',
    empty: 'No orders found on this account.',
    itemTitle: (item) => '${item['service'] ?? 'Virtual number'} · ${item['phone'] ?? item['phoneNumber'] ?? 'Number pending'}',
    itemSubtitle: (item) => '${item['country'] ?? item['countryCode'] ?? ''}  •  ${item['status'] ?? 'unknown'}',
  );
}

class _WalletPage extends StatelessWidget {
  const _WalletPage();
  @override
  Widget build(BuildContext context) => _ProtectedListPage(
    title: 'Transactions',
    load: (repo, token) => repo.transactions(token: token),
    listKey: 'transactions',
    empty: 'No transactions found.',
    itemTitle: (item) => '${item['description'] ?? item['type'] ?? 'Transaction'}',
    itemSubtitle: (item) => '${item['amount'] ?? 0} coins · ${item['createdAt'] ?? ''}',
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
  const _ProtectedListPage({required this.title, required this.load, required this.listKey, required this.empty, required this.itemTitle, required this.itemSubtitle});
  final String title, listKey, empty;
  final _LoadList load;
  final _ItemText itemTitle, itemSubtitle;
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
            )),
        ]));
      },
    ),
  );
}

class _AccountPage extends StatelessWidget {
  const _AccountPage();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.user ?? const <String, dynamic>{};
    return ListView(padding: const EdgeInsets.all(18), children: [
      const SizedBox(height: 12),
      const CircleAvatar(radius: 34, backgroundColor: Color(0xFF123C64), child: Icon(Icons.person_outline_rounded, size: 35, color: AppTheme.cyan)),
      const SizedBox(height: 12),
      Text((user['name'] ?? 'Numelixa user').toString(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      Text((user['email'] ?? '').toString(), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF91A8C4))),
      const SizedBox(height: 22),
      const Card(child: ListTile(leading: Icon(Icons.verified_user_outlined, color: AppTheme.cyan), title: Text('Secure API session'), subtitle: Text('Bearer credential verified by Numelixa.'))),
      const Card(child: ListTile(leading: Icon(Icons.support_agent_rounded, color: AppTheme.cyan), title: Text('Help & support'), subtitle: Text('support.numelixa.com'))),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: () async { await context.read<AuthService>().logout(); },
        icon: const Icon(Icons.logout_rounded), label: const Text('Sign out'),
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), foregroundColor: const Color(0xFFFF788C)),
      ),
    ]);
  }
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
