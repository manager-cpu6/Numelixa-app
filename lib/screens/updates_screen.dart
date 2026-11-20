import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../core/config/app_config.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

final ValueNotifier<bool?> updatesVisibilityChanged = ValueNotifier<bool?>(null);

class UpdatesScreen extends StatefulWidget {
 const UpdatesScreen({super.key});
 @override State<UpdatesScreen> createState()=>_UpdatesScreenState();
}
class _UpdatesScreenState extends State<UpdatesScreen>{
 late Future<Map<String,dynamic>> _future;
 final _search=TextEditingController();String _query='',_category='All';
 @override void initState(){super.initState();_load();}
 @override void dispose(){_search.dispose();super.dispose();}
 void _load(){_future=ApiClient().get('/api/updates',accessToken:context.read<AuthService>().accessToken);}
 @override Widget build(BuildContext context)=>FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
  if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
  if(s.hasError)return _UpdatesMessage(message:s.error.toString(),retry:()=>setState(_load));
  final d=s.data??{};if(d['enabled']!=true||d['hidden']==true)return const _UpdatesMessage(message:'Updates is not currently available.');
  final raw=d['channels'];final channels=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  final categoryValues=channels.map((x)=>(x['category']??'General').toString()).toSet().toList()..sort();
  final categories=<String>['All',...categoryValues];
  final filtered=channels.where((c){final text=(c['name']??'').toString()+' '+(c['description']??'').toString()+' '+(c['category']??'').toString();final categoryOk=_category=='All'||(c['category']??'General').toString()==_category;return categoryOk&&text.toLowerCase().contains(_query);}).toList();
  return RefreshIndicator(onRefresh:()async{setState(_load);await _future;},child:ListView(padding:const EdgeInsets.fromLTRB(16,16,16,30),children:[
   Row(children:[const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('NUMELIXA CHANNELS',style:TextStyle(color:AppTheme.cyan,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.6)),SizedBox(height:5),Text('Updates',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900))])),IconButton(onPressed:()=>setState(_load),icon:const Icon(Icons.refresh_rounded))]),
   const Text('Official announcements, service news and product updates.',style:TextStyle(color:AppTheme.muted,height:1.45)),
   const SizedBox(height:14),
   TextField(controller:_search,onChanged:(v)=>setState(()=>_query=v.trim().toLowerCase()),decoration:InputDecoration(prefixIcon:const Icon(Icons.search_rounded),hintText:'Search channels',suffixIcon:_query.isEmpty?null:IconButton(onPressed:(){_search.clear();setState(()=>_query='');},icon:const Icon(Icons.close_rounded)))),
   const SizedBox(height:12),
   SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:categories.map((category)=>Padding(padding:const EdgeInsets.only(right:7),child:ChoiceChip(label:Text(category),selected:_category==category,onSelected:(_)=>setState(()=>_category=category)))).toList())),
   const SizedBox(height:14),
   if(filtered.isEmpty)_UpdatesMessage(message:channels.isEmpty?'No channels have been published yet.':'No channels match your filters.')
   else ...filtered.map((channel)=>_ChannelCard(channel:channel,accessToken:context.read<AuthService>().accessToken??'',onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>UpdatesChannelScreen(channel:channel))).then((_) {if(mounted)setState(_load);}))),
  ]));
 });
}

class _ChannelCard extends StatefulWidget{
 const _ChannelCard({required this.channel,required this.accessToken,required this.onTap});final Map<String,dynamic> channel;final String accessToken;final VoidCallback onTap;
 @override State<_ChannelCard> createState()=>_ChannelCardState();
}
class _ChannelCardState extends State<_ChannelCard>{
 late bool _joined;bool _busy=false;
 @override void initState(){super.initState();_joined=widget.channel['joined']==true;}
 Future<void> _join()async{
  if(_busy||_joined)return;setState(()=>_busy=true);
  try{await ApiClient().post('/api/updates/channels/'+Uri.encodeComponent((widget.channel['slug']??'').toString())+'/membership',accessToken:widget.accessToken,body:{'notificationsEnabled':true});if(mounted){setState(()=>_joined=true);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('You joined this channel.')));}}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context){
  final channel=widget.channel,name=(channel['name']??'Numelixa channel').toString(),avatar=(channel['avatarUrl']??'').toString();
  final latest=channel['latestPost'] is Map?Map<String,dynamic>.from(channel['latestPost']):<String,dynamic>{};
  final preview=(latest['title']??latest['body']??channel['description']??'Official channel').toString();
  final count=(channel['publicSubscriberCount']??channel['actualSubscriberCount']??0).toString();
  return Card(margin:const EdgeInsets.only(bottom:10),child:Padding(padding:const EdgeInsets.all(13),child:Row(children:[
   GestureDetector(onTap:widget.onTap,child:_ChannelAvatar(url:avatar,size:52)),const SizedBox(width:11),
   Expanded(child:InkWell(onTap:widget.onTap,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Row(children:[Flexible(child:Text(name,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800))),if(channel['verified']==true)...[const SizedBox(width:4),const Icon(Icons.verified_rounded,color:AppTheme.cyan,size:16)],if(channel['featured']==true)...[const SizedBox(width:5),const Text('FEATURED',style:TextStyle(color:AppTheme.warning,fontSize:8,fontWeight:FontWeight.w900,letterSpacing:.6)]]]),
    const SizedBox(height:4),Text((channel['description']??'').toString(),maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:AppTheme.muted,fontSize:11)),
    const SizedBox(height:6),Row(children:[const Icon(Icons.people_alt_outlined,size:13,color:AppTheme.cyan),const SizedBox(width:4),Text('$count subscribers',style:const TextStyle(color:AppTheme.muted,fontSize:10)),const SizedBox(width:7),Expanded(child:Text(preview,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:10,fontWeight:FontWeight.w600)))])
   ]))),
   const SizedBox(width:7),
   _joined?const Chip(label:Text('Joined',style:TextStyle(fontSize:10)),visualDensity:VisualDensity.compact,padding:EdgeInsets.zero):TextButton(onPressed:_busy?null:_join,child:Text(_busy?'…':'Join')),
  ])));
 }
}

class UpdatesChannelScreen extends StatefulWidget{
 const UpdatesChannelScreen({super.key,required this.channel});final Map<String,dynamic> channel;
 @override State<UpdatesChannelScreen> createState()=>_UpdatesChannelScreenState();
}
class _UpdatesChannelScreenState extends State<UpdatesChannelScreen>{
 late Future<Map<String,dynamic>> _future;Map<String,dynamic> _channel={};List<Map<String,dynamic>> _posts=[];
 bool _busy=false,_hasMore=false;int _page=1;
 String get _slug=>(widget.channel['slug']??'').toString();
 String get _token=>context.read<AuthService>().accessToken??'';
 String _path(String suffix)=>'/api/updates/channels/'+Uri.encodeComponent(_slug)+suffix;
 @override void initState(){super.initState();_load();}
 void _load(){_page=1;_posts=[];_future=_fetch();}
 Future<Map<String,dynamic>> _fetch()async{
  final r=await ApiClient().get(_path('?page=1'),accessToken:_token);
  final raw=r['posts'];final items=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  if(mounted)setState((){_channel=r['channel'] is Map?Map<String,dynamic>.from(r['channel']):{};_posts=items;_hasMore=r['hasMore']==true;});
  return r;
 }
 Future<void> _membership(bool join)async{
  if(_busy)return;setState(()=>_busy=true);
  try{final api=ApiClient();final r=join?await api.post(_path('/membership'),accessToken:_token,body:{'notificationsEnabled':true}):await api.delete(_path('/membership'),accessToken:_token);if(mounted)setState(()=>_channel={..._channel,'joined':join,'actualSubscriberCount':r['subscriberCount']??_channel['actualSubscriberCount'],'publicSubscriberCount':_channel['subscriberDisplayMode']=='custom'?_channel['publicSubscriberCount']:(r['subscriberCount']??_channel['actualSubscriberCount'])});}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _notifications(bool enabled)async{
  if(_busy)return;setState(()=>_busy=true);
  try{await ApiClient().post(_path('/membership'),accessToken:_token,body:{'notificationsEnabled':enabled});if(mounted)setState(()=>_channel={..._channel,'notificationsEnabled':enabled});}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _block()async{
  final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Block this channel?'),content:const Text('The channel will disappear from your Updates list and its notifications will stop. You can unblock it later.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Block channel'))]));
  if(yes!=true||!mounted)return;
  try{await ApiClient().post(_path('/block'),accessToken:_token);if(mounted)Navigator.pop(context);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
 Future<void> _more()async{
  if(_busy||!_hasMore)return;setState(()=>_busy=true);
  try{final next=_page+1;final r=await ApiClient().get(_path('?page=$next'),accessToken:_token);final raw=r['posts'];final items=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];if(mounted)setState((){_page=next;_posts=[..._posts,...items];_hasMore=r['hasMore']==true;});}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text((widget.channel['name']??'Channel').toString())),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
  if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
  if(s.hasError)return _UpdatesMessage(message:s.error.toString(),retry:()=>setState(_load));
  final c=_channel.isEmpty?widget.channel:_channel,joined=c['joined']==true;
  final subscriberCount=(c['publicSubscriberCount']??c['actualSubscriberCount']??0).toString();
  return RefreshIndicator(onRefresh:()async{setState(_load);await _future;},child:ListView(padding:const EdgeInsets.fromLTRB(14,0,14,28),children:[
   if((c['coverUrl']??'').toString().isNotEmpty)ClipRRect(borderRadius:BorderRadius.circular(18),child:Image.network(_mediaUrl(c['coverUrl'].toString()),height:145,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const SizedBox(height:12)))
   else Container(height:96,decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),color:const Color(0xFF123C64)),child:const Center(child:Icon(Icons.campaign_outlined,color:AppTheme.cyan,size:40))),
   const SizedBox(height:12),Row(children:[_ChannelAvatar(url:(c['avatarUrl']??'').toString(),size:60),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Flexible(child:Text((c['name']??'').toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900))),if(c['verified']==true)const Icon(Icons.verified_rounded,color:AppTheme.cyan,size:18)]),Text((c['description']??'').toString(),style:const TextStyle(color:AppTheme.muted,fontSize:12)),Text('$subscriberCount subscribers',style:const TextStyle(color:AppTheme.cyan,fontSize:11,fontWeight:FontWeight.w700))]))]),
   const SizedBox(height:12),Row(children:[Expanded(child:FilledButton(onPressed:_busy?null:()=>_membership(!joined),child:Text(_busy?'Please wait…':joined?'Joined · Leave':'Join channel'))),if(joined)IconButton(onPressed:_busy?null:()=>_notifications(c['notificationsEnabled']!=true),icon:Icon(c['notificationsEnabled']==true?Icons.notifications_active_rounded:Icons.notifications_off_outlined,color:AppTheme.cyan)),IconButton(onPressed:_busy?null:_block,icon:const Icon(Icons.block_rounded,color:AppTheme.muted))]),
   const SizedBox(height:18),const Text('LATEST POSTS',style:TextStyle(fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.4,color:AppTheme.muted)),
   if(_posts.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No published posts yet.',textAlign:TextAlign.center,style:TextStyle(color:AppTheme.muted))),
   ..._posts.map((p)=>_UpdatePostCard(post:p,slug:_slug,accessToken:_token)),if(_hasMore)OutlinedButton(onPressed:_busy?null:_more,child:Text(_busy?'Loading…':'Load older posts'))
  ]));
 }));
}

class _UpdatePostCard extends StatefulWidget{
 const _UpdatePostCard({required this.post,required this.slug,required this.accessToken});final Map<String,dynamic> post;final String slug,accessToken;
 @override State<_UpdatePostCard> createState()=>_UpdatePostCardState();
}
class _UpdatePostCardState extends State<_UpdatePostCard>{
 @override void initState(){super.initState();final id=(widget.post['id']??'').toString();if(id.isNotEmpty){WidgetsBinding.instance.addPostFrameCallback((_) {if(mounted)ApiClient().post('/api/updates/channels/'+Uri.encodeComponent(widget.slug)+'/views',accessToken:widget.accessToken,body:{'postId':id}).catchError((_)=> <String,dynamic>{});});}}
 @override Widget build(BuildContext context){
  final post=widget.post;
  final media=post['media'] is List?(post['media'] as List).whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  final date=DateTime.tryParse((post['publishedAt']??'').toString());
  final views=(post['displayViews']??post['actualViews']??0).toString();
  return Card(margin:const EdgeInsets.only(top:12),child:Padding(padding:const EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
   Row(children:[const Icon(Icons.campaign_outlined,color:AppTheme.cyan,size:18),const SizedBox(width:7),Expanded(child:Text((post['title']??'Announcement').toString(),style:const TextStyle(fontWeight:FontWeight.w900,fontSize:15))),Text(date==null?'':date.toLocal().toString().substring(0,16),style:const TextStyle(color:AppTheme.muted,fontSize:10))]),
   if((post['body']??'').toString().isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:SelectableText((post['body']??'').toString(),style:const TextStyle(height:1.55,fontSize:13))),
   if(media.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:SizedBox(height:220,child:PageView(children:media.map((m){final rawUrl=(m['url']??'').toString();final url=_mediaUrl(rawUrl);return ClipRRect(borderRadius:BorderRadius.circular(14),child:m['type']=='video'?_UpdateVideoPlayer(url:url):GestureDetector(onTap:()=>showDialog<void>(context:context,builder:(_)=>Dialog(backgroundColor:Colors.black,child:InteractiveViewer(child:Image.network(url,fit:BoxFit.contain,errorBuilder:(_,__,___)=>const Icon(Icons.broken_image_outlined,color:Colors.white))))),child:Image.network(url,fit:BoxFit.cover,errorBuilder:(_,__,___)=>const Center(child:Icon(Icons.broken_image_outlined,color:AppTheme.muted)))));}).toList()))),
   if(post['links'] is List&&(post['links'] as List).isNotEmpty)Padding(padding:const EdgeInsets.only(top:10),child:Wrap(spacing:7,runSpacing:7,children:(post['links'] as List).whereType<String>().map((link)=>ActionChip(avatar:const Icon(Icons.open_in_new_rounded,size:14),label:Text(Uri.tryParse(link)?.host??'Open link'),onPressed:()=>launchUrl(Uri.parse(link),mode:LaunchMode.externalApplication))).toList())),
   const SizedBox(height:8),Row(children:[const Icon(Icons.visibility_outlined,size:15,color:AppTheme.muted),const SizedBox(width:5),Text('$views views',style:const TextStyle(color:AppTheme.muted,fontSize:11))])
  ])));
 }
}
String _mediaUrl(String raw)=>raw.startsWith('/')?Uri.parse(AppConfig.apiBase).resolve(raw).toString():raw;

class _UpdateVideoPlayer extends StatefulWidget{
 const _UpdateVideoPlayer({required this.url});final String url;
 @override State<_UpdateVideoPlayer> createState()=>_UpdateVideoPlayerState();
}
class _UpdateVideoPlayerState extends State<_UpdateVideoPlayer>{
 late final VideoPlayerController _controller;bool _failed=false;
 @override void initState(){super.initState();_controller=VideoPlayerController.networkUrl(Uri.parse(widget.url))..initialize().then((_) {if(mounted)setState((){});}).catchError((_) {if(mounted)setState(()=>_failed=true);});}
 @override void dispose(){_controller.dispose();super.dispose();}
 @override Widget build(BuildContext context){
  if(_failed)return Container(color:Colors.black,alignment:Alignment.center,child:const Text('Video unavailable',style:TextStyle(color:Colors.white70)));
  if(!_controller.value.isInitialized)return Container(color:Colors.black,alignment:Alignment.center,child:const CircularProgressIndicator(color:AppTheme.cyan));
  return GestureDetector(onTap:(){if(_controller.value.isPlaying){_controller.pause();}else{_controller.play();}setState((){});},child:Container(color:Colors.black,child:Stack(alignment:Alignment.center,children:[
   AspectRatio(aspectRatio:_controller.value.aspectRatio,child:VideoPlayer(_controller)),
   if(!_controller.value.isPlaying)const Icon(Icons.play_circle_fill_rounded,color:Colors.white,size:58),
   Positioned(left:10,right:10,bottom:8,child:VideoProgressIndicator(_controller,allowScrubbing:true,colors:const VideoProgressColors(playedColor:AppTheme.cyan,bufferedColor:Colors.white38,backgroundColor:Colors.white12))),
  ])));
 }
}
class _ChannelAvatar extends StatelessWidget{
 const _ChannelAvatar({required this.url,required this.size});final String url;final double size;
 @override Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(17),child:Container(width:size,height:size,color:const Color(0xFF12213B),child:url.isEmpty?Icon(Icons.campaign_outlined,size:size*.48,color:AppTheme.cyan):Image.network(url,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Icon(Icons.campaign_outlined,size:size*.48,color:AppTheme.cyan))));
}
class _UpdatesMessage extends StatelessWidget{
 const _UpdatesMessage({required this.message,this.retry});final String message;final VoidCallback? retry;
 @override Widget build(BuildContext context)=>Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Icon(Icons.campaign_outlined,size:44,color:AppTheme.cyan),const SizedBox(height:12),Text(message,textAlign:TextAlign.center,style:const TextStyle(color:AppTheme.muted,height:1.5)),if(retry!=null)...[const SizedBox(height:12),OutlinedButton.icon(onPressed:retry,icon:const Icon(Icons.refresh_rounded),label:const Text('Try again'))]])));
}
