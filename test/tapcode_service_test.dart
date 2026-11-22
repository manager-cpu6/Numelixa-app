import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/services/tapcode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.numelixa.app/tapcode');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') {
        return <String, dynamic>{'available': true, 'enabled': true, 'osEnabled': true};
      }
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('syncs only active owned order codes and preserves waiting order association', () async {
    final now = DateTime.now();
    await TapCodeService.instance.syncOrders([
      {
        'id': 'active-with-code',
        'status': 'waiting',
        'service': 'Example',
        'phone': '+12025550100',
        'code': '482916',
        'codeReceivedAt': now.subtract(const Duration(minutes: 1)).toIso8601String(),
        'expiresAt': now.add(const Duration(minutes: 4)).toIso8601String(),
      },
      {
        'id': 'active-waiting',
        'status': 'waiting',
        'service': 'Another app',
        'phone': '+12025550101',
      },
      {
        'id': 'cancelled',
        'status': 'cancelled',
        'code': '123456',
        'codeReceivedAt': now.toIso8601String(),
      },
      {
        'id': 'old-success',
        'status': 'successful',
        'code': '654321',
        'codeReceivedAt': now.subtract(const Duration(minutes: 12)).toIso8601String(),
      },
    ]);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'syncOrders');
    final payload = Map<String, dynamic>.from(calls.single.arguments as Map);
    final active = (payload['activeOrders'] as List).cast<Map>();
    final codes = (payload['orders'] as List).cast<Map>();
    expect(active.map((item) => item['orderId']), containsAll(['active-with-code', 'active-waiting']));
    expect(active.map((item) => item['orderId']), isNot(contains('cancelled')));
    expect(codes, hasLength(1));
    expect(codes.single['orderId'], 'active-with-code');
    expect(codes.single['code'], '482916');
  });

  test('clears the native cache when TapCode is disabled', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getStatus') {
        return <String, dynamic>{'available': true, 'enabled': false};
      }
      calls.add(call);
      return null;
    });
    await TapCodeService.instance.syncOrders([
      {'id': 'private-order', 'status': 'waiting', 'code': '123456'},
    ]);
    expect(calls.any((call) => call.method == 'clearAll'), isTrue);
    expect(calls.any((call) => call.method == 'syncOrders'), isFalse);
  });
}
