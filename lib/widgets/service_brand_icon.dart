import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Brand marks are resolved from an explicit, reviewed catalogue. Unknown
/// service IDs never become random Simple Icons slugs or misleading initials.
class ServiceBrandIcon extends StatelessWidget {
  const ServiceBrandIcon({super.key, required this.name, this.id, this.size = 46});
  final String name;
  final String? id;
  final double size;

  static String _key(String value) => value.toLowerCase().replaceAll('š', 's').replaceAll('Š', 's').replaceAll(RegExp(r'[^a-z0-9]'), '');

  static const Map<String, String> _aliases = {
    'wa':'whatsapp','whatsapp':'whatsapp','whatsappbusiness':'whatsapp',
    'tg':'telegram','telegram':'telegram','tt':'tiktok','tiktok':'tiktok','tiktokdouyin':'tiktok',
    'douyin':'douyin','douying':'douyin','ig':'instagram','instagram':'instagram',
    'fb':'facebook','facebook':'facebook','go':'google','google':'google','gm':'gmail','gmail':'gmail',
    'yt':'youtube','youtube':'youtube','ms':'microsoft','msft':'microsoft','microsoft':'microsoft',
    'ds':'discord','discord':'discord','sn':'snapchat','snapchat':'snapchat',
    'x':'x','tw':'x','twitter':'x','threads':'threads','linkedin':'linkedin',
    'reddit':'reddit','spotify':'spotify','netflix':'netflix','amazon':'amazon',
    'alibaba':'alibabadotcom','alibabacom':'alibabadotcom','alibabadotcom':'alibabadotcom',
    'alibabacloud':'alibabacloud','apple':'apple','paypal':'paypal','viber':'viber',
    'signal':'signal','wechat':'wechat','line':'line','kakaotalk':'kakaotalk','imo':'imo',
    'pinterest':'pinterest','twitch':'twitch','steam':'steam','uber':'uber','airbnb':'airbnb',
    'yahoo':'yahoo','binance':'binance','aliexpress':'aliexpress','ebay':'ebay',
    'microsoftteams':'microsoftteams','telegramx':'telegram','olx':'olx','tinder':'tinder',
    'bumble':'bumble','grab':'grab','bolt':'bolt','openai':'openai','chatgpt':'chatgpt',
    'claude':'claude','capcut':'capcut','dropbox':'dropbox','slack':'slack','zoom':'zoom',
    'notion':'notion','canva':'canva','figma':'figma','protonmail':'protonmail',
    'proton':'proton','xbox':'xbox','playstation':'playstation','epicgames':'epicgames',
    'roblox':'roblox','coinbase':'coinbase','kucoin':'kucoin','bybit':'bybit','okx':'okx',
    'bitget':'bitget','shopee':'shopee','rakuten':'rakuten','disneyplus':'disneyplus',
    'hulu':'hulu','booking':'bookingdotcom','bookingcom':'bookingdotcom','expedia':'expedia',
    'agoda':'agoda','skype':'skype','vkontakte':'vk','vk':'vk','yandex':'yandex',
    'googlevoice':'googlevoice','zupee':'zupee','huya':'huya','moneza':'moneza',
    'miratorg':'miratorg','novaposhta':'novaposhta','novaposta':'novaposhta','novapoahta':'novaposhta'
  };

  static const Map<String, String> _domains = {
    'imo':'imo.im','moneza':'moneza.com','miratorg':'miratorg.ru',
    'douyin':'douyin.com','novaposhta':'novaposhta.ua'
  };

  static const Map<String, IconData> _brands = {
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

  static String? canonicalSlug(String name, {String? id}) {
    final rawName = _key(name);
    final rawId = _key(id ?? '');
    for (final value in [rawName, rawId]) {
      if (_aliases.containsKey(value)) return _aliases[value];
    }
    if (rawName.contains('tiktok')) return 'tiktok';
    if (rawName.contains('douyin') || rawName.contains('douying')) return 'douyin';
    return null;
  }

  static String? canonicalKey(String name, {String? id}) {
    final slug = canonicalSlug(name, id: id);
    return slug != null && _brands.containsKey(slug) ? slug : null;
  }

  static bool hasVerifiedIcon(String name, {String? id}) =>
      canonicalSlug(name, id: id) != null;

  @override
  Widget build(BuildContext context) {
    final slug = canonicalSlug(name, id: id);
    if (slug == null) return SizedBox(width: size, height: size);
    final localIcon = _brands[slug];
    if (localIcon != null) {
      return SizedBox(width: size, height: size,
        child: Center(child: FaIcon(localIcon, size: size * .66, color: _brandColor(slug))));
    }
    final domain = _domains[slug];
    if (domain != null) {
      return SizedBox(width: size, height: size,
        child: Center(child: Image.network(
          'https://www.google.com/s2/favicons?domain=$domain&sz=128',
          width: size * .72, height: size * .72, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        )));
    }
    return SizedBox(width: size, height: size,
      child: Center(child: SvgPicture.network(
        'https://cdn.simpleicons.org/$slug',
        width: size * .78, height: size * .78, fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.shrink(),
        errorBuilder: (_, __, ___) {
          final fallbackDomain = _domains[slug];
          if (fallbackDomain == null) return const SizedBox.shrink();
          return Image.network('https://www.google.com/s2/favicons?domain=$fallbackDomain&sz=128',
            width: size * .72, height: size * .72, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink());
        },
      )));
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

extension on String {
  String normalizeNfkd() {
    // The current brand IDs are ASCII; this identity extension keeps the
    // normalization pipeline deterministic without adding dependencies.
    return this;
  }
}
