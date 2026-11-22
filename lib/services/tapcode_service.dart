import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TapCodeService {
  TapCodeService._();
  static final instance = TapCodeService._();
  static const _channel = MethodChannel('com.numelixa.app/tapcode');
  static const _storage = FlutterSecureStorage();

  Future<Map<String, dynamic>> status() async =>
      await _channel.invokeMapMethod<String, dynamic>('getStatus') ?? const {'available': false};

  Future<void> enable() => _channel.invokeMethod<void>('enableTapCode');
  Future<void> disable() => _channel.invokeMethod<void>('disableTapCode');
  Future<void> clearAll() => _channel.invokeMethod<void>('clearAll');
  Future<void> clearOrder(String orderId) => _channel.invokeMethod<void>('clearOrder', {'orderId': orderId});
  Future<bool> autoCopyEnabled() async =>
      (await _storage.read(key: 'numelixa_tapcode_auto_copy')) == 'true';
  Future<void> setAutoCopyEnabled(bool value) async {
    if (value) {
      await _storage.write(key: 'numelixa_tapcode_auto_copy', value: 'true');
    } else {
      await _storage.delete(key: 'numelixa_tapcode_auto_copy');
    }
  }

  Future<void> syncOrders(List<Map<String, dynamic>> orders) async {
    final current = await status();
    if (current['enabled'] != true) {
      await _channel.invokeMethod<void>('clearAll');
      return;
    }
    final now = DateTime.now();
    final entries = <Map<String, dynamic>>[];
    for (final order in orders) {
      final status = (order['status'] ?? '').toString().toLowerCase();
      if (['cancel', 'fail', 'expir', 'success', 'complete', 'finish'].any(status.contains)) continue;
      final id = (order['id'] ?? order['_id'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      var code = (order['code'] ?? order['smsCode'] ?? '').toString().trim();
      if (!RegExp(r'^\d{4,8}$').hasMatch(code)) {
        code = RegExp(r'(?<!\d)\d{4,8}(?!\d)').firstMatch((order['fullSms'] ?? '').toString())?.group(0) ?? '';
      }
      if (!RegExp(r'^\d{4,8}$').hasMatch(code)) continue;
      final received = DateTime.tryParse((order['codeReceivedAt'] ?? order['smsReceivedAt'] ?? order['receivedAt'] ?? order['updatedAt'] ?? order['createdAt'] ?? '').toString());
      if (received == null) continue;
      var expiry = received.add(const Duration(minutes: 10));
      final orderExpiry = DateTime.tryParse((order['expiresAt'] ?? order['expires_at'] ?? '').toString());
      if (orderExpiry != null && orderExpiry.isBefore(expiry)) expiry = orderExpiry;
      if (!expiry.isAfter(now)) continue;
      entries.add({
        'orderId': id, 'code': code,
        'service': (order['service'] ?? 'Virtual number').toString(),
        'phone': (order['phone'] ?? order['phoneNumber'] ?? order['number'] ?? '').toString(),
        'expiresAt': expiry.millisecondsSinceEpoch,
      });
      if (entries.length == 10) break;
    }
    await _channel.invokeMethod<void>('syncOrders', {'orders': entries});
  }

  Future<void> cachePushOtp(Map<String, dynamic> data) async {
    final id = (data['orderId'] ?? '').toString().trim();
    final code = (data['code'] ?? data['otp'] ?? data['verificationCode'] ?? data['smsCode'] ?? '').toString().trim();
    if (id.isEmpty || !RegExp(r'^\d{4,8}$').hasMatch(code)) return;
    await _channel.invokeMethod<void>('cachePushOtp', {'orderId': id, 'code': code});
  }
}
