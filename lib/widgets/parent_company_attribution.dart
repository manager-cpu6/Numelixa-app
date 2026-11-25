import 'package:flutter/material.dart';

class ParentCompanyAttribution extends StatelessWidget {
  const ParentCompanyAttribution({super.key, required this.label, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(label, textAlign: TextAlign.center, style: TextStyle(
      color: color ?? Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: .72),
      fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .55,
    )),
  );
}
