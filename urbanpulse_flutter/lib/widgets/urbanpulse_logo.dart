import 'package:flutter/material.dart';

/// The app mark, ported from `drawable/ic_urbanpulse_logo.xml` — a shield/leaf
/// silhouette carrying a pulse waveform and a geo-beacon pin. Drawn directly
/// rather than shipped as a raster so it stays crisp at every size.
class UrbanPulseLogo extends StatelessWidget {
  const UrbanPulseLogo({this.size = 120, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _LogoPainter(),
      isComplex: true,
      child: const SizedBox.expand(),
    ),
  );
}

class _LogoPainter extends CustomPainter {
  /// Source viewport of the original vector drawable.
  static const _viewport = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _viewport;
    canvas.save();
    canvas.scale(scale);

    // Outer glow capsule ring.
    canvas.drawCircle(
      const Offset(60, 60),
      50,
      Paint()..color = const Color(0x1510B981),
    );

    // Sleek geometric shield / leaf foundation.
    final shield = Path()
      ..moveTo(60, 22)
      ..cubicTo(80, 22, 96, 38, 96, 60)
      ..cubicTo(96, 86, 60, 102, 60, 102)
      ..cubicTo(60, 102, 24, 86, 24, 60)
      ..cubicTo(24, 38, 40, 22, 60, 22)
      ..close();
    canvas.drawPath(shield, Paint()..color = const Color(0xFF1E293B));
    canvas.drawPath(
      shield,
      Paint()
        ..color = const Color(0xFF334155)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Vibrant pulse waveform (green & inclusive city heartbeat).
    final waveform = Path()
      ..moveTo(34, 60)
      ..lineTo(46, 60)
      ..lineTo(52, 42)
      ..lineTo(62, 78)
      ..lineTo(70, 52)
      ..lineTo(76, 64)
      ..lineTo(86, 60);
    canvas.drawPath(
      waveform,
      Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Smart city geo-beacon pin core.
    final pin = Path()
      ..moveTo(60, 34)
      ..cubicTo(63.3, 34, 66, 36.7, 66, 40)
      ..cubicTo(66, 44.5, 60, 50, 60, 50)
      ..cubicTo(60, 50, 54, 44.5, 54, 40)
      ..cubicTo(54, 36.7, 56.7, 34, 60, 34)
      ..close();
    canvas.drawPath(pin, Paint()..color = const Color(0xFF38BDF8));
    canvas.drawCircle(
      const Offset(60, 40),
      2,
      Paint()..color = const Color(0xFF0F172A),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}
