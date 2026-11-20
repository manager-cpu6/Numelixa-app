import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Uses locally bundled vector brand glyphs only. Unknown services are omitted
/// from the customer catalog rather than showing a misleading placeholder.
class ServiceBrandIcon extends StatelessWidget {
  const ServiceBrandIcon({super.key, required this.name, this.id, this.size = 46});
  final String name;
  final String? id;

  static String canonicalKey(String name, String? id) {
    final raw = (id?.trim().isNotEmpty == true ? id! : name).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceFirst(RegExp(r'\\d+$'), '');
    const aliases = <String,String>{
      'wa':'whatsapp','tg':'telegram','tt':'tiktok','douyin':'tiktok','ig':'instagram','fb':'facebook',
      'go':'google','gm':'gmail','yt':'youtube','ms':'microsoft','ds':'discord','sn':'snapchat',
      'tw':'x','twitter':'x','li':'linkedin','pp':'paypal','rd':'reddit','sp':'spotify','nf':'netflix',
      'vb':'viber','sg':'signal','gplay':'googleplay','googleplaystore':'googleplay','gpay':'googlepay',
    };
    return aliases[raw] ?? raw;
  }

  static bool supports(String name, String? id) => _brandIcon(canonicalKey(id ?? '', null)) != null || _brandIcon(canonicalKey(name, null)) != null;

  static IconData? _brandIcon(String key) {
    switch (key) {
      case 'whatsapp': return FontAwesomeIcons.whatsapp;
      case 'telegram': return FontAwesomeIcons.telegram;
      case 'tiktok': return FontAwesomeIcons.tiktok;
      case 'instagram': return FontAwesomeIcons.instagram;
      case 'facebook': return FontAwesomeIcons.facebook;
      case 'googleplay': return FontAwesomeIcons.googlePlay;
      case 'googlepay': return FontAwesomeIcons.googlePay;
      case 'google': case 'googlevoice': case 'gmail': return FontAwesomeIcons.google;
      case 'youtube': return FontAwesomeIcons.youtube;
      case 'microsoft': case 'microsoftteams': return FontAwesomeIcons.microsoft;
      case 'discord': return FontAwesomeIcons.discord;
      case 'snapchat': return FontAwesomeIcons.snapchat;
      case 'x': return FontAwesomeIcons.xTwitter;
      case 'linkedin': return FontAwesomeIcons.linkedin;
      case 'paypal': return FontAwesomeIcons.paypal;
      case 'reddit': return FontAwesomeIcons.reddit;
      case 'spotify': return FontAwesomeIcons.spotify;
      case 'netflix': return FontAwesomeIcons.netflix;
      case 'amazon': return FontAwesomeIcons.amazon;
      case 'apple': return FontAwesomeIcons.apple;
      case 'signal': return FontAwesomeIcons.signalMessenger;
      case 'viber': return FontAwesomeIcons.viber;
      case 'wechat': return FontAwesomeIcons.weixin;
      case 'line': return FontAwesomeIcons.line;
      case 'pinterest': return FontAwesomeIcons.pinterest;
      case 'twitch': return FontAwesomeIcons.twitch;
      case 'steam': return FontAwesomeIcons.steam;
      case 'uber': return FontAwesomeIcons.uber;
      case 'airbnb': return FontAwesomeIcons.airbnb;
      case 'yahoo': return FontAwesomeIcons.yahoo;
      case 'tinder': return FontAwesomeIcons.tinder;
      case 'dropbox': return FontAwesomeIcons.dropbox;
      case 'slack': return FontAwesomeIcons.slack;
      case 'zoom': return FontAwesomeIcons.zoom;
      case 'canva': return FontAwesomeIcons.canva;
      case 'figma': return FontAwesomeIcons.figma;
      case 'openai': case 'chatgpt': return FontAwesomeIcons.openai;
      case 'capcut': return FontAwesomeIcons.cut;
      case 'threads': return FontAwesomeIcons.threads;
      case 'vk': return FontAwesomeIcons.vk;
      case 'yandex': return FontAwesomeIcons.yandex;
      case 'coinbase': return FontAwesomeIcons.coinbase;
      case 'aliexpress': return FontAwesomeIcons.alipay;
      case 'ebay': return FontAwesomeIcons.ebay;
      case 'bolt': return FontAwesomeIcons.bolt;
      case 'grab': return FontAwesomeIcons.grab;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final idKey = canonicalKey(id ?? '', null);
    final key = _brandIcon(idKey) != null ? idKey : canonicalKey(name, null);
    final icon = _brandIcon(key);
    if (icon == null) return const SizedBox.shrink();
    final color = switch (key) {
      'whatsapp' => const Color(0xFF25D366),
      'telegram' => const Color(0xFF2AABEE),
      'tiktok' => Colors.white,
      'instagram' => const Color(0xFFE66A9A),
      'facebook' => const Color(0xFF1877F2),
      'google' || 'googlevoice' || 'gmail' => const Color(0xFF4285F4),
      'youtube' => const Color(0xFFFF0033),
      'microsoft' || 'microsoftteams' => const Color(0xFF00A4EF),
      'discord' => const Color(0xFF5865F2),
      'snapchat' => const Color(0xFFFFE500),
      'spotify' => const Color(0xFF1DB954),
      'netflix' => const Color(0xFFE50914),
      'apple' => Colors.white,
      _ => const Color(0xFFDCE8F8),
    };
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF102844),
        borderRadius: BorderRadius.circular(size * .25),
        border: Border.all(color: const Color(0xFF29425F)),
      ),
      child: FaIcon(icon, size: size * .49, color: color),
    );
  }
}
