import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/widgets/keystone/aw1000_drawing.dart';

class RouterDrawing extends StatelessWidget {
  const RouterDrawing({
    super.key,
    this.model,
    this.lights = RouterLights.unlit,
    this.width = 100,
  });

  final String? model;
  final RouterLights lights;
  final double width;

  bool get isAw1000 => model?.toUpperCase().contains('AW1000') ?? false;

  String get _label {
    if (!isAw1000) return 'Router';
    final parts = [
      for (var i = 0; i < 6; i++)
        '${RouterLights.names[i]} ${lights.slots[i].name}',
    ];
    return 'AW1000. Lights: ${parts.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _label,
      image: true,
      child: ExcludeSemantics(
        child: isAw1000
            ? Aw1000Drawing(lights: lights, width: width)
            : CustomPaint(
                size: Size(width, width * 1.32),
                painter: _GenericPainter(context.ks),
              ),
      ),
    );
  }
}

class _GenericPainter extends CustomPainter {
  _GenericPainter(this.ks);

  final KeystoneColors ks;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTRB(20, 6, 80, 118),
      const Radius.circular(8),
    );
    canvas.drawRRect(body, Paint()..color = ks.node);
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = ks.mu.withValues(alpha: .45),
    );
    final dot = Paint()..color = ks.mu.withValues(alpha: .45);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(Offset(44, 48 + i * 7.0), 1.6, dot);
    }
  }

  @override
  bool shouldRepaint(_GenericPainter old) => old.ks != ks;
}
