import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({super.key});
  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}
class _VouchersScreenState extends State<VouchersScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  bool _emailSent = false;
  String? _error;
  Map<String,dynamic>? _receipt;
  @override
  void dispose(){_code.dispose();super.dispose();}
  Future<void> _redeem() async {
    final code=_code.text.trim().toUpperCase();
    if(code.length<6){setState(()=>_error='Enter your complete voucher code.');return;}
    setState((){_busy=true;_error=null;});
    try{
      final auth=context.read<AuthService>();
      final result=await ApiClient().post('/api/mobile/vouchers/redeem',accessToken:auth.accessToken,body:{'code':code});
      if(result['ok']!=true||result['receipt'] is! Map)throw ApiException((result['error']??'Voucher redemption was not confirmed.').toString());
      if(!mounted)return;
      setState((){_receipt=Map<String,dynamic>.from(result['receipt'] as Map);_emailSent=result['emailSent']==true;});
      _code.clear();
    }on ApiException catch(e){if(mounted)setState(()=>_error=e.message);}
    catch(_){if(mounted)setState(()=>_error='Unable to redeem this code right now. Please try again.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  String _money(dynamic value)=>'\$' + (double.tryParse(value?.toString()??'')??0).toStringAsFixed(2);
  String _date(dynamic value){final d=DateTime.tryParse(value?.toString()??'')?.toLocal();if(d==null)return 'Date unavailable';return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year} · ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';}
  @override
  Widget build(BuildContext context){
    final receipt=_receipt;
    return Scaffold(appBar:AppBar(title:const Text('Vouchers')),body:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,28),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF103C70),Color(0xFF21194F)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:AppTheme.cyan.withValues(alpha:.25))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        ClipRRect(borderRadius:BorderRadius.circular(16),child:SizedBox(height:132,width:double.infinity,child:SvgPicture.asset('assets/numelixa-voucher-hero.svg',width:double.infinity,height:132,fit:BoxFit.cover))),const SizedBox(height:14),
        Text('Redeem a Numelixa voucher',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),SizedBox(height:6),
        Text('Enter your voucher code. If it is valid, the reward is added to your wallet and a receipt is sent to your email.',style:TextStyle(color:AppTheme.muted,height:1.5)),
      ])),
      const SizedBox(height:18),
      if(receipt==null) ...[
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Text('VOUCHER CODE',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900,fontSize:11,letterSpacing:1.5)),const SizedBox(height:10),
          TextField(controller:_code,enabled:!_busy,textCapitalization:TextCapitalization.characters,autocorrect:false,enableSuggestions:false,inputFormatters:[FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),LengthLimitingTextInputFormatter(48)],decoration:const InputDecoration(hintText:'NX-XXXXXXXXXXXX',prefixIcon:Icon(Icons.confirmation_number_outlined))),
          if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:const TextStyle(color:AppTheme.error))),
          const SizedBox(height:16),
          FilledButton.icon(onPressed:_busy?null:_redeem,icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.redeem_rounded),label:Text(_busy?'Verifying code…':'Redeem voucher')),
        ]))),
        const SizedBox(height:10),
        const Text('Only official active codes can be redeemed. Each account can use a voucher only as permitted by its redemption limit.',style:TextStyle(color:AppTheme.muted,fontSize:12,height:1.5)),
      ]else ...[
        Center(child:Container(width:302,padding:const EdgeInsets.fromLTRB(18,20,18,16),decoration:BoxDecoration(color:Colors.white,border:Border.all(color:const Color(0xFFD7DEE8)),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.20),blurRadius:24,offset:const Offset(0,12))]),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Center(child:Image.asset('assets/numelixa_app_icon.webp',width:48,height:48,fit:BoxFit.contain)),
          const SizedBox(height:7),const Text('NUMELIXA',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF102A56),fontSize:21,fontWeight:FontWeight.w900,letterSpacing:3)),
          const Text('OFFICIAL VOUCHER RECEIPT',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF64748B),fontSize:9,fontWeight:FontWeight.w900,letterSpacing:1.5)),
          const SizedBox(height:12),const Divider(color:Color(0xFF94A3B8),thickness:1.3),
          const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.verified_rounded,color:Color(0xFF07845F),size:18),SizedBox(width:6),Text('VOUCHER REDEEMED',style:TextStyle(color:Color(0xFF087D65),fontWeight:FontWeight.w900,letterSpacing:1.2,fontSize:11))]),
          const SizedBox(height:8),Text(_money(receipt['amountUsd']),textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF101C31),fontSize:34,fontWeight:FontWeight.w900)),
          const Text('CREDITED TO YOUR NUMELIXA WALLET',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF53647A),fontSize:9,fontWeight:FontWeight.w800,letterSpacing:.7)),
          const SizedBox(height:12),const Divider(color:Color(0xFFCBD5E1)),
          _receiptLine('Voucher code',receipt['code']),_receiptLine('Receipt number',receipt['receiptNumber']),_receiptLine('Date & time',_date(receipt['redeemedAt'])),_receiptLine('Wallet balance',_money(receipt['balanceUsd'])),_receiptLine('Coins credited',receipt['creditedCoins']),_receiptLine('Status','SUCCESSFUL'),
          const SizedBox(height:12),Center(child:QrImageView(data:(receipt['receiptNumber']??'').toString(),size:104,backgroundColor:Colors.white)),
          const SizedBox(height:8),Center(child:Image.asset('assets/numelixa_app_icon.webp',width:190,fit:BoxFit.contain)),
          const SizedBox(height:7),Text(_emailSent?'Receipt emailed from receipts@numelixa.com.':'Voucher credited. Email delivery could not be confirmed; keep this receipt.',textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF53647A),fontSize:10,height:1.45)),
          const Divider(color:Color(0xFF94A3B8),thickness:1.3),const Text('THANK YOU FOR CHOOSING NUMELIXA',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF334155),fontSize:9,fontWeight:FontWeight.w900,letterSpacing:.7)),
          const SizedBox(height:4),const Text('receipts@numelixa.com · numelixa.com',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF64748B),fontSize:9)),
        ]))),
        const SizedBox(height:16),FilledButton(onPressed:()=>setState(()=>_receipt=null),child:const Text('Continue')),
      ],
    ]));
  }
  Widget _receiptLine(String label,dynamic value)=>Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(label,style:const TextStyle(color:Color(0xFF65748A),fontSize:12))),const SizedBox(width:12),Flexible(child:Text((value??'—').toString(),textAlign:TextAlign.right,style:const TextStyle(color:Color(0xFF14233A),fontSize:12,fontWeight:FontWeight.w800)))]));
}
