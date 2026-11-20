import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class ServiceBrandIcon extends StatelessWidget {
  const ServiceBrandIcon({super.key, required this.name, this.id, this.size = 46});
  final String name;
  final String? id;
  final double size;

  static const Map<String,String> _aliases={
    'wa':'whatsapp','tg':'telegram','tt':'tiktok','ig':'instagram','fb':'facebook',
    'go':'google','gm':'gmail','yt':'youtube','ms':'microsoft','ds':'discord',
    'sn':'snapchat','tw':'x','li':'linkedin','pp':'paypal','rd':'reddit',
    'sp':'spotify','nf':'netflix','vb':'viber','sg':'signal','ap':'apple','am':'amazon',
  };
  static const Map<String,String> _domains={
    'whatsapp':'whatsapp.com','telegram':'telegram.org','tiktok':'tiktok.com',
    'instagram':'instagram.com','facebook':'facebook.com','google':'google.com',
    'googlevoice':'voice.google.com','gmail':'mail.google.com','youtube':'youtube.com',
    'microsoft':'microsoft.com','microsoftteams':'teams.microsoft.com','discord':'discord.com',
    'snapchat':'snapchat.com','x':'x.com','twitter':'x.com','signal':'signal.org',
    'viber':'viber.com','wechat':'wechat.com','line':'line.me','imo':'imo.im',
    'paypal':'paypal.com','binance':'binance.com','reddit':'reddit.com','netflix':'netflix.com',
    'amazon':'amazon.com','apple':'apple.com','spotify':'spotify.com','linkedin':'linkedin.com',
    'pinterest':'pinterest.com','twitch':'twitch.tv','steam':'steampowered.com','uber':'uber.com',
    'airbnb':'airbnb.com','yahoo':'yahoo.com','kakaotalk':'kakao.com','tinder':'tinder.com',
    'bumble':'bumble.com','shopee':'shopee.com','dropbox':'dropbox.com','slack':'slack.com',
    'zoom':'zoom.us','notion':'notion.so','canva':'canva.com','figma':'figma.com',
    'openai':'openai.com','chatgpt':'chatgpt.com','capcut':'capcut.com','threads':'threads.net',
    'vk':'vk.com','yandex':'yandex.com','protonmail':'proton.me','coinbase':'coinbase.com',
    'bybit':'bybit.com','okx':'okx.com','kucoin':'kucoin.com','bitget':'bitget.com',
    'aliexpress':'aliexpress.com','ebay':'ebay.com','olx':'olx.com','bolt':'bolt.eu',
    'grab':'grab.com','booking':'booking.com','expedia':'expedia.com','agoda':'agoda.com',
    'disneyplus':'disneyplus.com','hulu':'hulu.com',
  };

  @override
  Widget build(BuildContext context) {
    final raw=(id??name).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'),'').replaceFirst(RegExp(r'\d+$'),'');
    final key=_aliases[raw]??raw;
    String? domain=_domains[key];
    if(domain==null){
      for(final entry in _domains.entries){if(key.startsWith(entry.key)&&entry.key.length>=3){domain=entry.value;break;}}
    }
    return Container(
      width:size,height:size,
      decoration:BoxDecoration(color:const Color(0xFF102844),borderRadius:BorderRadius.circular(size*.28)),
      alignment:Alignment.center,
      child:domain==null
        ?Icon(Icons.apps_rounded,color:AppTheme.muted,size:size*.48)
        :ClipRRect(
          borderRadius:BorderRadius.circular(size*.2),
          child:Image.network(
            'https://www.google.com/s2/favicons?domain=$domain&sz=128',
            width:size*.62,height:size*.62,fit:BoxFit.contain,
            errorBuilder:(_,__,___)=>Icon(Icons.apps_rounded,color:AppTheme.muted,size:size*.48),
          ),
        ),
    );
  }
}
