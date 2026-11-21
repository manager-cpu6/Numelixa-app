import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:numelixa_app/core/theme/app_theme.dart';
import 'package:numelixa_app/widgets/service_brand_icon.dart';

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

  test('service brand resolver keeps similar names separate and recognizes requested brands', () {
    expect(ServiceBrandIcon.canonicalSlug('X/Twitter'), 'x');
    expect(ServiceBrandIcon.canonicalSlug('Alibaba.com'), 'alibabadotcom');
    expect(ServiceBrandIcon.canonicalSlug('TikTok/douying'), 'tiktok');
    expect(ServiceBrandIcon.canonicalSlug('imo'), 'imo');
    expect(ServiceBrandIcon.canonicalSlug('Microsoft'), 'microsoft');
    expect(ServiceBrandIcon.canonicalSlug('NovaPošta'), 'novaposhta');
    expect(ServiceBrandIcon.canonicalSlug('PayPal'), 'paypal');
    expect(ServiceBrandIcon.canonicalSlug('Moneza'), 'moneza');
    expect(ServiceBrandIcon.canonicalSlug('Unknown Service'), isNull);\n    expect(ServiceBrandIcon.canonicalSlug('Unknown Service', id: 'ms'), isNull);
  });

  test('Material navigation and card styles are defined centrally', () {
    expect(AppTheme.dark.navigationBarTheme.height, 68);
    expect(AppTheme.dark.cardTheme, isNotNull);
    expect(AppTheme.dark.inputDecorationTheme, isNotNull);
  });
}
