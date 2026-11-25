import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'updates_screen.dart';
import 'tapcode_screen.dart';
import 'request_money_screen.dart';

class AccountSettingsScreen extends StatefulWidget{
 const AccountSettingsScreen({super.key});
 @override State<AccountSettingsScreen> createState()=>_AccountSettingsScreenState();
}
class _AccountSettingsScreenState extends State<AccountSettingsScreen>{
 bool _loading=true,_busy=false,_app=true,_email=false,_hideUpdates=false,_updatesEnabled=false,_updatesNotifications=true;
 String? _error;
 @override void initState(){super.initState();_load();}
 Future<void> _load()async{
  try{
   final token=context.read<AuthService>().accessToken;
   final values=await Future.wait([ApiClient().get('/api/mobile/notification-preferences',accessToken:token),ApiClient().get('/api/updates/preferences',accessToken:token)]);
   if(!mounted)return;
   setState((){_app=values[0]['preferences']?['appEnabled']!=false;_email=values[0]['preferences']?['emailEnabled']==true;_hideUpdates=values[1]['hideUpdates']==true;_updatesEnabled=values[1]['enabled']==true;_updatesNotifications=values[1]['notificationsEnabled']!=false;_loading=false;_error=null;});
  }catch(e){if(mounted)setState(()=>_loading=false);if(mounted)setState(()=>_error=e.toString());}
 }
 Future<void> _saveNotifications({bool? app,bool? email})async{
  final nextApp=app??_app,nextEmail=email??_email;setState(()=>_busy=true);
  try{await ApiClient().patch('/api/mobile/notification-preferences',accessToken:context.read<AuthService>().accessToken,body:{'appEnabled':nextApp,'emailEnabled':nextEmail});if(mounted)setState((){_app=nextApp;_email=nextEmail;});}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _saveUpdatesNotifications(bool value)async{
  setState(()=>_busy=true);
  try{final result=await ApiClient().patch('/api/updates/preferences',accessToken:context.read<AuthService>().accessToken,body:{'notificationsEnabled':value});if(mounted)setState(()=>_updatesNotifications=result['notificationsEnabled']!=false);}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _saveHideUpdates(bool value)async{
  setState(()=>_busy=true);
  try{final result=await ApiClient().patch('/api/updates/preferences',accessToken:context.read<AuthService>().accessToken,body:{'hideUpdates':value});if(mounted){setState(()=>_hideUpdates=result['hideUpdates']==true);updatesVisibilityChanged.value=_hideUpdates;}}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context){
  final auth=context.watch<AuthService>();
  return Scaffold(appBar:AppBar(title:const Text('Settings')),body:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
   if(_error!=null)Card(child:ListTile(title:const Text('Some settings could not be loaded'),subtitle:Text(_error!),trailing:IconButton(onPressed:_load,icon:const Icon(Icons.refresh)))),
   const _SettingHeading('APPEARANCE'),
   const Card(child:ListTile(leading:Icon(Icons.dark_mode_outlined,color:AppTheme.cyan),title:Text('Dark appearance'),subtitle:Text('Numelixa uses its standard dark interface.'))),
   const SizedBox(height:14),const _SettingHeading('NOTIFICATIONS'),
   Card(child:Column(children:[
    SwitchListTile(value:_app,onChanged:_busy?null:(v)=>_saveNotifications(app:v),secondary:const Icon(Icons.notifications_active_outlined,color:AppTheme.cyan),title:const Text('App notifications'),subtitle:const Text('Order, wallet and account alerts')),
    const Divider(height:1),
    SwitchListTile(value:_email,onChanged:_busy?null:(v)=>_saveNotifications(email:v),secondary:const Icon(Icons.email_outlined,color:AppTheme.cyan),title:const Text('Email notifications'),subtitle:const Text('Account and service emails')),
    ListTile(leading:const Icon(Icons.tune_rounded,color:AppTheme.cyan),title:const Text('Android notification permissions'),subtitle:Text(context.read<NotificationService>().registrationStatus.value),trailing:const Icon(Icons.chevron_right),onTap:()=>context.read<NotificationService>().openNotificationSettings()),
   ])),
   const SizedBox(height:14),const _SettingHeading('UPDATES'),
   Card(child:Column(children:[
    SwitchListTile(value:_updatesEnabled&&!_hideUpdates,onChanged:_updatesEnabled&&!_busy?(v)=>_saveHideUpdates(!v):null,secondary:const Icon(Icons.campaign_outlined,color:AppTheme.cyan),title:const Text('Show Updates'),subtitle:Text(_updatesEnabled?'Hide Updates only on this account. Your subscriptions are preserved.':'Updates is currently closed by Numelixa administrators.')),
    const Divider(height:1),
    SwitchListTile(value:_updatesNotifications,onChanged:_updatesEnabled&&!_busy?(v)=>_saveUpdatesNotifications(v):null,secondary:const Icon(Icons.notifications_active_outlined,color:AppTheme.cyan),title:const Text('Updates notifications'),subtitle:const Text('Allow new post alerts from channels you follow')),
    const Divider(height:1),
    ListTile(enabled:_updatesEnabled,leading:const Icon(Icons.block_outlined,color:AppTheme.cyan),title:const Text('Blocked channels'),subtitle:const Text('Review and unblock channels'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const BlockedUpdatesChannelsScreen()))),
   ])),
   const SizedBox(height:14),const _SettingHeading('WALLET'),
   Card(child:ListTile(leading:const Icon(Icons.request_quote_outlined,color:AppTheme.cyan),title:const Text('Request Money Another User'),subtitle:const Text('Request wallet funds using another user’s Numelixa ID'),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const RequestMoneyScreen())))),
   const SizedBox(height:14),const _SettingHeading('TAPCODE'),
   Card(child:ListTile(leading:const Icon(Icons.password_rounded,color:AppTheme.cyan),title:const Text('Numelixa TapCode'),subtitle:const Text('User-controlled OTP Autofill and code privacy'),trailing:const Icon(Icons.chevron_right_rounded),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const TapCodeSettingsScreen())))),
   const SizedBox(height:14),const _SettingHeading('SECURITY'),
   Card(child:Column(children:[
    SwitchListTile(value:auth.biometricEnabled,onChanged:_busy?null:(v)=>_toggleBiometric(v),secondary:const Icon(Icons.fingerprint_rounded,color:AppTheme.cyan),title:const Text('Biometric app lock'),subtitle:const Text('Require fingerprint, face or device authentication when returning to Numelixa')),
    const Divider(height:1),

   ])),
   const SizedBox(height:14),const _SettingHeading('SUPPORT'),
   const Card(child:ListTile(leading:Icon(Icons.support_agent_rounded,color:AppTheme.cyan),title:Text('Need help?'),subtitle:Text('Contact the official Numelixa support team.'))),
  ]));
 }
 Future<void> _toggleBiometric(bool value)async{
  try{if(value){final ok=await context.read<AuthService>().enableBiometricLock();if(!ok&&mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Biometric setup was cancelled.')));}else{await context.read<AuthService>().disableBiometricLock();}}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
 }
}

class AccountManagementScreen extends StatelessWidget {
 const AccountManagementScreen({super.key});
 @override
 Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Account')),
  body:ListView(padding:const EdgeInsets.all(16),children:[
   const Card(child:ListTile(leading:Icon(Icons.shield_outlined,color:AppTheme.cyan),title:Text('Account protection'),subtitle:Text('Manage your sessions, password and account access.'))),
   const SizedBox(height:14),
   const _SettingHeading('ACCOUNT SECURITY'),
   Card(child:Column(children:[
    ListTile(leading:const Icon(Icons.devices_rounded,color:AppTheme.cyan),title:const Text('Devices'),subtitle:const Text('Review active sessions and sign out other devices'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const AccountDevicesScreen()))),
    const Divider(height:1),
    ListTile(leading:const Icon(Icons.password_rounded,color:AppTheme.cyan),title:const Text('Change password'),subtitle:const Text('Verify with the code sent to your account email'),trailing:const Icon(Icons.chevron_right),onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>const AccountPasswordScreen()))),
    const Divider(height:1),
    ListTile(leading:const Icon(Icons.history_rounded,color:AppTheme.cyan),title:const Text('Security activity'),subtitle:const Text('Review recent account security activity'),trailing:const Icon(Icons.open_in_new_rounded),onTap:()=>launchUrl(Uri.parse('https://www.numelixa.com/security'),mode:LaunchMode.externalApplication)),
   ])),
   const SizedBox(height:18),
   const _SettingHeading('ACCOUNT CONTROL'),
   Card(child:ListTile(
    leading:const Icon(Icons.delete_forever_outlined,color:Color(0xFFFF788C)),
    title:const Text('Delete account',style:TextStyle(color:Color(0xFFFF788C),fontWeight:FontWeight.w800)),
    subtitle:const Text('Submit an official account deletion request'),
    trailing:const Icon(Icons.chevron_right),
    onTap:()=>launchUrl(Uri.parse('https://www.numelixa.com/account-deletion'),mode:LaunchMode.externalApplication),
   )),
  ]),
 );
}

class AccountDevicesScreen extends StatefulWidget{
 const AccountDevicesScreen({super.key});
 @override State<AccountDevicesScreen> createState()=>_AccountDevicesScreenState();
}
class _AccountDevicesScreenState extends State<AccountDevicesScreen>{
 late Future<Map<String,dynamic>> _future;bool _busy=false;
 @override void initState(){super.initState();_load();}
 void _load(){_future=context.read<AuthService>().listDevices();}
 Future<void> _remove(Map<String,dynamic> d)async{
  final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Sign out this device?'),content:Text('This will revoke the session for '+(d['device']??'this device').toString()+'.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Sign out'))]));
  if(yes!=true)return;setState(()=>_busy=true);
  try{await context.read<AuthService>().removeDevice((d['deviceId']??'').toString(),sessionId:(d['sessionId']??'').toString());if(mounted)setState(_load);}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 Future<void> _signOutOthers(List<Map<String,dynamic>> devices)async{
  final others=devices.where((d)=>d['current']!=true).toList();if(others.isEmpty)return;
  final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Sign out other devices?'),content:Text('Revoke '+others.length.toString()+' other device session(s)? This device will remain signed in.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Sign out others'))]));
  if(yes!=true)return;setState(()=>_busy=true);
  try{for(final d in others){await context.read<AuthService>().removeDevice((d['deviceId']??'').toString(),sessionId:(d['sessionId']??'').toString());}if(mounted)setState(_load);}
  catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Your devices'),actions:[IconButton(onPressed:()=>setState(_load),icon:const Icon(Icons.refresh))]),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
  if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
  if(s.hasError)return Center(child:Text(s.error.toString()));
  final raw=s.data?['devices'];final devices=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  return RefreshIndicator(onRefresh:()async{setState(_load);await _future;},child:ListView(padding:const EdgeInsets.all(16),children:[
   Card(child:ListTile(leading:const Icon(Icons.shield_outlined,color:AppTheme.cyan),title:const Text('Active sessions'),subtitle:Text(devices.length.toString()+' device(s) currently have an active session.'))),
   if(devices.any((d)=>d['current']!=true))Padding(padding:const EdgeInsets.symmetric(vertical:10),child:OutlinedButton.icon(onPressed:_busy?null:()=>_signOutOthers(devices),icon:const Icon(Icons.logout),label:const Text('Sign out other devices'))),
   if(devices.isEmpty)const Padding(padding:EdgeInsets.all(24),child:Text('No active device sessions were returned.',textAlign:TextAlign.center)),
   ...devices.map((d)=>Card(child:ListTile(leading:Icon(d['current']==true?Icons.phone_android:Icons.devices,color:d['current']==true?AppTheme.mint:AppTheme.cyan),title:Text((d['device']??'Device').toString()),subtitle:Text([d['platform'],d['browser'],d['city'],d['country']].where((x)=>x!=null&&x.toString().isNotEmpty).join(' · ')+'\nLast active: '+(d['lastSeenAt']??'Unknown').toString()),isThreeLine:true,trailing:d['current']==true?const Chip(label:Text('This device')):IconButton(onPressed:_busy?null:()=>_remove(d),icon:const Icon(Icons.logout,color:Color(0xFFFF647C)))))),
  ]));
 }));
}

class AccountPasswordScreen extends StatefulWidget{
 const AccountPasswordScreen({super.key});
 @override State<AccountPasswordScreen> createState()=>_AccountPasswordScreenState();
}
class _AccountPasswordScreenState extends State<AccountPasswordScreen>{
 final _code=TextEditingController(),_password=TextEditingController(),_confirm=TextEditingController();
 bool _sent=false,_busy=false;String? _message;
 @override void dispose(){_code.dispose();_password.dispose();_confirm.dispose();super.dispose();}
 Future<void> _send()async{setState(()=>_busy=true);try{await context.read<AuthService>().requestPasswordChangeCode();if(mounted)setState((){_sent=true;_message='A six-digit verification code was sent to your account email.';});}catch(e){if(mounted)setState(()=>_message=e.toString());}finally{if(mounted)setState(()=>_busy=false);}}
 Future<void> _applyPasswordChange()async{
  if(_password.text.length<8||_password.text!=_confirm.text){setState(()=>_message='Enter a password with at least 8 characters and make sure both fields match.');return;}
  setState(()=>_busy=true);try{await context.read<AuthService>().confirmPasswordChange(code:_code.text,newPassword:_password.text);if(mounted){setState(()=>_message='Password changed successfully.');_password.clear();_confirm.clear();_code.clear();}}catch(e){if(mounted)setState(()=>_message=e.toString());}finally{if(mounted)setState(()=>_busy=false);}
 }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Change password')),body:ListView(padding:const EdgeInsets.all(18),children:[
  const Icon(Icons.lock_reset_rounded,color:AppTheme.cyan,size:48),const SizedBox(height:12),
  const Text('Protect your account',textAlign:TextAlign.center,style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
  const Text('Request a one-time code by email, then choose a new password.',textAlign:TextAlign.center,style:TextStyle(color:AppTheme.muted)),
  if(_message!=null)Padding(padding:const EdgeInsets.all(12),child:Text(_message!,style:const TextStyle(color:AppTheme.cyan))),
  if(!_sent)FilledButton(onPressed:_busy?null:_send,child:Text(_busy?'Sending…':'Send verification code'))
  else ...[
   TextField(controller:_code,keyboardType:TextInputType.number,maxLength:6,decoration:const InputDecoration(labelText:'6-digit email code')),
   TextField(controller:_password,obscureText:true,decoration:const InputDecoration(labelText:'New password')),
   TextField(controller:_confirm,obscureText:true,decoration:const InputDecoration(labelText:'Confirm new password')),
   const SizedBox(height:12),FilledButton(onPressed:_busy?null:_applyPasswordChange,child:Text(_busy?'Saving…':'Update password')),
   TextButton(onPressed:_busy?null:_send,child:const Text('Send a new code')),
  ]
 ]));
}

class BlockedUpdatesChannelsScreen extends StatefulWidget{
 const BlockedUpdatesChannelsScreen({super.key});
 @override State<BlockedUpdatesChannelsScreen> createState()=>_BlockedUpdatesChannelsScreenState();
}
class _BlockedUpdatesChannelsScreenState extends State<BlockedUpdatesChannelsScreen>{
 late Future<Map<String,dynamic>> _future;bool _busy=false;
 @override void initState(){super.initState();_load();}
 void _load(){_future=ApiClient().get('/api/updates/blocked',accessToken:context.read<AuthService>().accessToken);}
 Future<void> _unblock(String id)async{setState(()=>_busy=true);try{await ApiClient().delete('/api/updates/blocked',accessToken:context.read<AuthService>().accessToken,body:{'channelId':id});if(mounted)setState(_load);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>_busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Blocked channels')),body:FutureBuilder<Map<String,dynamic>>(future:_future,builder:(context,s){
  if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
  if(s.hasError)return Center(child:Text(s.error.toString()));
  final raw=s.data?['channels'];final channels=raw is List?raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():<Map<String,dynamic>>[];
  if(channels.isEmpty)return const Center(child:Text('You have not blocked any channels.',style:TextStyle(color:AppTheme.muted)));
  return ListView(padding:const EdgeInsets.all(16),children:channels.map((c)=>Card(child:ListTile(leading:const Icon(Icons.block,color:AppTheme.muted),title:Text((c['name']??'Channel').toString()),subtitle:Text((c['description']??'').toString()),trailing:TextButton(onPressed:_busy?null:()=>_unblock((c['_id']??'').toString()),child:const Text('Unblock'))))).toList());
 }));
}

class _SettingHeading extends StatelessWidget{
 const _SettingHeading(this.label);final String label;
 @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(left:4,bottom:8),child:Text(label,style:const TextStyle(color:AppTheme.muted,fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.3)));
}
