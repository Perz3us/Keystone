import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class SpeedChart extends StatelessWidget {
  const SpeedChart({
    super.key,
    required this.down,
    this.up = const [],
    this.max,
  });

  final List<double> down;
  final List<double> up;

  final double? max;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return SizedBox.expand(
      child: CustomPaint(
        painter: _SpeedPainter(
          down: down,
          up: up,
          downColor: ks.ac,
          upColor: ks.mu,
          grid: ks.line,
          max: max,
        ),
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter({
    required this.down,
    required this.up,
    required this.downColor,
    required this.upColor,
    required this.grid,
    this.max,
  });

  final double? max;

  final List<double> down;
  final List<double> up;
  final Color downColor;
  final Color upColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = grid,
    );
    final top = max ?? [...down, ...up].fold<double>(0, math.max);
    if (top <= 0) return;

    Path line(List<double> v) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        final x = v.length == 1 ? 0.0 : size.width * i / (v.length - 1);
        final y =
            size.height - 2 - (size.height - 6) * (v[i] / top).clamp(0.0, 1.0);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    if (down.length > 1) canvas.drawPath(line(down), paint..color = downColor);
    if (up.length > 1) {
      for (final m in line(up).computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 6) {
          canvas.drawPath(
            m.extractPath(d, math.min(d + 2, m.length)),
            paint
              ..color = upColor
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_SpeedPainter o) =>
      o.down != down || o.up != up || o.downColor != downColor;
}
