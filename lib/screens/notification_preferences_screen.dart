import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key,required this.accessToken});
  final String accessToken;
  @override
  State<NotificationPreferencesScreen> createState()=>_NotificationPreferencesScreenState();
}
class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen>{
 final ApiClient _api=ApiClient();
 bool _app=true,_email=false,_loading=true,_saving=false;
 String? _error;
 @override
 void initState(){super.initState();_load();}
 Future<void> _load()async{
  try{final d=await _api.get('/api/mobile/notification-preferences',accessToken:widget.accessToken);final p=d['preferences'];if(p is Map&&mounted)setState((){_app=p['appEnabled']!=false;_email=p['emailEnabled']==true;_loading=false;});}
  catch(e){if(mounted)setState((){_error='Could not load notification preferences. Check your connection and retry.';_loading=false;});}
 }
 Future<void> _save(bool app,bool email)async{
  final oldApp=_app,oldEmail=_email;
  setState((){_app=app;_email=email;_saving=true;_error=null;});
  try{final d=await _api.patch('/api/mobile/notification-preferences',accessToken:widget.accessToken,body:{'appEnabled':app,'emailEnabled':email});final p=d['preferences'];if(p is Map&&mounted)setState((){_app=p['appEnabled']!=false;_email=p['emailEnabled']==true;});}
  catch(_){if(mounted)setState((){_app=oldApp;_email=oldEmail;_error='Could not save your preferences. Please try again.';});}
  finally{if(mounted)setState(()=>_saving=false);}
 }
 @override
 Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Notification Preferences')),
  body:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(18),children:[
   const Text('Manage which notifications you receive.',style:TextStyle(color:Color(0xFF91A8C4),fontSize:14)),
   const SizedBox(height:18),
   Card(child:SwitchListTile(
    secondary:Container(width:44,height:44,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFF102844),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.notifications_active_rounded,color:AppTheme.cyan)),
    title:const Text('App notifications',style:TextStyle(fontWeight:FontWeight.w800)),
    subtitle:const Text('Receive alerts on your Numelixa Android device.'),
    value:_app,onChanged:_saving?null:(v)=>_save(v,_email),activeColor:AppTheme.cyan,
   )),
   Card(child:SwitchListTile(
    secondary:Container(width:44,height:44,alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xFF102844),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.email_rounded,color:AppTheme.violet)),
    title:const Text('Email notifications',style:TextStyle(fontWeight:FontWeight.w800)),
    subtitle:const Text('Send eligible account and service updates to your registered email address.'),
    value:_email,onChanged:_saving?null:(v)=>_save(_app,v),activeColor:AppTheme.cyan,
   )),
   if(_saving)const Padding(padding:EdgeInsets.all(12),child:Center(child:CircularProgressIndicator(strokeWidth:2))),
   if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:const TextStyle(color:Color(0xFFFF879B)))),
   const SizedBox(height:12),
   const Text('You can enable either channel or both. Android notification permission and your device settings must also allow app alerts.',style:TextStyle(color:Color(0xFF7185A5),fontSize:12,height:1.55)),
  ]),
 );
}
