import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/core/theme/app_theme.dart';\nimport 'package:numelixa_app/widgets/service_brand_icon.dart';

void main() {
  test('Numelixa uses the unified dark brand background', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, AppTheme.navy);
    expect(AppTheme.navy, const Color(0xFF050B18));
  });

  test('Numelixa brand tokens use the approved accessible palette', () {
    expect(AppTheme.blue, const Color(0xFF4388FF));
    expect(AppTheme.cyan, const Color(0xFF35D6E3));
    expect(AppTheme.violet, const Color(0xFFA64DFF));
    expect(AppTheme.textPrimary, const Color(0xFFF4F7FC));
    expect(AppTheme.textSecondary, const Color(0xFF98A9C2));
    expect(AppTheme.glassBorder, const Color(0xFF263957));
  });

  test('service brand resolver keeps similar names separate and recognizes requested brands', () {\n    expect(ServiceBrandIcon.canonicalSlug('X/Twitter'), 'x');\n    expect(ServiceBrandIcon.canonicalSlug('Alibaba.com'), 'alibabadotcom');\n    expect(ServiceBrandIcon.canonicalSlug('TikTok/douying'), 'tiktok');\n    expect(ServiceBrandIcon.canonicalSlug('imo'), 'imo');\n    expect(ServiceBrandIcon.canonicalSlug('Microsoft'), 'microsoft');\n    expect(ServiceBrandIcon.canonicalSlug('NovaPošta'), 'novaposhta');\n    expect(ServiceBrandIcon.canonicalSlug('PayPal'), 'paypal');\n    expect(ServiceBrandIcon.canonicalSlug('Moneza'), 'moneza');\n    expect(ServiceBrandIcon.canonicalSlug('Unknown Service'), isNull);\n  });\n\n  test('Material navigation and card styles are defined centrally', () {
    expect(AppTheme.dark.navigationBarTheme.height, 68);
    expect(AppTheme.dark.cardTheme, isNotNull);
    expect(AppTheme.dark.inputDecorationTheme, isNotNull);
  });
}
