import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Displays a local brand mark when available, otherwise resolves official
/// transparent SVG marks from the Simple Icons catalogue.
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
    'x':'x','twitter':'x','tw':'x','threads':'threads','linkedin':'linkedin',
    'reddit':'reddit','spotify':'spotify','netflix':'netflix','amazon':'amazon',
    'apple':'apple','paypal':'paypal','viber':'viber','signal':'signal',
    'wechat':'wechat','line':'line','kakaotalk':'kakaotalk','imo':'imo',
    'pinterest':'pinterest','twitch':'twitch','steam':'steam','uber':'uber',
    'airbnb':'airbnb','yahoo':'yahoo','binance':'binance','aliexpress':'aliexpress',
    'ebay':'ebay','microsoftteams':'microsoftteams','telegramx':'telegram',
    'olx':'olx','tinder':'tinder','bumble':'bumble','grab':'grab','bolt':'bolt',
    'openai':'openai','chatgpt':'openai','claude':'claude','capcut':'capcut',
    'dropbox':'dropbox','slack':'slack','zoom':'zoom','notion':'notion',
    'canva':'canva','figma':'figma','protonmail':'protonmail','proton':'proton',
    'xbox':'xbox','playstation':'playstation','epicgames':'epicgames','roblox':'roblox',
    'coinbase':'coinbase','kucoin':'kucoin','bybit':'bybit','okx':'okx','bitget':'bitget',
    'shopee':'shopee','rakuten':'rakuten','disneyplus':'disneyplus','hulu':'hulu',
    'booking':'bookingdotcom','bookingcom':'bookingdotcom','expedia':'expedia',
    'agoda':'agoda','skype':'skype','vkontakte':'vk','vk':'vk','yandex':'yandex',
    'googlevoice':'googlevoice',
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

  static String _slugFor(String name, {String? id}) {
    final raw = _key(name);
    if (raw.isNotEmpty) return _aliases[raw] ?? raw;
    final fallback = _key(id ?? '');
    return _aliases[fallback] ?? fallback;
  }

  static String? canonicalKey(String name, {String? id}) {
    final rawName = _key(name);
    final nameKey = _aliases[rawName] ?? rawName;
    if (_brands.containsKey(nameKey)) return nameKey;
    final keys = _brands.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final key in keys) {
      if (!rawName.startsWith(key)) continue;
      final suffix = rawName.substring(key.length);
      if (suffix.isEmpty || const ['verification', 'otp', 'sms', 'activation'].contains(suffix)) return key;
    }
    if (rawName.isEmpty || rawName == _key(id ?? '')) {
      final idKey = _aliases[_key(id ?? '')] ?? _key(id ?? '');
      if (_brands.containsKey(idKey)) return idKey;
    }
    return null;
  }

  static bool hasVerifiedIcon(String name, {String? id}) =>
      canonicalKey(name, id: id) != null || _slugFor(name, id: id).isNotEmpty;

  String _initials() {
    final words = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words.first.substring(0, 1) + words.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final key = canonicalKey(name, id: id);
    final localIcon = key == null ? null : _brands[key];
    if (localIcon != null) {
      return Center(child: FaIcon(localIcon, size: size * .66, color: _brandColor(key!)));
    }
    final slug = _slugFor(name, id: id);
    if (slug.isEmpty) {
      return Center(child: Text(_initials(), style: TextStyle(color: Colors.white70, fontSize: size * .30, fontWeight: FontWeight.w900)));
    }
    return Center(
      child: SvgPicture.network(
        'https://cdn.simpleicons.org/$slug',
        width: size * .78,
        height: size * .78,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Text(_initials(), style: TextStyle(color: Colors.white70, fontSize: size * .30, fontWeight: FontWeight.w900)),
        errorBuilder: (_, __, ___) => Text(_initials(), style: TextStyle(color: Colors.white70, fontSize: size * .30, fontWeight: FontWeight.w900)),
      ),
    );
  }

  static Color _brandColor(String key) {
    const colors = <String, Color>{
      'whatsapp': Color(0xFF25D366), 'telegram': Color(0xFF2AABEE),
      'tiktok': Colors.white, 'instagram': Color(0xFFE1306C),
      'facebook': Color(0xFF1877F2), 'google': Color(0xFF4285F4),
      'googleplay': Color(0xFF34A853), 'googlepay': Color(0xFF4285F4),
      'youtube': Color(0xFFFF0033), 'microsoft': Color(0xFFF25022),
      'snapchat': Color(0xFFFFFC00), 'discord': Color(0xFF5865F2),
    };
    return colors[key] ?? Colors.white;
  }
}
