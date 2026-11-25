import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/speed/speed_test.dart';
import 'package:yet_another_luci_app/widgets/keystone/speed_chart.dart';

class SpeedView extends StatelessWidget {
  const SpeedView({
    super.key,
    required this.progress,
    required this.available,
    required this.history,
    required this.onStart,
    required this.onCancel,
    this.mobileData = false,
  });

  final SpeedTestProgress? progress;
  final bool available;
  final List<SpeedResult> history;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  final bool mobileData;

  static String _n(double? v) => v == null
      ? '—'
      : v >= 100
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1);

  static String _ms(double? v) => v == null ? '—' : '${v.round()} ms';

  static String _phase(SpeedPhase p) => switch (p) {
    SpeedPhase.starting => 'Finding a server',
    SpeedPhase.ping => 'Checking ping',
    SpeedPhase.download => 'Testing download',
    SpeedPhase.upload => 'Testing upload',
    SpeedPhase.done => 'Download',
    SpeedPhase.failed => '',
  };

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final p = progress;
    final running = p != null && p.running;
    final done = p?.phase == SpeedPhase.done;
    final failed = p?.phase == SpeedPhase.failed;
    final measuring =
        running &&
        (p.phase == SpeedPhase.download || p.phase == SpeedPhase.upload);
    final gaugeMbps = measuring ? p.liveMbps : (done ? p!.downMbps ?? 0 : 0.0);
    final upColor = ks.ok;
    final phase = p?.phase;
    final downStarted =
        phase == SpeedPhase.download || phase == SpeedPhase.upload || done;
    final upStarted = phase == SpeedPhase.upload || done;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text('Speed test', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Text(
          "Run from your router, so it measures your internet, not this "
          "phone's Wi-Fi.",
          style: KeystoneType.secondary(ks.mu),
        ),
        if (!available)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              "This router doesn't have a speed test installed.",
              style: KeystoneType.body(ks.mu),
            ),
          )
        else ...[
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 280,
              height: 232,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: _Glide(
                      value: gaugeMbps,
                      builder: (v) => _Glide(
                        value: running ? p.progress : 0,
                        builder: (pp) => CustomPaint(
                          painter: _Gauge(
                            fill: _scale(v),
                            phaseProgress: pp,
                            track: ks.line,
                            label: ks.mu,
                            color: phase == SpeedPhase.upload ? upColor : ks.ac,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (failed)
                          Icon(
                            Icons.error_outline_rounded,
                            color: ks.bad,
                            size: 40,
                          )
                        else ...[
                          _Glide(
                            value: gaugeMbps,
                            builder: (v) => FittedBox(
                              child: Text(
                                measuring || done ? _n(v) : '—',
                                style: KeystoneType.headline(ks.tx).copyWith(
                                  fontSize: 52,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Text('Mbps', style: KeystoneType.secondary(ks.mu)),
                          const SizedBox(height: 6),
                          if (p != null)
                            Text(
                              _phase(p.phase),
                              style: KeystoneType.caption(
                                running ? ks.ac : ks.mu,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (failed) ...[
            Text(
              "The test didn't finish.",
              textAlign: TextAlign.center,
              style: KeystoneType.bodyStrong(ks.tx),
            ),
            if (p?.error case final error?)
              Text(
                error,
                textAlign: TextAlign.center,
                style: KeystoneType.caption(ks.mu),
              ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tile(
                  ks,
                  icon: Icons.arrow_downward_rounded,
                  label: 'Download',
                  mbps: downStarted ? p?.downMbps : null,
                  value: '—',
                  unit: 'Mbps',
                  tint: ks.ac,
                  active: phase == SpeedPhase.download,
                ),
                const SizedBox(width: 8),
                _tile(
                  ks,
                  icon: Icons.arrow_upward_rounded,
                  label: 'Upload',
                  mbps: upStarted ? p?.upMbps : null,
                  value: '—',
                  unit: 'Mbps',
                  tint: upColor,
                  active: phase == SpeedPhase.upload,
                ),
                const SizedBox(width: 8),
                _tile(
                  ks,
                  icon: Icons.timer_outlined,
                  label: 'Ping',
                  value: _ms(p?.pingMs),
                  unit: p?.jitterMs == null
                      ? ''
                      : 'Jitter ${p!.jitterMs!.round()} ms',
                  tint: ks.tx2,
                  active: phase == SpeedPhase.ping,
                ),
              ],
            ),
          ),
          if (p != null && (p.downSamples.isNotEmpty)) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: SpeedChart(down: p.downSamples, up: p.upSamples),
            ),
          ],
          if (p != null && !failed) ..._details(ks, p),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: running ? onCancel : onStart,
            style: FilledButton.styleFrom(
              backgroundColor: running ? ks.tint : ks.tx,
              foregroundColor: running ? ks.tx : ks.bg,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              running
                  ? 'Cancel'
                  : failed
                  ? 'Try again'
                  : done
                  ? 'Test again'
                  : 'Start test',
              style: KeystoneType.bodyStrong(running ? ks.tx : ks.bg),
            ),
          ),
          if (mobileData) ...[
            const SizedBox(height: 10),
            Text(
              'A test uses a few hundred MB of mobile data.',
              textAlign: TextAlign.center,
              style: KeystoneType.caption(ks.warnTx),
            ),
          ],
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Earlier tests', style: KeystoneType.secondary(ks.mu)),
          const SizedBox(height: 4),
          for (final r in history)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ks.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_n(r.downMbps)} down · ${_n(r.upMbps)} up'
                          '${r.pingMs == null ? '' : ' · ${r.pingMs!.round()} ms'}',
                          style: KeystoneType.body(ks.tx),
                        ),
                        if (r.server case final s?)
                          Text(s, style: KeystoneType.caption(ks.mu)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_when(r.at), style: KeystoneType.caption(ks.mu)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  List<Widget> _details(KeystoneColors ks, SpeedTestProgress p) {
    final rows = <(String, String)>[
      if (p.server case final s? when s.isNotEmpty) ('Server', s),
      if (p.isp case final s? when s.isNotEmpty) ('Provider', s),
      if (p.externalIp case final s? when s.isNotEmpty) ('Your IP', s),
      if (p.downLoadedPingMs != null || p.upLoadedPingMs != null)
        (
          'Ping when busy',
          [
            if (p.downLoadedPingMs != null) '${_ms(p.downLoadedPingMs)} down',
            if (p.upLoadedPingMs != null) '${_ms(p.upLoadedPingMs)} up',
          ].join(' · '),
        ),
      if (p.packetLoss case final l?)
        (
          'Packet loss',
          '${l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1)}%',
        ),
    ];
    if (rows.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: ks.node,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ks.line),
        ),
        child: Column(
          children: [
            for (final (i, (label, value)) in rows.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: ks.line)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: KeystoneType.secondary(ks.mu)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        value,
                        textAlign: TextAlign.end,
                        style: KeystoneType.secondary(ks.tx),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  static double _scale(double mbps) =>
      (math.log(1 + mbps) / math.log(1001)).clamp(0.0, 1.0);

  static String _when(DateTime t) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.day} ${months[t.month - 1]} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _tile(
    KeystoneColors ks, {
    required IconData icon,
    required String label,
    required String value,
    double? mbps,
    required String unit,
    required Color tint,
    required bool active,
  }) => Expanded(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: active ? ks.acSoft : ks.node,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? tint : ks.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tint),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: KeystoneType.caption(ks.mu),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _Glide(
            value: mbps ?? 0,
            builder: (v) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                mbps == null ? value : _n(v),
                style: KeystoneType.sheetTitle(
                  ks.tx,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ),
          if (unit.isNotEmpty) Text(unit, style: KeystoneType.caption(ks.mu)),
        ],
      ),
    ),
  );
}

class _Glide extends StatelessWidget {
  const _Glide({required this.value, required this.builder});
  final double value;
  final Widget Function(double) builder;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value),
    duration: MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 900),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => builder(v),
  );
}

class _Gauge extends CustomPainter {
  _Gauge({
    required this.fill,
    required this.phaseProgress,
    required this.track,
    required this.label,
    required this.color,
  });

  final double fill;
  final double phaseProgress;
  final Color track;
  final Color label;
  final Color color;

  static const _start = math.pi * 5 / 6;
  static const _sweep = math.pi * 4 / 3;
  static const _marks = [0, 10, 100, 1000];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height * 1.1) / 2 - 14;
    final c = Offset(size.width / 2, size.height / 2 + 14);
    final rect = Rect.fromCircle(center: c, radius: r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12;
    canvas.drawArc(rect, _start, _sweep, false, p..color = track);
    if (fill > 0) {
      canvas.drawArc(rect, _start, _sweep * fill, false, p..color = color);
    }
    if (phaseProgress > 0) {
      canvas.drawArc(
        rect.deflate(18),
        _start,
        _sweep * phaseProgress.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..color = color.withValues(alpha: 0.5),
      );
    }
    for (final m in _marks) {
      final a =
          _start + _sweep * (math.log(1 + m) / math.log(1001)).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: '$m',
          style: TextStyle(color: label, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final at = c + Offset(math.cos(a), math.sin(a)) * (r - 30);
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_Gauge o) =>
      o.fill != fill ||
      o.phaseProgress != phaseProgress ||
      o.color != color ||
      o.track != track;
}
