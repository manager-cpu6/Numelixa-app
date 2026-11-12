import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../core/config/app_config.dart';

const _ink=Color(0xff07111f),_panel=Color(0xff111f32),_line=Color(0xff263b56),_mint=Color(0xff45ddb4),_blue=Color(0xff718bff);
const _smsChannel=MethodChannel('com.numelixa/ebirr_sms');
const _storage=FlutterSecureStorage();
const _tokenKey='ebirr_numelixa_device_token';
const _syncKey='ebirr_numelixa_last_sms_sync';

class EbirrAdminGate extends StatefulWidget {
  const EbirrAdminGate({super.key});
  @override State<EbirrAdminGate> createState()=>_EbirrAdminGateState();
}
class _EbirrAdminGateState extends State<EbirrAdminGate> {
  String? token; bool loading=true,permission=false; String? error;
  @override void initState(){super.initState();_start();}
  Future<void> _start() async {
    try {
      var p=await Permission.sms.status;
      if(!p.isGranted) p=await Permission.sms.request();
      permission=p.isGranted;
      token=await _storage.read(key:_tokenKey);
      if(token!=null&&token!.isNotEmpty){
        final r=await _request('GET','/api/v1/ebirr-device',token:token);
        if(r['ok']!=true)throw Exception('Pairing token is not active.');
      }
    } catch(e) {
      final invalid=e.toString().toLowerCase().contains('invalid or revoked')||e.toString().contains('401');
      if(token!=null&&invalid){await _storage.delete(key:_tokenKey);token=null;}
      error=e.toString();
    } finally {if(mounted)setState(()=>loading=false);}
  }
  Future<Map<String,dynamic>> _request(String method,String path,{String? token,Map<String,dynamic>? body}) async {
    final uri=Uri.parse(AppConfig.apiBase).resolve(path);
    final headers=<String,String>{'Accept':'application/json','Content-Type':'application/json'};
    if(token!=null)headers['x-numelixa-device-token']=token;
    final response=method=='GET'?await http.get(uri,headers:headers).timeout(const Duration(seconds:20)):
      await http.post(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:20));
    final data=response.body.isEmpty?<String,dynamic>{}:jsonDecode(response.body);
    if(response.statusCode<200||response.statusCode>=300){
      final message=data is Map?(data['error']??data['message']??'HTTP ${response.statusCode}').toString():'HTTP ${response.statusCode}';
      throw Exception(message);
    }
    if(data is! Map<String,dynamic>)throw Exception('Invalid server response.');
    return data;
  }
  Future<void> _pair(String value) async {
    final clean=value.trim();
    if(clean.length<24)throw Exception('Geli Token-ka saxda ah ee laga soo saaray Admin Panel → eBirr.');
    final data=await _request('GET','/api/v1/ebirr-device',token:clean);
    if(data['ok']!=true)throw Exception('Token-ku ma shaqaynayo.');
    await _storage.write(key:_tokenKey,value:clean);
    if(!mounted)return;setState(()=>token=clean);
  }
  @override Widget build(BuildContext context){
    if(loading)return const _LoadingPage();
    if(token!=null)return EbirrAdminScreen(token:token!,permissionGranted:permission,onRevoke:()async{await _storage.delete(key:_tokenKey);if(mounted)setState(()=>token=null);});
    return _PairingPage(permissionGranted:permission,error:error,onPermission:()async{
      final p=await Permission.sms.request();if(mounted)setState(()=>permission=p.isGranted);
    },onPair:_pair);
  }
}

class EbirrAdminScreen extends StatefulWidget {
  const EbirrAdminScreen({super.key,required this.token,required this.permissionGranted,required this.onRevoke});
  final String token;final bool permissionGranted;final Future<void> Function() onRevoke;
  @override State<EbirrAdminScreen> createState()=>_EbirrAdminScreenState();
}
class _EbirrAdminScreenState extends State<EbirrAdminScreen> with WidgetsBindingObserver {
  Timer? poll;bool busy=false,syncing=false,open=false,permission=false;
  String message='',receiver='',instructions='',rate='';Map<String,dynamic> data={};
  final receiverCtrl=TextEditingController(),rateCtrl=TextEditingController(),instructionsCtrl=TextEditingController();
  @override void initState(){super.initState();WidgetsBinding.instance.addObserver(this);permission=widget.permissionGranted;_load();poll=Timer.periodic(const Duration(seconds:20),(_){_syncSms();_load(silent:true);});}
  @override void didChangeAppLifecycleState(AppLifecycleState s){if(s==AppLifecycleState.resumed){_load(silent:true);_syncSms();}}
  @override void dispose(){WidgetsBinding.instance.removeObserver(this);poll?.cancel();receiverCtrl.dispose();rateCtrl.dispose();instructionsCtrl.dispose();super.dispose();}
  Future<Map<String,dynamic>> _api(String method,{Map<String,dynamic>? body}) async {
    final uri=Uri.parse(AppConfig.apiBase).resolve('/api/v1/ebirr-device');
    final headers={'Accept':'application/json','Content-Type':'application/json','x-numelixa-device-token':widget.token};
    final response=method=='GET'?await http.get(uri,headers:headers).timeout(const Duration(seconds:20)):
      await http.post(uri,headers:headers,body:jsonEncode(body??{})).timeout(const Duration(seconds:20));
    final raw=response.body.isEmpty?<String,dynamic>{}:jsonDecode(response.body);
    if(response.statusCode<200||response.statusCode>=300)throw Exception(raw is Map?(raw['error']??'HTTP ${response.statusCode}').toString():'HTTP ${response.statusCode}');
    if(raw is! Map<String,dynamic>)throw Exception('Invalid server response.');
    return raw;
  }
  Future<void> _load({bool silent=false}) async {
    if(busy&&!silent)return;
    try{final d=await _api('GET');if(!mounted)return;final s=Map<String,dynamic>.from(d['settings']??{});
      setState((){data=d;open=s['open']==true;receiver=s['receiver']?.toString()??'';rate=(s['rate']??'').toString();instructions=s['instructions']?.toString()??'';receiverCtrl.text=receiver;rateCtrl.text=rate;instructionsCtrl.text=instructions;if(!silent)message='Xogta server-ka waa la cusboonaysiiyay.';});
    }catch(e){if(mounted&&!silent)setState(()=>message=e.toString());}
  }
  Future<void> _save() async {
    setState(()=>busy=true);
    try{await _api('POST',body:{'action':'save_settings','open':open,'rate':double.tryParse(rateCtrl.text.trim())??0,'receiver':receiverCtrl.text.trim(),'instructions':instructionsCtrl.text.trim()});if(mounted)setState(()=>message='Dejinta eBirr waa la kaydiyay.');await _load(silent:true);}
    catch(e){if(mounted)setState(()=>message=e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _closeOrder(String id) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(backgroundColor:_panel,title:const Text('Xir dalabkan?'),content:const Text('Lacag laguma shubayo wallet-ka. Dalabka waa la xirayaa.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Ka noqo')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Xir'))]));
    if(yes!=true)return;setState(()=>busy=true);
    try{await _api('POST',body:{'action':'close_order','orderId':id});setState(()=>message='Dalabka waa la xiray.');await _load(silent:true);}catch(e){setState(()=>message=e.toString());}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _syncSms() async {
    if(syncing||!permission)return;syncing=true;
    try{
      final after=int.tryParse(await _storage.read(key:_syncKey)??'')??(DateTime.now().subtract(const Duration(minutes:30)).millisecondsSinceEpoch);
      final rows=await _smsChannel.invokeMethod<List<dynamic>>('readRecentSms',{'after':after,'limit':80});
      var newest=after;var uploaded=0;
      for(final item in rows??[]){
        if(item is! Map)continue;final sms=Map<String,dynamic>.from(item);
        final date=(sms['date'] as num?)?.toInt()??0;if(date<=after)continue;if(date>newest)newest=date;
        final body=(sms['body']??'').toString().trim(),sender=(sms['address']??'').toString();
        if(body.isEmpty||!RegExp(r'ebirr|e-birr|\bbirr\b|ብር',caseSensitive:false).hasMatch(body+' '+sender))continue;
        final uri=Uri.parse(AppConfig.apiBase).resolve('/api/v1/payment-sms');
        final response=await http.post(uri,headers:{'Content-Type':'application/json','x-numelixa-device-token':widget.token},body:jsonEncode({
          'provider':'EBIRR','rawBody':body,'receivingSimPhone':receiver,'senderPhone':sender,
          'simOperator':'Android SIM ${sms['subscriptionId']??'unknown'}','deviceId':'ebirr-numelixa-android'
        })).timeout(const Duration(seconds:20));
        if(response.statusCode==401)throw Exception('Token-ka waa la joojiyay. Dib uga samee pairing Admin Panel-ka.');
        if(response.statusCode<200||response.statusCode>=300)throw Exception('SMS upload HTTP ${response.statusCode}');
        uploaded++;
      }
      if(newest>after)await _storage.write(key:_syncKey,value:newest.toString());
      if(uploaded>0&&mounted)setState(()=>message='$uploaded SMS lacag-bixin ah ayaa server-ka loo diray; xaqiijinta server-ka ayaa go’aaminaysa.');
    }catch(e){if(mounted&&e.toString().contains('Token-ka waa la joojiyay'))setState(()=>message=e.toString());}
    finally{syncing=false;}
  }
  Future<void> _askPermission() async {final p=await Permission.sms.request();if(mounted)setState(()=>permission=p.isGranted);if(p.isGranted)await _syncSms();}
  Future<void> _revoke() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(backgroundColor:_panel,title:const Text('Ka saar pairing-ka?'),content:const Text('App-kan ma sii diri doono SMS ilaa token cusub la geliyo.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Revoke'))]));
    if(yes!=true)return;
    try{await _api('POST',body:{'action':'revoke_device'});await widget.onRevoke();}catch(e){setState(()=>message=e.toString());}
  }
  List<Map<String,dynamic>> get orders=>(data['orders'] as List? ?? []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  List<Map<String,dynamic>> get events=>(data['events'] as List? ?? []).whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList();
  @override Widget build(BuildContext context){
    final pending=orders.where((o)=>!['paid','closed','rejected'].contains((o['status']??'').toString())).length;
    final paid=orders.where((o)=>o['status']=='paid').length;
    return Scaffold(backgroundColor:_ink,appBar:AppBar(backgroundColor:_ink,title:const Text('EBIRR · NUMELIXA',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1)),actions:[IconButton(onPressed:()=>_load(),icon:const Icon(Icons.refresh_rounded)),IconButton(onPressed:_revoke,icon:const Icon(Icons.link_off_rounded))]),body:RefreshIndicator(onRefresh:()=>_load(),child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('PAYMENT CONTROL CENTER',style:TextStyle(color:_mint,fontWeight:FontWeight.w900,letterSpacing:2,fontSize:11)),
      const SizedBox(height:7),const Text('eBirr Admin Dashboard',style:TextStyle(fontSize:27,fontWeight:FontWeight.w900)),
      const SizedBox(height:5),Text('SMS monitoring · Automatic receipt matching · Wallet audit',style:TextStyle(color:Colors.blueGrey.shade200,fontSize:12)),
      const SizedBox(height:16),
      if(message.isNotEmpty)_panel(child:Text(message,style:const TextStyle(color:_mint))),
      if(!permission)_panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('SMS permission is required',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:6),const Text('Allow SMS access so the app can read incoming eBirr receipts and send matching data to Numelixa securely.',style:TextStyle(color:Colors.white70)),const SizedBox(height:10),FilledButton(onPressed:_askPermission,child:const Text('Grant SMS permission'))])),
      Row(children:[_metric('PENDING',pending.toString(),Colors.orangeAccent),const SizedBox(width:9),_metric('PAID',paid.toString(),_mint),const SizedBox(width:9),_metric('SMS LOGS',events.length.toString(),_blue)]),
      const SizedBox(height:14),
      _panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Text('eBirr PAYMENT SETTINGS',style:TextStyle(fontWeight:FontWeight.w900))),Switch(value:open,onChanged:(v)=>setState(()=>open=v),activeColor:_mint)]),
        Text(open?'OPEN · Customers can pay with eBirr':'CLOSED · Hidden from customer checkout',style:TextStyle(color:open?_mint:Colors.orangeAccent,fontSize:12,fontWeight:FontWeight.bold)),
        const SizedBox(height:12),_field('ETB per 1 USD',rateCtrl,keyboard:TextInputType.number),
        _field('Official eBirr receiving number',receiverCtrl,keyboard:TextInputType.phone),
        _field('Payment instructions',instructionsCtrl,maxLines:3),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:_save,icon:const Icon(Icons.save_rounded),label:const Text('SAVE SETTINGS'),style:FilledButton.styleFrom(backgroundColor:_mint,foregroundColor:_ink)))
      ])),
      const SizedBox(height:14),
      _panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Text('AUTOMATIC SMS MONITOR',style:TextStyle(fontWeight:FontWeight.w900))),_status(syncing?'SYNCING':permission?'ACTIVE':'PERMISSION OFF',permission?_mint:Colors.orangeAccent)]),
        const SizedBox(height:8),const Text('App-ku wuxuu baarayaa SMS-yada cusub ee eBirr. Server-ku wuxuu xaqiijiyaa sender-ka, lacagta, lambarka diraha, receiver SIM iyo dalabka; wallet-ka hal mar oo keliya ayaa la credit-gareeyaa.',style:TextStyle(color:Colors.white70,height:1.45,fontSize:12)),
        const SizedBox(height:10),SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:syncing?null:_syncSms,icon:const Icon(Icons.sync),label:const Text('SCAN INCOMING SMS')))
      ])),
      const SizedBox(height:14),
      _panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Text('PAYMENT ORDERS',style:TextStyle(fontWeight:FontWeight.w900))),Text('${orders.length} total',style:const TextStyle(color:Colors.white54,fontSize:11))]),
        if(orders.isEmpty)const Padding(padding:EdgeInsets.all(14),child:Text('No eBirr orders found.',style:TextStyle(color:Colors.white60))),
        ...orders.map((o)=>_orderCard(o))
      ])),
      const SizedBox(height:14),
      _panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[const Expanded(child:Text('INCOMING SMS AUDIT LOG',style:TextStyle(fontWeight:FontWeight.w900))),Text('${events.length} records',style:const TextStyle(color:Colors.white54,fontSize:11))]),
        if(events.isEmpty)const Padding(padding:EdgeInsets.all(14),child:Text('No SMS events yet.',style:TextStyle(color:Colors.white60))),
        ...events.take(30).map((e)=>Padding(padding:const EdgeInsets.symmetric(vertical:9),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Expanded(child:Text('${e['provider']??'SMS'} · ${e['amount']??'—'} ETB',style:const TextStyle(fontWeight:FontWeight.bold))),_status(e['matched']==true?'MATCHED':'UNMATCHED',e['matched']==true?_mint:Colors.orangeAccent)]),
          Text('Payer: ${e['payerPhone']??'—'} · SIM: ${e['simPhone']??'—'}',style:const TextStyle(color:Colors.white60,fontSize:11)),
          Text('${e['reason']??''}',style:const TextStyle(color:Colors.white54,fontSize:11)),
          Text((e['rawBody']??'').toString(),maxLines:3,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white70,fontSize:11))
        ])))
      ])),
      const SizedBox(height:20),const Center(child:Text('NUMELIXA · SECURE ETHIOPIA PAYMENTS',style:TextStyle(color:Colors.white30,fontSize:10,letterSpacing:1.2)))
    ])));
  }
  Widget _orderCard(Map<String,dynamic> o){
    final status=(o['status']??'pending').toString();final paid=status=='paid';
    return Container(margin:const EdgeInsets.only(top:11),padding:13,decoration:BoxDecoration(color:const Color(0xff0b192b),borderRadius:BorderRadius.circular(13),border:Border.all(color:_line)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text('${o['method']??'eBirr'} · ${o['amountEtb']??'—'} ETB',style:const TextStyle(fontWeight:FontWeight.w900))),_status(status.toUpperCase(),paid?_mint:status=='closed'?Colors.white54:Colors.orangeAccent)]),
      const SizedBox(height:5),Text('Order: ${o['orderId']??'—'}',style:const TextStyle(color:Colors.white70,fontSize:11)),
      Text('Payer: ${o['payerPhone']??'—'} · USD ${o['amountUsd']??'—'}',style:const TextStyle(color:Colors.white60,fontSize:11)),
      Text('SMS: ${o['smsMatched']==true?'MATCHED':'WAITING'} · Ref: ${o['transactionReference']??'—'}',style:TextStyle(color:o['smsMatched']==true?_mint:Colors.orangeAccent,fontSize:11)),
      if(!paid&&status!='closed'&&status!='rejected')Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:busy?null:()=>_closeOrder((o['orderId']??'').toString()),icon:const Icon(Icons.close_rounded),label:const Text('CLOSE ORDER')))
    ]));
  }
}

class _PairingPage extends StatefulWidget {
  const _PairingPage({required this.permissionGranted,required this.onPermission,required this.onPair, this.error});
  final bool permissionGranted;final Future<void> Function() onPermission;final Future<void> Function(String) onPair;final String? error;
  @override State<_PairingPage> createState()=>_PairingPageState();
}
class _PairingPageState extends State<_PairingPage>{
  final controller=TextEditingController();bool busy=false;String error='';
  @override void dispose(){controller.dispose();super.dispose();}
  Future<void> pair()async{setState(()=>busy=true);try{await widget.onPair(controller.text);}catch(e){setState(()=>error=e.toString());}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(backgroundColor:_ink,body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(22),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:480),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
    const Icon(Icons.account_balance_wallet_rounded,color:_mint,size:58),const SizedBox(height:16),
    const Text('EBIRR · NUMELIXA',textAlign:TextAlign.center,style:TextStyle(color:_mint,fontWeight:FontWeight.w900,letterSpacing:2)),
    const SizedBox(height:10),const Text('Ku xidh Admin Panel-ka',textAlign:TextAlign.center,style:TextStyle(color:Colors.white,fontSize:27,fontWeight:FontWeight.w900)),
    const SizedBox(height:8),const Text('Marka ugu horraysa, oggolow SMS permission kadib geli pairing token-ka aad ka soo saartay Website Admin → eBirr → Generate pairing token.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white70,height:1.5)),
    const SizedBox(height:24),_panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('1 · SMS PERMISSION',style:TextStyle(fontWeight:FontWeight.w900)),
      const SizedBox(height:8),Text(widget.permissionGranted?'Granted · SMS inbox access is enabled':'Not granted · Allow access to scan incoming payment receipts',style:TextStyle(color:widget.permissionGranted?_mint:Colors.orangeAccent,fontSize:12)),
      const SizedBox(height:10),SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:busy?null:widget.onPermission,icon:const Icon(Icons.sms_outlined),label:Text(widget.permissionGranted?'Permission enabled':'Allow SMS access'))),
      const SizedBox(height:16),const Text('2 · ADMIN PAIRING TOKEN',style:TextStyle(fontWeight:FontWeight.w900)),
      const SizedBox(height:8),TextField(controller:controller,obscureText:true,autocorrect:false,enableSuggestions:false,decoration:const InputDecoration(hintText:'Paste one-time device token',filled:true,fillColor:_ink,border:OutlineInputBorder())),
      const SizedBox(height:12),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:pair,style:FilledButton.styleFrom(backgroundColor:_mint,foregroundColor:_ink,padding:const EdgeInsets.all(15)),child:Text(busy?'CONNECTING…':'CONNECT TO ADMIN PANEL',style:const TextStyle(fontWeight:FontWeight.w900)))),
      if(error.isNotEmpty||widget.error!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(error.isNotEmpty?error:widget.error!,style:const TextStyle(color:Colors.redAccent,fontSize:12)))
    ])),
    const SizedBox(height:16),const Text('Token-ka waa lagu kaydinayaa Android Secure Storage. Ha la wadaagin qof kale.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white38,fontSize:11))
  ]))))));
}

class _LoadingPage extends StatelessWidget {const _LoadingPage();@override Widget build(BuildContext context)=>const Scaffold(backgroundColor:_ink,body:Center(child:CircularProgressIndicator(color:_mint)));}
Widget _panel({required Widget child})=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(17),border:Border.all(color:_line)),child:child);
Widget _metric(String label,String value,Color color)=>Expanded(child:Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(14),border:Border.all(color:_line)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white54,fontSize:9,fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(value,style:TextStyle(color:color,fontSize:23,fontWeight:FontWeight.w900))])));
Widget _status(String text,Color color)=>Container(padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),decoration:BoxDecoration(color:color.withOpacity(.12),borderRadius:BorderRadius.circular(20)),child:Text(text,style:TextStyle(color:color,fontSize:9,fontWeight:FontWeight.w900)));
Widget _field(String label,TextEditingController c,{TextInputType? keyboard,int maxLines=1})=>Padding(padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:Colors.white70,fontSize:11)),const SizedBox(height:6),TextField(controller:c,keyboardType:keyboard,maxLines:maxLines,style:const TextStyle(color:Colors.white),decoration:const InputDecoration(filled:true,fillColor:_ink,border:OutlineInputBorder(),contentPadding:EdgeInsets.all(12)))]));
