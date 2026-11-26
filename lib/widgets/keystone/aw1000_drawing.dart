import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';

class Aw1000Drawing extends StatelessWidget {
  const Aw1000Drawing({
    super.key,
    this.lights = RouterLights.unlit,
    this.width = 100,
  });

  final RouterLights lights;
  final double width;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(width, width * 1.32),
    painter: _Aw1000Painter(lights),
  );
}

const _ink = Color(0xFF0B1220);
const _labels = ['POWER', '5G', 'MOBILE SIGNAL', 'WI-FI', 'INTERNET', 'PHONE'];

Color _led(LightColor c) => switch (c) {
  LightColor.green => KeystoneColors.ledGreen,
  LightColor.red => KeystoneColors.ledRed,
  LightColor.blue => KeystoneColors.ledBlue,
  LightColor.off => KeystoneColors.ledOff,
};

final _body = Path()
  ..moveTo(18.2, 10.4)
  ..arcToPoint(const Offset(24.2, 4.4), radius: const Radius.circular(6))
  ..lineTo(75.8, 4.4)
  ..arcToPoint(const Offset(81.8, 10.4), radius: const Radius.circular(6))
  ..lineTo(83.4, 108.6)
  ..quadraticBezierTo(83.4, 110.6, 81.4, 110.6)
  ..lineTo(18.6, 110.6)
  ..quadraticBezierTo(16.6, 110.6, 16.6, 108.6)
  ..close();

final _base = Path()
  ..moveTo(16.6, 110.6)
  ..lineTo(83.4, 110.6)
  ..lineTo(83.4, 113.6)
  ..cubicTo(83.4, 119.4, 81.4, 121.8, 76.4, 121.8)
  ..lineTo(23.6, 121.8)
  ..cubicTo(18.6, 121.8, 16.6, 119.4, 16.6, 113.6)
  ..close();

Paint _linear(
  Rect r,
  List<Color> colors,
  List<double> stops, {
  bool down = false,
}) => Paint()
  ..shader = LinearGradient(
    begin: down ? Alignment.topCenter : Alignment.centerLeft,
    end: down ? Alignment.bottomCenter : Alignment.centerRight,
    colors: colors,
    stops: stops,
  ).createShader(r);

class _Aw1000Painter extends CustomPainter {
  _Aw1000Painter(this.lights);

  final RouterLights lights;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(50, 123.4), width: 70, height: 4.4),
      Paint()
        ..color = _ink.withValues(alpha: 0.24)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.4),
    );
    final foot = Paint()..color = const Color(0xFFC3C7CC);
    for (final x in [22.0, 72.5]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 121, 5.5, 2),
          const Radius.circular(0.8),
        ),
        foot,
      );
    }

    final baseRect = _base.getBounds();
    canvas.drawPath(
      _base,
      _linear(
        baseRect,
        const [
          Color(0xFFCFD2D6),
          Color(0xFFE2E4E7),
          Color(0xFFE5E7EA),
          Color(0xFFD3D6DA),
          Color(0xFFC6CACF),
        ],
        const [0, .12, .6, .92, 1],
      ),
    );
    canvas.drawPath(
      _base,
      _linear(
        baseRect,
        [
          _ink.withValues(alpha: 0),
          _ink.withValues(alpha: .02),
          _ink.withValues(alpha: .16),
        ],
        const [0, .45, 1],
        down: true,
      ),
    );
    canvas.save();
    canvas.clipPath(_base);
    final slot = Paint()
      ..color = const Color(0xFF6D737B).withValues(alpha: 0.8);
    for (var i = 0; i < 30; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(20.6 + i * 1.98, 116.3, 0.95, 8),
          const Radius.circular(0.47),
        ),
        slot,
      );
    }
    canvas.restore();
    canvas.drawLine(
      const Offset(17, 111.3),
      const Offset(83, 111.3),
      Paint()
        ..color = _ink.withValues(alpha: .22)
        ..strokeWidth = .6,
    );
    canvas.drawLine(
      const Offset(17.2, 112),
      const Offset(82.8, 112),
      Paint()
        ..color = KeystoneColors.paper.withValues(alpha: .6)
        ..strokeWidth = .5,
    );

    final bodyRect = _body.getBounds();
    canvas.drawPath(
      _body,
      _linear(
        bodyRect,
        const [
          Color(0xFFECEEEF),
          Color(0xFFFAFAFA),
          Color(0xFFF8F8F7),
          Color(0xFFF2F3F2),
          Color(0xFFE5E6E7),
          Color(0xFFCFD2D5),
        ],
        const [0, .04, .42, .62, .82, 1],
      ),
    );
    canvas.drawPath(
      _body,
      _linear(
        bodyRect,
        [
          KeystoneColors.paper.withValues(alpha: .5),
          KeystoneColors.paper.withValues(alpha: 0),
          _ink.withValues(alpha: 0),
          _ink.withValues(alpha: .06),
        ],
        const [0, .12, .9, 1],
        down: true,
      ),
    );
    canvas.drawPath(
      _body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .6
        ..color = _ink.withValues(alpha: .09),
    );
    canvas.drawLine(
      const Offset(81, 13),
      const Offset(82.6, 107),
      Paint()
        ..color = _ink.withValues(alpha: .06)
        ..strokeWidth = 1.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .6),
    );

    final labelStyle = GoogleFonts.onest(
      fontSize: 2.05,
      fontWeight: FontWeight.w600,
      letterSpacing: .12,
      color: const Color(0xFF8E949C),
      height: 1,
    );
    for (var i = 0; i < 6; i++) {
      final y = 51.0 + i * 4.3;
      final state = lights.slots[i];
      final c = _led(state);
      if (state != LightColor.off) {
        canvas.drawCircle(
          Offset(49.4, y),
          2,
          Paint()..color = c.withValues(alpha: .4),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(49.4, y), width: 1.7, height: 1.7),
          const Radius.circular(.55),
        ),
        Paint()..color = c,
      );
      final tp = TextPainter(
        text: TextSpan(text: _labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(52.2, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_Aw1000Painter old) => old.lights != lights;
}
