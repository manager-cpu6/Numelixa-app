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
 final id=TextEditingController();
 final amount=TextEditingController();
 final note=TextEditingController();
 bool loading=true,busy=false;
 List<Map<String,dynamic>> requests=[];
 String get token=>context.read<AuthService>().accessToken??'';
 String get myId=>(context.read<AuthService>().user?['id']??'').toString();
 String money(dynamic value)=>String.fromCharCode(36)+(double.tryParse(value?.toString()??'')??0).toStringAsFixed(2);
 @override void initState(){super.initState();load();}
 @override void dispose(){id.dispose();amount.dispose();note.dispose();super.dispose();}

 Future<void> load()async{
  try{
   final result=await ApiClient().get('/api/wallet/requests',accessToken:token);
   final raw=result['requests'];
   if(mounted)setState(()=>requests=raw is List?raw.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():[]);
  }catch(e){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));
  }finally{if(mounted)setState(()=>loading=false);}
 }

 Future<void> create()async{
  final userId=id.text.trim(),usd=double.tryParse(amount.text.trim());
  if(!RegExp(r'^\d{7}$').hasMatch(userId)||usd==null||usd<=0){
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid 7-digit ID and USD amount.')));
   return;
  }
  setState(()=>busy=true);
  try{
   await ApiClient().post('/api/wallet/requests',accessToken:token,body:{'userId':userId,'amountUsd':usd,'note':note.text.trim()});
   id.clear();amount.clear();note.clear();
   await load();
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Money request sent.')));
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>busy=false);}
 }

 Future<void> act(Map<String,dynamic> request,String action)async{
  if(action=='confirm'){
   final person=Map<String,dynamic>.from(request['requester']??{});
   final message='Send '+money(request['amountUsd'])+' to '+(person['name']??'Numelixa user').toString()+' (ID '+(person['publicId']??'—').toString()+')?';
   final yes=await showDialog<bool>(context:context,builder:(dialog)=>AlertDialog(
    title:const Text('Confirm payment'),
    content:Text(message),
    actions:[
     TextButton(onPressed:()=>Navigator.pop(dialog,false),child:const Text('Cancel')),
     FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:const Text('Continue'))
    ]));
   if(yes!=true||!mounted)return;
  }
  setState(()=>busy=true);
  try{
   final result=await ApiClient().patch('/api/wallet/requests',accessToken:token,body:{'requestId':request['id'],'action':action});
   await load();
   if(action=='confirm'&&mounted){
    final receipt=Map<String,dynamic>.from(result['receipt']??{});
    final paidTo=Map<String,dynamic>.from(receipt['paidTo']??request['requester']??{});
    final receiptText='Receipt: '+(receipt['receiptId']??'—').toString()+'\nAmount: '+money(request['amountUsd'])+' USD\nPaid to: '+(paidTo['name']??'Numelixa user').toString()+'\nNumelixa ID: '+(paidTo['publicId']??'—').toString()+'\nPaid at: '+(receipt['paidAt']??DateTime.now().toIso8601String()).toString()+'\nThe wallet debit and credit have been recorded.';
    await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
     title:const Text('Transfer complete'),
     content:Text(receiptText),
     actions:[FilledButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Confirm'))]
    ));
   }
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString())));}
  finally{if(mounted)setState(()=>busy=false);}
 }

 @override Widget build(BuildContext context)=>Scaffold(
  appBar:AppBar(title:const Text('Request money'),actions:[IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh))]),
  body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
   Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Text('REQUEST FROM ANOTHER USER',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900)),
    const SizedBox(height:8),
    const Text('Enter their 7-digit Numelixa ID and the amount. They can Confirm or Reject the request.',style:TextStyle(color:AppTheme.muted)),
    const SizedBox(height:14),
    TextField(controller:id,keyboardType:TextInputType.number,maxLength:7,decoration:const InputDecoration(labelText:'User Numelixa ID',counterText:'')),
    TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount (USD)')),
    TextField(controller:note,maxLength:140,decoration:const InputDecoration(labelText:'Note (optional)')),
    const SizedBox(height:8),
    SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:create,child:Text(busy?'Please wait…':'Send request')))
   ]))),
   const SizedBox(height:18),
   const Text('REQUEST ACTIVITY',style:TextStyle(color:AppTheme.cyan,fontWeight:FontWeight.w900)),
   if(requests.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No money requests yet.'))),
   ...requests.map((request){
    final payer=Map<String,dynamic>.from(request['payer']??{});
    final incoming=(payer['id']??'').toString()==myId;
    final other=Map<String,dynamic>.from((incoming?request['requester']:request['payer'])??{});
    final status=(request['status']??'pending').toString();
    final detail='ID '+(other['publicId']??'—').toString()+' · '+status.toUpperCase()+'\n'+money(request['amountUsd'])+' USD';
    return Card(child:ListTile(
     isThreeLine:true,
     title:Text((incoming?'Request from ':'Request to ')+(other['name']??'User').toString()),
     subtitle:Text(detail),
     trailing:incoming&&status=='pending'
      ?PopupMenuButton<String>(enabled:!busy,onSelected:(value)=>act(request,value),itemBuilder:(_)=>const[
       PopupMenuItem(value:'confirm',child:Text('Confirm')),
       PopupMenuItem(value:'reject',child:Text('Reject'))
      ])
      :status=='confirmed'?const Icon(Icons.verified,color:AppTheme.mint):null
    ));
   })
  ])
 );
}
