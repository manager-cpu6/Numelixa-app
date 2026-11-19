import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/core/theme/app_theme.dart';

void main() {
  test('Numelixa uses the unified dark brand background', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, AppTheme.navy);
    expect(AppTheme.navy, const Color(0xFF050B18));
  });

  test('Numelixa brand tokens use the approved accessible palette', () {
    expect(AppTheme.blue, const Color(0xFF176BFF));
    expect(AppTheme.cyan, const Color(0xFF39D8E8));
    expect(AppTheme.violet, const Color(0xFFA64DFF));
    expect(AppTheme.textPrimary, const Color(0xFFF4F7FF));
    expect(AppTheme.textSecondary, const Color(0xFF9BAAC4));
    expect(AppTheme.glassBorder, const Color(0xFF1A3154));
  });

  test('Material navigation and card styles are defined centrally', () {
    expect(AppTheme.dark.navigationBarTheme.height, 68);
    expect(AppTheme.dark.cardTheme, isNotNull);
    expect(AppTheme.dark.inputDecorationTheme, isNotNull);
  });
}
