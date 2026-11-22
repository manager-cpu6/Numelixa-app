import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../services/notification_service.dart';
import '../services/tapcode_service.dart';

class TapCodeSettingsScreen extends StatefulWidget {
  const TapCodeSettingsScreen({super.key});
  @override State<TapCodeSettingsScreen> createState() => _TapCodeSettingsScreenState();
}
class _TapCodeSettingsScreenState extends State<TapCodeSettingsScreen> {
  Map<String,dynamic> _status = const {};
  bool _loading = true, _busy = false, _autoCopy = false;
  String? _error;
  @override void initState(){super.initState();_refresh();}
  Future<void> _refresh() async {
    try {
      final values=await Future.wait([TapCodeService.instance.status(),TapCodeService.instance.autoCopyEnabled()]);
      if(!mounted)return;
      setState((){_status=values[0] as Map<String,dynamic>;_autoCopy=values[1] as bool;_loading=false;_error=null;});
    } catch (_) {if(mounted)setState((){_loading=false;_error='TapCode native integration is unavailable in this build.';});}
  }
  String get _label {
    if(_error!=null||_status['available']==false)return 'Temporarily unavailable';
    if(_status['enabled']==true&&_status['osEnabled']==true)return _status['hasCodes']==true?'Ready':'Enabled';
    if(_status['enabled']==true)return 'Setup required';
    return 'Not enabled';
  }
  Color get _color=>switch(_label){'Ready'=>AppTheme.mint,'Enabled'=>AppTheme.cyan,'Setup required'=>AppTheme.warning,'Temporarily unavailable'=>const Color(0xFFFF788C),_=>AppTheme.muted};
  Future<void> _enable()async{setState(()=>_busy=true);try{await TapCodeService.instance.enable();await Future<void>.delayed(const Duration(milliseconds:500));await _refresh();}catch(_){if(mounted)setState(()=>_error='Could not open Android Autofill settings. Select Numelixa manually in Settings.');}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> _disable()async{setState(()=>_busy=true);try{await TapCodeService.instance.disable();await _refresh();}catch(_){if(mounted)setState(()=>_error='TapCode could not be disabled. Try again.');}finally{if(mounted)setState(()=>_busy=false);}}
  Future<void> _notifications()async{final p=await Permission.notification.status;if(!p.isGranted){await context.read<NotificationService>().requestPermission();}else{await context.read<NotificationService>().openNotificationSettings();}}
  @override Widget build(BuildContext context){
    if(_loading)return Scaffold(appBar:AppBar(title:const Text('Numelixa TapCode')),body:const Center(child:CircularProgressIndicator()));
    final enabled=_status['enabled']==true,osEnabled=_status['osEnabled']==true;
    return Scaffold(appBar:AppBar(title:const Text('Numelixa TapCode'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh_rounded))]),body:ListView(padding:const EdgeInsets.all(16),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(borderRadius:BorderRadius.circular(22),border:Border.all(color:AppTheme.glassBorder),gradient:const LinearGradient(colors:[Color(0xFF102D55),Color(0xFF09172B)])),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Row(children:[Icon(Icons.password_rounded,color:AppTheme.cyan,size:27),SizedBox(width:10),Text('NUMELIXA TAPCODE',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1))]),
        const SizedBox(height:14),const Text('Your verification code, exactly when you need it.',style:TextStyle(fontSize:21,height:1.25,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),const Text('Get a user-controlled code suggestion without switching back to Numelixa.',style:TextStyle(color:AppTheme.muted,height:1.45)),
        const SizedBox(height:18),Row(children:[Container(width:8,height:8,decoration:BoxDecoration(color:_color,shape:BoxShape.circle)),const SizedBox(width:8),Text(_label,style:TextStyle(color:_color,fontWeight:FontWeight.w800)),const Spacer(),if(_status['hasCodes']==true)const Text('Active code available',style:TextStyle(color:AppTheme.mint,fontSize:11))]),
        const SizedBox(height:16),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:_busy?null:(enabled&&osEnabled?_disable:_enable),icon:Icon(enabled&&osEnabled?Icons.power_settings_new_rounded:Icons.security_rounded),label:Text(_busy?'Please wait…':enabled&&osEnabled?'Disable TapCode':enabled?'Complete Android setup':'Enable TapCode'))),
      ])),
      if(_error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(_error!,style:const TextStyle(color:Color(0xFFFF788C)))),
      const SizedBox(height:20),const _Heading('HOW TO SET UP'),
      const Card(child:Padding(padding:EdgeInsets.all(15),child:Column(children:[
        _Step('01','Enable TapCode','Start setup from this screen.'),
        _Step('02','Choose Numelixa','In Android Autofill settings, select Numelixa as your preferred service.'),
        _Step('03','Open Activations','Refresh your active Numelixa orders so eligible codes can be securely associated.'),
        _Step('04','Tap the suggestion','When a supported app requests Autofill, choose the Numelixa code suggestion.'),
      ]))),
      const SizedBox(height:16),const _Heading('PREFERENCES'),
      Card(child:SwitchListTile(value:_autoCopy,onChanged:_busy?null:(v)async{await TapCodeService.instance.setAutoCopyEnabled(v);if(mounted)setState(()=>_autoCopy=v);},secondary:const Icon(Icons.content_copy_rounded,color:AppTheme.cyan),title:const Text('Auto-copy received code'),subtitle:const Text('Optional. Copies an OTP only when Numelixa receives its notification while open.'))),
      Card(child:ListTile(leading:const Icon(Icons.notifications_active_outlined,color:AppTheme.cyan),title:const Text('OTP arrival notifications'),subtitle:const Text('Uses Numelixa notification permission and its existing verification channel.'),trailing:const Icon(Icons.chevron_right_rounded),onTap:_notifications)),
      const SizedBox(height:16),const _Heading('PRIVACY & COMPATIBILITY'),
      const Card(child:Padding(padding:EdgeInsets.all(15),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        _Info(Icons.verified_user_outlined,'Your orders only','Codes are associated with active orders returned by your signed-in Numelixa account.'),
        _Info(Icons.lock_outline_rounded,'Encrypted temporary cache','OTP data is encrypted with Android Keystore and removed after its short useful lifetime.'),
        _Info(Icons.apps_rounded,'Compatible fields only','Suggestions appear only when another app exposes Android’s SMS one-time-code Autofill hint. Some apps do not support this.'),
        _Info(Icons.copy_all_rounded,'Copy Code fallback','If Autofill is unavailable, use Copy Code in Activations.'),
      ]))),
      const SizedBox(height:12),const Text('TapCode never uses Accessibility, reads another app’s screen, or inserts a code without your tap.',style:TextStyle(color:AppTheme.muted,fontSize:12,height:1.5)),
    ]));
  }
}
class _Heading extends StatelessWidget{const _Heading(this.text);final String text;@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(left:4,bottom:9),child:Text(text,style:const TextStyle(color:AppTheme.muted,fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.2)));}
class _Step extends StatelessWidget{const _Step(this.number,this.title,this.detail);final String number,title,detail;@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:14),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(number,style:const TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900)),const SizedBox(width:12),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(detail,style:const TextStyle(color:AppTheme.muted,fontSize:12,height:1.4))]))]));}
class _Info extends StatelessWidget{const _Info(this.icon,this.title,this.detail);final IconData icon;final String title,detail;@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:13),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(icon,color:AppTheme.cyan,size:20),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(detail,style:const TextStyle(color:AppTheme.muted,fontSize:12,height:1.45))]))]));}
