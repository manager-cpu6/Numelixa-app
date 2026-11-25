import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
      setState(()=>_receipt=Map<String,dynamic>.from(result['receipt'] as Map));
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
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF103C70),Color(0xFF21194F)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:AppTheme.cyan.withValues(alpha:.25))),child:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Icon(Icons.card_giftcard_rounded,color:AppTheme.cyan,size:34),SizedBox(height:14),
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
        Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(color:const Color(0xFFF8FBFF),borderRadius:BorderRadius.circular(22),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.22),blurRadius:22,offset:const Offset(0,12))]),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          const Center(child:Icon(Icons.verified_rounded,color:Color(0xFF079B79),size:54)),const SizedBox(height:10),
          const Text('VOUCHER REDEEMED',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF087D65),fontWeight:FontWeight.w900,letterSpacing:1.4)),const SizedBox(height:6),
          Text(_money(receipt['amountUsd']),textAlign:TextAlign.center,style:const TextStyle(color:Color(0xFF101C31),fontSize:34,fontWeight:FontWeight.w900)),
          const Text('Added to your Numelixa wallet',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF53647A))),
          const Divider(height:28,color:Color(0xFFDCE4EF)),
          _receiptLine('Voucher code',receipt['code']),_receiptLine('Receipt number',receipt['receiptNumber']),_receiptLine('Date',_date(receipt['redeemedAt'])),_receiptLine('Wallet balance',_money(receipt['balanceUsd'])),_receiptLine('Status','Successful'),
          const SizedBox(height:14),const Text('A copy of this receipt has been sent to your registered email address.',textAlign:TextAlign.center,style:TextStyle(color:Color(0xFF53647A),fontSize:12,height:1.45)),
        ])),
        const SizedBox(height:16),FilledButton(onPressed:()=>setState(()=>_receipt=null),child:const Text('Continue')),
      ],
    ]));
  }
  Widget _receiptLine(String label,dynamic value)=>Padding(padding:const EdgeInsets.symmetric(vertical:7),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(label,style:const TextStyle(color:Color(0xFF65748A),fontSize:12))),const SizedBox(width:12),Flexible(child:Text((value??'—').toString(),textAlign:TextAlign.right,style:const TextStyle(color:Color(0xFF14233A),fontSize:12,fontWeight:FontWeight.w800)))]));
}
