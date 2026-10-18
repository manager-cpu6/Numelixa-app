import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/core/theme/app_theme.dart';

void main() {
  test('Numelixa dark theme has expected background', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, AppTheme.navy);
  });
}
