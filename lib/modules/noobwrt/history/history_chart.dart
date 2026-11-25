// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';

import 'history_data.dart';

const _maxGap = Duration(minutes: 10);

typedef HistoryLine = ({
  double? Function(HistoryPoint) value,
  double lo,
  double hi,
  Color color,
  double width,
});

typedef HistoryBand = ({double lo, double hi, Color color, String label});

Duration historyGap(List<HistoryPoint> p) {
  if (p.length < 3) return _maxGap;
  final steps = [
    for (var i = 1; i < p.length; i++) p[i].t.difference(p[i - 1].t),
  ]..sort();
  final median = steps[(steps.length - 1) ~/ 2] * 3;
  return median > _maxGap ? median : _maxGap;
}

List<List<HistoryPoint>> historyRuns(
  List<HistoryPoint> p,
  double? Function(HistoryPoint) value,
) {
  final has = [
    for (final e in p)
      if (value(e)?.isFinite ?? false) e,
  ];
  final gap = historyGap(has);
  final out = <List<HistoryPoint>>[];
  for (final e in has) {
    if (out.isEmpty || e.t.difference(out.last.last.t) > gap) out.add([]);
    out.last.add(e);
  }
  return out;
}

class HistoryChart extends CustomPainter {
  HistoryChart({
    required this.points,
    required this.from,
    required this.to,
    required this.line,
    required this.slowColor,
    required this.grid,
    required this.labelStyle,
    this.bands = const [],
    this.slow = const [],
    this.ticks = false,
    this.top,
    this.bottom,
    this.pick,
  });

  final List<HistoryPoint> points;
  final DateTime from, to;
  final HistoryLine line;
  final List<HistoryBand> bands;
  final List<(DateTime, DateTime)> slow;
  final Color slowColor, grid;
  final TextStyle labelStyle;
  final bool ticks;
  final String? top, bottom;
  final DateTime? pick;

  double x(DateTime t, double w) {
    final span = to.difference(from).inMilliseconds;
    if (span <= 0) return w;
    return w * (t.difference(from).inMilliseconds / span).clamp(0.0, 1.0);
  }

  TextPainter _text(String s, double max) => TextPainter(
    text: TextSpan(text: s, style: labelStyle),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: max);

  double plotWidth(double full) {
    var widest = 0.0;
    for (final b in bands) {
      final tp = _text(b.label, full);
      if (tp.width > widest) widest = tp.width;
      tp.dispose();
    }
    if (widest == 0) return full;
    return full - widest - 8 > 0 ? full - widest - 8 : 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final full = size.width, h = size.height;
    final w = plotWidth(full);
    final range = line.hi - line.lo;
    double y(double v) =>
        h - 3 - (h - 6) * ((v - line.lo) / range).clamp(0.0, 1.0);
    TextPainter text(String s) => _text(s, full);
    for (final b in bands) {
      final top = b.hi >= line.hi ? 0.0 : y(b.hi);
      final bottom = b.lo <= line.lo ? h : y(b.lo);
      canvas.drawRect(
        Rect.fromLTRB(0, top, w, bottom),
        Paint()..color = b.color,
      );
      final tp = text(b.label);
      if (tp.height <= bottom - top) {
        tp.paint(canvas, Offset(w + 6, (top + bottom - tp.height) / 2));
      }
      tp.dispose();
    }
    final shade = Paint()..color = slowColor.withValues(alpha: .16);
    for (final (a, b) in slow) {
      final l = x(a, w), r = x(b, w);
      canvas.drawRect(Rect.fromLTRB(l, 0, r < l + 2 ? l + 2 : r, h), shade);
    }
    final rule = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, h - .5), Offset(w, h - .5), rule);
    if (ticks) {
      for (var i = 1; i < points.length; i++) {
        final a = points[i - 1], b = points[i];
        if (a.pci == null || b.pci == null) continue;
        if (a.pci == b.pci && a.earfcn == b.earfcn) continue;
        final tx = x(b.t, w);
        canvas.drawLine(Offset(tx, 0), Offset(tx, h), rule);
      }
    }
    if (pick != null) {
      final px = x(pick!, w);
      canvas.drawLine(Offset(px, 0), Offset(px, h), rule..strokeWidth = 1.5);
    }
    final paint = Paint()
      ..color = line.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = line.width
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final run in historyRuns(points, line.value)) {
      Offset at(HistoryPoint p) => Offset(x(p.t, w), y(line.value(p)!));
      if (run.length == 1) {
        canvas.drawCircle(
          at(run.first),
          line.width + 1,
          Paint()..color = line.color,
        );
        continue;
      }
      final path = Path()..moveTo(at(run.first).dx, at(run.first).dy);
      for (final p in run.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, paint);
    }
    void label(String? s, bool atTop) {
      if (s == null) return;
      final tp = text(s);
      tp.paint(canvas, Offset(2, atTop ? 0 : h - tp.height - 3));
      tp.dispose();
    }

    label(top, true);
    label(bottom, false);
  }

  @override
  bool shouldRepaint(HistoryChart o) =>
      o.points != points ||
      o.slow != slow ||
      o.pick != pick ||
      o.from != from ||
      o.grid != grid ||
      o.slowColor != slowColor ||
      o.line.color != line.color ||
      o.bands != bands;
}
