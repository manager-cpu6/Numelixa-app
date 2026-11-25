import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/theme/app_theme.dart';

Future<void> showPaymentReceipt(
  BuildContext context, {
  required Map<String, dynamic> receipt,
  required String fallbackReference,
}) async {
  String value(String key) => (receipt[key] ?? '').toString();
  final amount = double.tryParse(value('amountUsd')) ?? 0;
  final paidAt = DateTime.tryParse(value('paidAt'));
  Widget line(String label, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 112, child: Text(label, style: const TextStyle(color: const Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800))),
      Expanded(child: Text(text.isEmpty ? '—' : text, textAlign: TextAlign.right, style: const TextStyle(color: const Color(0xFF111827), fontSize: 12, fontWeight: FontWeight.w800))),
    ]),
  );
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: double.infinity),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: const Color(0xFFD7DEE8)),
            boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 32, offset: Offset(0, 16))],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Container(
                    width: 43, height: 43,
                    decoration: BoxDecoration(
                      color: const Color(0xFF123B72),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.verified_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('NUMELIXA', style: TextStyle(color: const Color(0xFF102A56), fontWeight: FontWeight.w900, letterSpacing: 1.6, fontSize: 16)),
                    Text('OFFICIAL PAYMENT RECEIPT', style: TextStyle(color: const Color(0xFF64748B), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
                  ])),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(color: const Color(0xFFE8F7EF), borderRadius: BorderRadius.circular(30)),
                    child: const Text('VERIFIED', style: TextStyle(color: const Color(0xFF087D65), fontSize: 11, fontWeight: FontWeight.w900)),
                  ),
                ]),
                const SizedBox(height: 12),
                Center(child:SizedBox(width:190,child:Image.network('https://numelixa.com/brand/numelixa-official-branding.jpg',fit:BoxFit.contain,errorBuilder:(_,__,___)=>const SizedBox.shrink()))),
                const SizedBox(height: 12),
                const Text('PAYMENT RECEIVED', style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                Text('USD ' + amount.toStringAsFixed(2), style: const TextStyle(color: const Color(0xFF101C31), fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1.1)),
                const Text('Wallet credit confirmed', style: TextStyle(color: const Color(0xFF087D65), fontSize: 12, fontWeight: FontWeight.w800)),
                const Divider(height: 26, color: const Color(0xFFCBD5E1)),
                line('RECEIPT NUMBER', value('receiptId')),
                line('PAYMENT METHOD', value('service')),
                line('SENDER NUMBER', value('payerPhone')),
                line('RECEIVER NUMBER', value('receiverPhone')),
                line('TRANSACTION REF', value('transactionReference')),
                line('DATE & TIME', paidAt == null ? '—' : paidAt.toLocal().toString().split('.').first),
                line('WALLET CREDIT', (double.tryParse(value('walletCredit')) ?? 0).toStringAsFixed(0) + ' credits'),
                if ((double.tryParse(value('amountEtb')) ?? 0) > 0)
                  line('LOCAL PAYMENT', (double.tryParse(value('amountEtb')) ?? 0).ceil().toString() + ' ETB'),
                const SizedBox(height: 16),
                Center(child: Container(
                  width: 118, height: 118, padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.glassBorder)),
                  child: QrImageView(data: value('receiptId').isEmpty ? fallbackReference : value('receiptId'), size: 100, backgroundColor: Colors.white),
                )),
                const SizedBox(height: 7),
                Center(child: Text(value('receiptId'), style: const TextStyle(color: const Color(0xFF102A56), fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 11))),
                const SizedBox(height: 12),
                const Text('Generated from the Numelixa wallet ledger after successful server-side payment verification.', textAlign: TextAlign.center, style: TextStyle(color: const Color(0xFF64748B), fontSize: 10, height: 1.5)),
                const SizedBox(height: 8),
                
                const SizedBox(height: 16),
                FilledButton.icon(style:FilledButton.styleFrom(backgroundColor:const Color(0xFF123B72),foregroundColor:Colors.white),onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.check_circle_outline_rounded), label: const Text('Continue')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
