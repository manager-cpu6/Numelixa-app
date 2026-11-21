import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/services/app_update_service.dart';

void main() {
  test('legacy app update check uses the canonical no-redirect host', () {
    expect(numelixaUpdateApiUrl, 'https://www.numelixa.com/api/app-update');
    expect(numelixaLatestApkUrl, 'https://www.numelixa.com/api/mobile/apk');
  });
}
