import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A small, crisp, vector-rendered Numelixa account verification mark.
class NumelixaVerifiedBadge extends StatelessWidget {
  const NumelixaVerifiedBadge({
    super.key,
    required this.verified,
    this.size = 18,
    this.color = const Color(0xFF1D9BF0),
  });

  final bool verified;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!verified) return const SizedBox.shrink();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _VerifiedBadgePainter(color)),
    );
  }
}

class _VerifiedBadgePainter extends CustomPainter {
  const _VerifiedBadgePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .49;
    final innerRadius = radius * .79;
    const points = 12;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final angle = -3.141592653589793 / 2 + i * 3.141592653589793 / points;
      final r = i.isEven ? radius : innerRadius;
      final point = Offset(center.dx + r * math.cos(angle), center.dy + r * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    final check = Path()
      ..moveTo(size.width * .27, size.height * .52)
      ..lineTo(size.width * .43, size.height * .66)
      ..lineTo(size.width * .74, size.height * .35);
    canvas.drawPath(
      check,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * .115
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }



  @override
  bool shouldRepaint(covariant _VerifiedBadgePainter oldDelegate) => oldDelegate.color != color;
}
