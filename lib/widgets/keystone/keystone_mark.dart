import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

class KeystoneMark extends StatelessWidget {
  const KeystoneMark({
    super.key,
    this.width = 30,
    this.settle = 1,
    this.keyDrop = 1,
    this.shine = -1,
    this.stoneColor,
  });

  final double width;
  final double settle;
  final double keyDrop;
  final double shine;
  final Color? stoneColor;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Semantics(
      label: 'Keystone',
      image: true,
      child: CustomPaint(
        size: Size(width, width * 24 / 40),
        painter: _MarkPainter(
          stone: stoneColor ?? ks.tx.withValues(alpha: 0.55),
          key: ks.ac,
          settle: settle,
          keyDrop: keyDrop,
          shine: shine,
        ),
      ),
    );
  }
}

Path _stones(int i) {
  final p = Path();
  switch (i) {
    case 0:
      p
        ..moveTo(3, 23)
        ..arcToPoint(const Offset(6.6, 12.6), radius: const Radius.circular(17))
        ..lineTo(11, 16)
        ..arcToPoint(
          const Offset(9, 23),
          radius: const Radius.circular(11),
          clockwise: false,
        );
    case 1:
      p
        ..moveTo(8, 11)
        ..lineTo(12.2, 14.7)
        ..arcToPoint(
          const Offset(16.5, 12.6),
          radius: const Radius.circular(11),
        )
        ..lineTo(15, 7.2)
        ..arcToPoint(
          const Offset(8, 11),
          radius: const Radius.circular(17),
          clockwise: false,
        );
    case 2:
      p
        ..moveTo(32, 11)
        ..lineTo(27.8, 14.7)
        ..arcToPoint(
          const Offset(23.5, 12.6),
          radius: const Radius.circular(11),
          clockwise: false,
        )
        ..lineTo(25, 7.2)
        ..arcToPoint(const Offset(32, 11), radius: const Radius.circular(17));
    default:
      p
        ..moveTo(37, 23)
        ..arcToPoint(
          const Offset(33.4, 12.6),
          radius: const Radius.circular(17),
          clockwise: false,
        )
        ..lineTo(29, 16)
        ..arcToPoint(const Offset(31, 23), radius: const Radius.circular(11));
  }
  return p..close();
}

Path _keystone() => Path()
  ..moveTo(16.2, 4.2)
  ..lineTo(23.8, 4.2)
  ..lineTo(22.6, 12)
  ..arcToPoint(
    const Offset(17.4, 12),
    radius: const Radius.circular(11),
    clockwise: false,
  )
  ..close();

class _MarkPainter extends CustomPainter {
  _MarkPainter({
    required this.stone,
    required this.key,
    required this.settle,
    required this.keyDrop,
    required this.shine,
  });

  final Color stone, key;
  final double settle, keyDrop, shine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 40);
    final all = Path();
    for (var i = 0; i < 4; i++) {
      final t = ((settle - i * 0.08) / 0.76).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final p = _stones(i).shift(Offset(0, (1 - t) * 6));
      canvas.drawPath(p, Paint()..color = stone.withValues(alpha: stone.a * t));
      all.addPath(p, Offset.zero);
    }
    final k = keyDrop.clamp(0.0, 1.0);
    if (k > 0) {
      final p = _keystone().shift(Offset(0, -(1 - k) * 18));
      canvas.drawPath(p, Paint()..color = key.withValues(alpha: k));
      all.addPath(p, Offset.zero);
    }
    if (shine >= 0 && shine <= 1) {
      final x = -22 + shine * 76;
      canvas.save();
      canvas.clipPath(all);
      canvas.transform(Matrix4.skewX(-math.pi / 9).storage);
      final band = Rect.fromLTWH(x, -4, 18, 32);
      canvas.drawRect(
        band,
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_MarkPainter o) =>
      o.settle != settle ||
      o.keyDrop != keyDrop ||
      o.shine != shine ||
      o.stone != stone ||
      o.key != key;
}
