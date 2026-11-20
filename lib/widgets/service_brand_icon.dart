import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Local vector brand marks for services whose identity is explicitly verified.
/// Unknown services are intentionally omitted from the catalogue.
class ServiceBrandIcon extends StatelessWidget {
  const ServiceBrandIcon({super.key, required this.name, this.id, this.size = 46});
  final String name;
  final String? id;
  final double size;

  static String _key(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static const Map<String, String> _aliases = {
    'wa':'whatsapp','tg':'telegram','tt':'tiktok','ig':'instagram','fb':'facebook',
    'go':'google','gm':'gmail','yt':'youtube','ms':'microsoft','ds':'discord',
    'sn':'snapchat','googleplaystore':'googleplay','gplay':'googleplay',
    'gpay':'googlepay','googlepay':'googlepay','msft':'microsoft',
  };

  static final Map<String, IconData> _brands = {
    'whatsapp': FontAwesomeIcons.whatsapp,
    'telegram': FontAwesomeIcons.telegram,
    'tiktok': FontAwesomeIcons.tiktok,
    'instagram': FontAwesomeIcons.instagram,
    'facebook': FontAwesomeIcons.facebook,
    'google': FontAwesomeIcons.google,
    'googleplay': FontAwesomeIcons.googlePlay,
    'googlepay': FontAwesomeIcons.googlePay,
    'youtube': FontAwesomeIcons.youtube,
    'microsoft': FontAwesomeIcons.microsoft,
    'snapchat': FontAwesomeIcons.snapchat,
    'discord': FontAwesomeIcons.discord,
  };

  static const Map<String, Color> _colors = {
    'whatsapp': Color(0xFF25D366),
    'telegram': Color(0xFF2AABEE),
    'tiktok': Color(0xFFFFFFFF),
    'instagram': Color(0xFFE1306C),
    'facebook': Color(0xFF1877F2),
    'google': Color(0xFF4285F4),
    'googleplay': Color(0xFF34A853),
    'googlepay': Color(0xFF4285F4),
    'youtube': Color(0xFFFF0033),
    'microsoft': Color(0xFFF25022),
    'snapchat': Color(0xFFFFFC00),
    'discord': Color(0xFF5865F2),
  };

  static String? canonicalKey(String name, {String? id}) {
    final rawName = _key(name);
    final nameKey = _aliases[rawName] ?? rawName;
    if (_brands.containsKey(nameKey)) return nameKey;
    // Match the most specific complete brand prefix before generic brands (Google).
    final keys = _brands.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (!rawName.startsWith(key)) continue;
      final suffix = rawName.substring(key.length);
      if (suffix.isEmpty || const ['verification', 'otp', 'sms', 'activation'].contains(suffix)) {
        return key;
      }
    }
    // Use a short provider code only when the displayed name is itself that code.
    final rawId = _key(id ?? '');
    if (rawName.isEmpty || rawName == rawId || _aliases.containsKey(rawName)) {
      final idKey = _aliases[rawId] ?? rawId;
      if (_brands.containsKey(idKey)) return idKey;
    }
    return null;
  }

  static bool hasVerifiedIcon(String name, {String? id}) => canonicalKey(name, id: id) != null;

  @override
  Widget build(BuildContext context) {
    final key = canonicalKey(name, id: id);
    if (key == null) return const SizedBox.shrink();
    final icon = _brands[key]!;
    final color = _colors[key]!;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF101D32),
        borderRadius: BorderRadius.circular(size * .25),
        border: Border.all(color: const Color(0x263E638C)),
      ),
      child: FaIcon(icon, size: size * .53, color: color),
    );
  }
}
