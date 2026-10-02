import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Recreation of the arrows and leaf drawn by the original website.
class EcoBrand extends StatelessWidget {
  const EcoBrand({this.size = 82, this.ring = false, super.key});
  final double size;
  final bool ring;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BrandPainter(ring: ring)),
  );
}

class _BrandPainter extends CustomPainter {
  const _BrandPainter({required this.ring});
  final bool ring;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100);
    if (ring) {
      canvas.drawCircle(
        const Offset(50, 50),
        48,
        Paint()
          ..color = const Color(0x5577E37B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    final rect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(12, 12, 76, 76),
      const Radius.circular(24),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF77E37B), Color(0xFF2D8D37)],
        ).createShader(rect.outerRect),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(21, 21, 58, 58),
        const Radius.circular(18),
      ),
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    for (var i = 0; i < 3; i++) {
      canvas.save();
      canvas.translate(50, 50);
      canvas.rotate(i * math.pi * 2 / 3);
      final arrow = Path()
        ..moveTo(-14, -22)
        ..lineTo(4, -22)
        ..lineTo(4, -27)
        ..lineTo(17, -17)
        ..lineTo(4, -7)
        ..lineTo(4, -12)
        ..lineTo(-14, -12)
        ..quadraticBezierTo(-20, -17, -14, -22);
      canvas.drawPath(arrow, Paint()..color = const Color(0xFFF7FFF7));
      canvas.restore();
    }
    final leaf = Path()
      ..moveTo(41, 59)
      ..cubicTo(29, 38, 56, 33, 62, 37)
      ..cubicTo(64, 55, 50, 61, 41, 59);
    canvas.drawPath(leaf, Paint()..color = const Color(0xFFDCFFDE));
    canvas.drawLine(
      const Offset(41, 60),
      const Offset(57, 41),
      Paint()
        ..color = const Color(0xFF66C86B)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.ring != ring;
}
