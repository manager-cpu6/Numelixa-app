import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_theme.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class RequestMoneyScreen extends StatefulWidget {
 const RequestMoneyScreen({super.key});
 @override State<RequestMoneyScreen> createState()=>_RequestMoneyScreenState();
}
class _RequestMoneyScreenState extends State<RequestMoneyScreen>{
 final id=TextEditingController(),amount=TextEditingController(),note=TextEditingController();
 bool loading=true,busy=false;List<Map<String,dynamic>> requests=[];
 String get token=>context.read<AuthService>().accessToken??'';
 String get myId=>(context.read<AuthService>().user?['id']??'').toString();
 @override void initState(){super.initState();load();}
 @override void dispose(){id.dispose();amount.dispose();note.dispose();super.dispose();}
 Future<void> load()async{try{final x=await ApiClient().get('/api/wallet/requests',accessToken:token);final raw=x['requests'];if(mounted)setState(()=>requests=raw is List?raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():[]);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>loading=false);}}
 Future<void> create()async{final uid=id.text.trim(),usd=double.tryParse(amount.text.trim());if(!RegExp(r'^\d{7}$').hasMatch(uid)||usd==null||usd<=0){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid 7-digit ID and USD amount.')));return;}setState(()=>busy=true);try{await ApiClient().post('/api/wallet/requests',accessToken:token,body:{'userId':uid,'amountUsd':usd,'note':note.text.trim()});id.clear();amount.clear();note.clear();await load();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Money request sent.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>busy=false);}}
 Future<void> act(Map<String,dynamic> r,String action)async{if(action=='confirm'){final person=Map<String,dynamic>.from(r['requester']??{});final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Confirm payment'),content:Text('Send $'+NumberFormatAmount.usd(r['amountUsd'])+' to '+(person['name']??'Numelixa user').toString()+' (ID '+(person['publicId']??'—').toString()+')?'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Continue'))]));if(yes!=true||!mounted)return;}
 setState(()=>busy=true);try{final result=await ApiClient().patch('/api/wallet/requests',accessToken:token,body:{'requestId':r['id'],'action':action});await load();if(action=='confirm'&&mounted){final receipt=Map<String,dynamic>.from(result['receipt']??{});await showDialog<void>(context:context,builder:(c)=>AlertDialog(title:const Text('Transfer complete'),content:Text('Receipt: '+(receipt['receiptId']??'—').toString()+'\nAmount: $'+NumberFormatAmount.usd(r['amountUsd'])+' USD\nThe wallet debit and credit have been recorded.'),actions:[FilledButton(onPressed:()=>Navigator.pop(c),child:const Text('Done'))]));}}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}finally{if(mounted)setState(()=>busy=false);}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Request money'),actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
 Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
 const Text('REQUEST FROM ANOTHER USER',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900)),
 const SizedBox(height:8),const Text('Enter their 7-digit Numelixa ID and the amount. They can Confirm or Reject the request.',style:TextStyle(color:AppTheme.muted)),
 const SizedBox(height:14),TextField(controller:id,keyboardType:TextInputType.number,maxLength:7,decoration:const InputDecoration(labelText:'User Numelixa ID',counterText:'')),
 TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount (USD)')),
 TextField(controller:note,maxLength:140,decoration:const InputDecoration(labelText:'Note (optional)')),
 const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:create,child:Text(busy?'Please wait…':'Send request'))),
 ]))),
 const SizedBox(height:18),const Text('REQUEST ACTIVITY',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900)),
 if(requests.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No money requests yet.'))),
 ...requests.map((r){final incoming=String(r['payer']?['id']??'')==myId;final other=Map<String,dynamic>.from((incoming?r['requester']:r['payer'])??{});final status=String(r['status']??'pending');return Card(child:ListTile(isThreeLine:true,title:Text((incoming?'Request from ':'Request to ')+(other['name']??'User').toString()),subtitle:Text('ID '+(other['publicId']??'—').toString()+' · '+status.toUpperCase()+'\n$'+NumberFormatAmount.usd(r['amountUsd'])+' USD'),trailing:incoming&&status=='pending'?PopupMenuButton<String>(enabled:!busy,onSelected:(v)=>act(r,v),itemBuilder:(_)=>const [PopupMenuItem(value:'confirm',child:Text('Confirm')),PopupMenuItem(value:'reject',child:Text('Reject'))]):status=='confirmed'?const Icon(Icons.verified,color:AppTheme.mint):null));}),
 ]));
}
class NumberFormatAmount{static String usd(dynamic v)=>((double.tryParse(v?.toString()??'')??0).toStringAsFixed(2));}
