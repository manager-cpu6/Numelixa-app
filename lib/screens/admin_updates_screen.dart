import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';

class AdminUpdatesScreen extends StatefulWidget {
  const AdminUpdatesScreen({super.key, required this.accessToken});
  final String accessToken;
  @override State<AdminUpdatesScreen> createState() => _AdminUpdatesScreenState();
}

class _AdminUpdatesScreenState extends State<AdminUpdatesScreen> {
  bool _loading = true, _busy = false, _enabled = false, _notifications = true;
  String _tab = 'Channels', _error = '', _notice = '';
  List<Map<String,dynamic>> _channels = [], _posts = [];
  String get _token => widget.accessToken;

  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    if(mounted)setState(()=>_loading=true);
    try {
      final values=await Future.wait([
        ApiClient().get('/api/admin/updates/settings',accessToken:_token),
        ApiClient().get('/api/admin/updates/channels',accessToken:_token),
        ApiClient().get('/api/admin/updates/posts',accessToken:_token),
      ]);
      if(!mounted)return;
      setState((){
        _enabled=values[0]['settings']?['enabled']==true;
        _notifications=values[0]['settings']?['notificationsEnabled']!=false;
        _channels=(values[1]['channels'] as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
        _posts=(values[2]['posts'] as List? ?? const []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
        _error='';_loading=false;
      });
    } catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _run(Future<void> Function() action) async {
    if(_busy)return;setState(()=>_busy=true);_error='';_notice='';
    try{await action();}catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _saveSettings(bool enabled,{bool? notifications}) async {
    await _run(() async {
      final r=await ApiClient().patch('/api/admin/updates/settings',accessToken:_token,body:{'enabled':enabled,'notificationsEnabled':notifications??_notifications});
      if(r['ok']!=true)throw ApiException('Unable to save Updates settings.');
      setState(()=>_notice='Updates settings saved.');await _load();
    });
  }
  Future<void> _createChannel() async {
    final name=TextEditingController(),slug=TextEditingController(),description=TextEditingController(),category=TextEditingController(text:'General');
    final values=await showDialog<List<String>>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Create Updates channel'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Channel name')),
        TextField(controller:slug,decoration:const InputDecoration(labelText:'Unique slug')),
        TextField(controller:description,maxLines:3,decoration:const InputDecoration(labelText:'Description')),
        TextField(controller:category,decoration:const InputDecoration(labelText:'Category')),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,[name.text,slug.text,description.text,category.text]),child:const Text('Create'))],
    ));
    if(values==null)return;
    await _run(() async {
      final r=await ApiClient().post('/api/admin/updates/channels',accessToken:_token,body:{'name':values[0],'slug':values[1],'description':values[2],'category':values[3],'status':'active','visibility':'public'});
      if(r['ok']!=true)throw ApiException('Channel could not be created.');
      setState(()=>_notice='Channel created.');await _load();
    });
    name.dispose();slug.dispose();description.dispose();category.dispose();
  }
  Future<void> _changeChannel(Map<String,dynamic> channel,String status) async {
    await _run(() async {
      final r=await ApiClient().patch('/api/admin/updates/channels',accessToken:_token,body:{'id':channel['_id'],'status':status});
      if(r['ok']!=true)throw ApiException('Channel could not be updated.');
      setState(()=>_notice='Channel updated.');await _load();
    });
  }
  Future<void> _archiveChannel(Map<String,dynamic> channel) async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Archive channel?'),content:Text('“${channel['name']}” will no longer appear in the public Updates feed. Existing posts and memberships are preserved.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Archive'))]));
    if(yes!=true)return;
    await _run(() async {final r=await ApiClient().delete('/api/admin/updates/channels',accessToken:_token,body:{'id':channel['_id'],'archive':true});if(r['ok']!=true)throw ApiException('Channel could not be archived.');setState(()=>_notice='Channel archived.');await _load();});
  }
  Future<void> _createPost() async {
    if(_channels.isEmpty){setState(()=>_error='Create a channel before publishing a post.');return;}
    String channelId=(_channels.first['_id']??'').toString(),status='published';
    final title=TextEditingController(),body=TextEditingController();
    final values=await showDialog<List<String>>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:const Text('New channel post'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:channelId,decoration:const InputDecoration(labelText:'Channel'),items:_channels.map((c)=>DropdownMenuItem(value:(c['_id']??'').toString(),child:Text((c['name']??'Channel').toString(),overflow:TextOverflow.ellipsis))).toList(),onChanged:(v){if(v!=null)setDialog(()=>channelId=v);}),
        TextField(controller:title,decoration:const InputDecoration(labelText:'Post title')),
        TextField(controller:body,minLines:3,maxLines:6,decoration:const InputDecoration(labelText:'Message')),
        DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Publish status'),items:const [DropdownMenuItem(value:'published',child:Text('Publish now')),DropdownMenuItem(value:'draft',child:Text('Save as draft'))],onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,[channelId,title.text,body.text,status]),child:const Text('Save post'))],
    )));
    if(values==null)return;
    await _run(() async {
      final r=await ApiClient().post('/api/admin/updates/posts',accessToken:_token,body:{'channelId':values[0],'title':values[1],'body':values[2],'type':'announcement','status':values[3],'requestId':'android-${DateTime.now().microsecondsSinceEpoch}'});
      if(r['ok']!=true)throw ApiException('Post could not be saved.');
      final sent=(r['notifications']?['sent']??0).toString();
      setState(()=>_notice=values[3]=='published'?'Post published. Push notifications sent to $sent devices.':'Post saved as draft.');
      await _load();
    });
    title.dispose();body.dispose();
  }
  Future<void> _publish(Map<String,dynamic> post) async {
    await _run(() async {final r=await ApiClient().patch('/api/admin/updates/posts',accessToken:_token,body:{'id':post['_id'],'status':'published'});if(r['ok']!=true)throw ApiException('Post could not be published.');setState(()=>_notice='Post published.');await _load();});
  }
  Future<void> _deletePost(Map<String,dynamic> post) async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete post?'),content:const Text('This removes the post and its view records.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
    if(yes!=true)return;
    await _run(() async {await ApiClient().delete('/api/admin/updates/posts',accessToken:_token,body:{'id':post['_id']});setState(()=>_notice='Post deleted.');await _load();});
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Updates management'),actions:[IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh_rounded))]),
    body:_loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('GLOBAL UPDATES CONTROL',style:TextStyle(color:AppTheme.cyan,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.2)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Enable Updates for users'),subtitle:const Text('Preserves channels and subscriptions when switched off.'),value:_enabled,onChanged:_busy?(v){}:(v)=>_saveSettings(v)),
        SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Push notifications'),subtitle:const Text('Send alerts for new published channel posts.'),value:_notifications,onChanged:_busy?(v){}:(v)=>_saveSettings(_enabled,notifications:v)),
      ]))),
      if(_error.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(_error,style:const TextStyle(color:AppTheme.warning))),
      if(_notice.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(_notice,style:const TextStyle(color:AppTheme.mint))),
      const SizedBox(height:8),
      SegmentedButton<String>(segments:const [ButtonSegment(value:'Channels',label:Text('Channels'),icon:Icon(Icons.campaign_outlined)),ButtonSegment(value:'Posts',label:Text('Posts'),icon:Icon(Icons.article_outlined))],selected:{_tab},onSelectionChanged:(v)=>setState(()=>_tab=v.first)),
      const SizedBox(height:12),
      if(_tab=='Channels')...[
        Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_busy?null:_createChannel,icon:const Icon(Icons.add),label:const Text('New channel'))),
        if(_channels.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No channels created yet.',textAlign:TextAlign.center)),
        ..._channels.map((c){final status=(c['status']??'inactive').toString();return Card(child:ListTile(isThreeLine:true,leading:const Icon(Icons.campaign_rounded,color:AppTheme.cyan),title:Text((c['name']??'Channel').toString()),subtitle:Text('@${c['slug']??''} · ${c['category']??'General'}\n${c['actualSubscribers']??0} subscribers · ${c['postCount']??0} posts · $status'),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='archive')_archiveChannel(c);else _changeChannel(c,v);},itemBuilder:(_)=>[PopupMenuItem(value:status=='active'?'inactive':'active',child:Text(status=='active'?'Deactivate':'Activate')),const PopupMenuItem(value:'archive',child:Text('Archive'))])));}),
      ] else ...[
        Align(alignment:Alignment.centerRight,child:FilledButton.icon(onPressed:_busy?null:_createPost,icon:const Icon(Icons.add),label:const Text('New post'))),
        if(_posts.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No posts yet.',textAlign:TextAlign.center)),
        ..._posts.map((p){final status=(p['status']??'draft').toString();return Card(child:ListTile(isThreeLine:true,leading:const Icon(Icons.article_outlined,color:AppTheme.cyan),title:Text((p['title']??'Untitled post').toString(),maxLines:2,overflow:TextOverflow.ellipsis),subtitle:Text('${p['actualViews']??0} views · $status\n${p['body']??''}',maxLines:2,overflow:TextOverflow.ellipsis),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='publish')_publish(p);if(v=='delete')_deletePost(p);},itemBuilder:(_)=>[if(status=='draft')const PopupMenuItem(value:'publish',child:Text('Publish')),const PopupMenuItem(value:'delete',child:Text('Delete'))])));}),
      ],
    ])),
  );
}
