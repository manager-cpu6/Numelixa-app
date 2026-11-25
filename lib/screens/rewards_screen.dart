import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState()=>_RewardsScreenState();
}
class _RewardsScreenState extends State<RewardsScreen>{
  Map<String,dynamic>? _data;
  bool _loading=true,_busy=false;
  String? _error;
  final _amount=TextEditingController(),_account=TextEditingController();
  String _country='Ethiopia',_bank='Commercial Bank of Ethiopia';
  final Map<String,List<String>> _banks={
    'Ethiopia':['Commercial Bank of Ethiopia','Awash Bank','Dashen Bank','Bank of Abyssinia','Wegagen Bank','Hibret Bank','Oromia Bank','Telebirr'],
    'Somalia':['Premier Bank','Salaam Somali Bank','Dahabshiil Bank','Amal Bank'],
    'Kenya':['KCB Bank','Equity Bank','Co-operative Bank','M-Pesa'],
  };
  @override
  void initState(){super.initState();_load();}
  @override
  void dispose(){_amount.dispose();_account.dispose();super.dispose();}
  String _money(dynamic n)=>'\$'+(double.tryParse(n?.toString()??'')??0).toStringAsFixed(2);
  Future<void> _load()async{
    try{final auth=context.read<AuthService>();final d=await ApiClient().get('/api/referrals',accessToken:auth.accessToken);if(d['ok']!=true)throw ApiException((d['error']??'Unable to load rewards.').toString());if(mounted)setState(()=>_data=d);}
    on ApiException catch(e){if(mounted)setState(()=>_error=e.message);}catch(_){if(mounted)setState(()=>_error='Rewards are temporarily unavailable.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _copyLink()async{final link=(_data?['link']??'').toString();if(link.isEmpty)return;await Clipboard.setData(ClipboardData(text:link));if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Referral link copied.')));}
  Future<void> _withdraw()async{
    final amount=double.tryParse(_amount.text.trim())??0,balance=double.tryParse(_data?['balanceUsd']?.toString()??'')??0;
    if(amount<=0||amount>balance||_account.text.trim().length<4){setState(()=>_error='Enter a valid amount and bank account details.');return;}
    setState((){_busy=true;_error=null;});
    try{
      final auth=context.read<AuthService>();
      final method='$_country · $_bank';
      final account=_account.text.trim();
      final d=await ApiClient().post('/api/referrals',accessToken:auth.accessToken,body:{'amountUsd':amount,'method':method,'account':account});
      if(d['ok']!=true)throw ApiException((d['error']??'Withdrawal request was not accepted.').toString());
      if(!mounted)return;
      final requestedAt=DateTime.now();
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        backgroundColor:const Color(0xFFF7FAFF),
        title:const Row(children:[Icon(Icons.hourglass_top_rounded,color:Color(0xFFD28B20)),SizedBox(width:9),Expanded(child:Text('Withdrawal pending',style:TextStyle(color:Color(0xFF17263B),fontWeight:FontWeight.w900)))]),
        content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(_money(amount),style:const TextStyle(color:Color(0xFF17263B),fontSize:30,fontWeight:FontWeight.w900)),
          Text('Bank: $_bank',style:const TextStyle(color:Color(0xFF53647A))),
          Text('Country: $_country',style:const TextStyle(color:Color(0xFF53647A))),
          Text('Account: $account',style:const TextStyle(color:Color(0xFF53647A))),
          Text('Date: $requestedAt',style:const TextStyle(color:Color(0xFF53647A))),
          const SizedBox(height:10),const Text('Your request is pending Admin review. A confirmation email has been requested.',style:TextStyle(color:Color(0xFF53647A),fontSize:12)),
        ]),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Continue'))],
      ));
      _amount.clear();_account.clear();await _load();
    }on ApiException catch(e){if(mounted)setState(()=>_error=e.message);}catch(_){if(mounted)setState(()=>_error='Unable to submit withdrawal.');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override
  Widget build(BuildContext context){
    final d=_data;
    return Scaffold(appBar:AppBar(title:const Text('Numelixa Rewards'),actions:[IconButton(onPressed:_load,icon:const Icon(Icons.refresh_rounded))]),body:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.fromLTRB(16,12,16,28),children:[
      Container(padding:const EdgeInsets.all(20),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF103B6E),Color(0xFF25184E)]),borderRadius:BorderRadius.circular(24),border:Border.all(color:AppTheme.cyan.withValues(alpha:.25))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Icon(Icons.card_giftcard_rounded,color:Color(0xFFFFD36B),size:34),const SizedBox(height:12),
        const Text('Share Numelixa. Earn rewards.',style:TextStyle(fontSize:22,fontWeight:FontWeight.w900)),
        const SizedBox(height:8),const Text('Invite friends and earn when their eligible payments are verified.',style:TextStyle(color:AppTheme.muted,height:1.5)),
        const SizedBox(height:18),const Text('AVAILABLE REWARDS',style:TextStyle(color:AppTheme.cyan,fontSize:10,fontWeight:FontWeight.w900,letterSpacing:1.4)),
        Text(_money(d?['balanceUsd']),style:const TextStyle(fontSize:34,fontWeight:FontWeight.w900)),
        const SizedBox(height:12),OutlinedButton.icon(onPressed:d==null?null:_copyLink,icon:const Icon(Icons.share_rounded),label:const Text('Copy referral link')),
      ])),
      if(_error!=null)Padding(padding:const EdgeInsets.all(10),child:Text(_error!,style:const TextStyle(color:AppTheme.error))),
      if(d!=null)...[
        const SizedBox(height:16),Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('YOUR REFERRAL CODE',style:TextStyle(color:AppTheme.cyan,fontSize:11,fontWeight:FontWeight.w900)),
          const SizedBox(height:8),Text((d['code']??'—').toString(),style:const TextStyle(fontSize:24,fontWeight:FontWeight.w900,letterSpacing:2)),
          Text('${d['referrals']??0} invited accounts · ${d['commissionPercent']??0}% reward rate',style:const TextStyle(color:AppTheme.muted,fontSize:12)),
        ]))),
        const SizedBox(height:16),Text('Withdraw rewards',style:Theme.of(context).textTheme.titleLarge),
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          TextField(controller:_amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Amount (USD) · Available '+_money(d['balanceUsd']))),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(initialValue:_country,decoration:const InputDecoration(labelText:'Country'),items:_banks.keys.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:_busy?null:(v){if(v!=null)setState(()=>{_country=v,_bank=_banks[v]!.first});}),
          const SizedBox(height:10),
          DropdownButtonFormField<String>(initialValue:_bank,decoration:const InputDecoration(labelText:'Bank / payout service'),items:_banks[_country]!.map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:_busy?null:(v){if(v!=null)setState(()=>_bank=v);}),
          const SizedBox(height:10),
          TextField(controller:_account,keyboardType:TextInputType.text,decoration:const InputDecoration(labelText:'Account number / receiving details')),
          const SizedBox(height:14),
          FilledButton.icon(onPressed:_busy?null:_withdraw,icon:_busy?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.account_balance_rounded),label:Text(_busy?'Submitting…':'Request withdrawal')),
          const SizedBox(height:8),const Text('Withdrawal status remains Pending until Admin reviews the request. Rejected requests are returned to your rewards balance.',style:TextStyle(color:AppTheme.muted,fontSize:11,height:1.5)),
        ]))),
        const SizedBox(height:16),Text('Withdrawal history',style:Theme.of(context).textTheme.titleLarge),
        ...((d['withdrawals'] is List)?(d['withdrawals'] as List).take(15).map((x)=>Card(child:ListTile(leading:Icon(Icons.receipt_long_rounded,color:(x['status']=='pending')?const Color(0xFFFFC46B):AppTheme.cyan),title:Text(_money(x['amountUsd'])),subtitle:Text('${x['method']??''} · ${x['createdAt']??''}'),trailing:Text((x['status']??'pending').toString().toUpperCase(),style:const TextStyle(fontSize:10,fontWeight:FontWeight.w900))))):[]),
      ],
    ]));
  }
}
