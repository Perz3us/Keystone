// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';
import 'package:yet_another_luci_app/screens/home/home_signal.dart';
import 'package:yet_another_luci_app/widgets/keystone/router_drawing.dart';

class FlowDevice {
  const FlowDevice({
    required this.name,
    required this.icon,
    required this.line,
    required this.mbps,
    this.onTap,
  });
  final String name;
  final IconData icon;

  final String line;
  final double mbps;
  final VoidCallback? onTap;

  bool get active => mbps >= FlowMotion.minRate;
}

class FlowMotion {
  static const gap = 14.0;
  static const minRate = 0.05;
  static const maxSpeed = 140.0;
  static const _fade = 2.5;

  final _rate = <String, double>{};
  final _phase = <String, double>{};

  static double speed(double mbps) =>
      math.min(maxSpeed, 18 + 14 * math.log(1 + mbps) / math.ln2);

  double rate(String line) => _rate[line] ?? 0;
  double phase(String line) => _phase[line] ?? gap / 2;
  bool get busy => _rate.isNotEmpty;

  void step(Map<String, double> target, double dt) {
    final decay = math.exp(-dt / _fade);
    for (final k in {...target.keys, ..._rate.keys}) {
      final r = math.max(target[k] ?? 0, rate(k) * decay);
      if (r < minRate) {
        _rate.remove(k);
        _phase.remove(k);
        continue;
      }
      _rate[k] = r;
      _phase[k] = (phase(k) + dt * speed(r)) % gap;
    }
  }
}

List<Client> pickFlowDevices(List<Client> online, HomePrefs p) {
  final busiest = [...online]
    ..sort((a, b) {
      final c = deviceMbps(b).compareTo(deviceMbps(a));
      return c != 0 ? c : a.displayName.compareTo(b.displayName);
    });
  final out = <Client>[];
  if (p.pick == HomePick.pinned) {
    for (final mac in p.pinned) {
      final c = online
          .where((c) => c.macAddress.toLowerCase() == mac)
          .firstOrNull;
      if (c != null) out.add(c);
    }
  }
  for (final c in busiest) {
    if (out.length >= p.deviceCount) break;
    if (!out.contains(c)) out.add(c);
  }
  return out.take(p.deviceCount).toList();
}

class HomeFlow extends StatefulWidget {
  const HomeFlow({
    super.key,
    required this.layout,
    required this.flow,
    required this.devices,
    required this.more,
    required this.internetLine,
    required this.internetMbps,
    required this.lights,
    this.model,
    this.problem,
    this.unknown = false,
    this.unreachable = false,
    this.internetIcon = Icons.public_rounded,
    this.onInternet,
    this.onRouter,
    this.onMore,
    this.internetBars,
    this.barsColor,
    this.beside,
  });

  final HomeLayout layout;
  final bool flow;
  final List<FlowDevice> devices;

  final int more;
  final String internetLine;
  final double internetMbps;
  final RouterLights lights;
  final String? model;

  final Color? problem;

  final bool unknown;

  final bool unreachable;
  final IconData internetIcon;
  final VoidCallback? onInternet;
  final VoidCallback? onRouter;
  final VoidCallback? onMore;

  final int? internetBars;
  final Color? barsColor;

  final Widget? beside;

  @override
  State<HomeFlow> createState() => _HomeFlowState();
}

class _HomeFlowState extends State<HomeFlow>
    with SingleTickerProviderStateMixin {
  static const _router = 80.0;
  static const _tile = 44.0;
  static const _nodeH = 92.0;

  static const _net = ':internet';
  final _motion = FlowMotion();
  Duration _last = Duration.zero;
  late final Ticker _ticker = createTicker((e) {
    final dt = math.min((e - _last).inMicroseconds / 1e6, .1);
    _last = e;
    _motion.step(_targets, dt);
    _seconds.value = e.inMicroseconds / 1e6;
    if (!_moving) _ticker.stop();
  });
  final _seconds = ValueNotifier<double>(0);

  Map<String, double> get _targets => {
    _net: widget.problem == null && !widget.unknown ? widget.internetMbps : 0,
    for (final d in widget.devices) d.name: d.mbps,
  };

  bool get _moving =>
      widget.flow &&
      !widget.unreachable &&
      !MediaQuery.of(context).disableAnimations &&
      (_motion.busy || _targets.values.any((r) => r >= FlowMotion.minRate));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didUpdateWidget(HomeFlow old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (_moving && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    if (!_moving && _ticker.isActive) _ticker.stop();
  }

  (double, double) _dots(String line) => _ticker.isActive
      ? (_motion.rate(line), _motion.phase(line))
      : (_targets[line] ?? 0, FlowMotion.gap / 2);

  @override
  void dispose() {
    _ticker.dispose();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final top = widget.layout == HomeLayout.topDown;
    const routerH = _router * 1.32;
    final routerTop = top ? 84.0 : 12.0;
    final routerFoot = routerTop + _router * 1.2;
    final devicesY = routerTop + routerH + 80;
    final devices = widget.unreachable ? const <FlowDevice>[] : widget.devices;
    final height =
        devicesY + (devices.isEmpty ? 34 : _nodeH + (widget.more > 0 ? 34 : 0));

    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final cx = w / 2;
        final n = math.max(devices.length, 1);
        final colW = w / math.max(n, 3);
        final left = cx - colW * devices.length / 2;
        final xs = [
          for (var i = 0; i < devices.length; i++) left + colW * (i + .5),
        ];

        final internetY = top ? 22.0 : routerTop + 34;
        final internetX = top ? cx : math.min(colW / 2, cx - 96);
        final netPath = top
            ? (Path()
                ..moveTo(cx, 46)
                ..lineTo(cx, routerTop + 8))
            : (Path()
                ..moveTo(internetX + _tile / 2 + 6, internetY)
                ..lineTo(cx - _router * .28, internetY));

        const base = _router * .46;
        final wires = [
          for (var i = 0; i < devices.length; i++)
            () {
              final sx = devices.length == 1
                  ? cx
                  : cx - base / 2 + base * i / (devices.length - 1);
              final sy = routerFoot - 8;
              return Path()
                ..moveTo(sx, sy)
                ..cubicTo(sx, sy + 64, xs[i], devicesY - 56, xs[i], devicesY);
            }(),
        ];

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _seconds,
                  builder: (_, _, _) => CustomPaint(
                    painter: _FlowPainter(
                      net: netPath,
                      netDots: _dots(_net),
                      netColor:
                          widget.problem ??
                          (widget.unknown || widget.unreachable
                              ? ks.line
                              : _mix(ks)),
                      netDashed: widget.unknown || widget.unreachable,
                      wires: wires,
                      dots: [for (final d in devices) _dots(d.name)],
                      on: _mix(ks),
                      off: ks.line,
                      dot: ks.ac,
                      shadow: Theme.of(context).brightness == Brightness.dark
                          ? KeystoneColors.ink.withValues(alpha: .7)
                          : ks.tx.withValues(alpha: .16),
                      shadowAt: Offset(cx, routerFoot + 1),
                      shadowW: _router * 1.35,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: cx - _router / 2,
                top: routerTop,
                child: Semantics(
                  button: widget.onRouter != null,
                  label: 'Router',
                  child: GestureDetector(
                    onTap: widget.onRouter,
                    child: RouterDrawing(
                      model: widget.model,
                      lights: widget.lights,
                      width: _router,
                    ),
                  ),
                ),
              ),
              if (widget.beside != null && !widget.unreachable)
                Positioned(
                  left: cx + _router * .36 + 12,
                  right: 0,
                  top: routerTop,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: widget.beside,
                  ),
                ),
              if (top)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Center(child: _internetPill(ks)),
                )
              else
                Positioned(
                  left: internetX - 48,
                  top: internetY - _tile / 2,
                  width: 96,
                  child: _node(
                    ks,
                    icon: widget.internetIcon,
                    name: 'Internet',
                    line: widget.internetLine,
                    lineColor: _lineColor(ks),
                    bars: widget.internetBars,
                    round: true,
                    alert: widget.problem,
                    onTap: widget.onInternet,
                  ),
                ),
              for (var i = 0; i < devices.length; i++)
                Positioned(
                  left: xs[i] - colW / 2,
                  top: devicesY,
                  width: colW,
                  child: _node(
                    ks,
                    icon: devices[i].icon,
                    name: devices[i].name,
                    line: devices[i].line,
                    lineColor: devices[i].active ? ks.ac : ks.mu,
                    onTap: devices[i].onTap,
                  ),
                ),
              if (devices.isEmpty && widget.more == 0 && !widget.unreachable)
                Positioned(
                  left: 0,
                  right: 0,
                  top: devicesY,
                  child: Text(
                    'No devices connected yet',
                    textAlign: TextAlign.center,
                    style: KeystoneType.secondary(ks.mu),
                  ),
                ),
              if (widget.more > 0 && !widget.unreachable)
                Positioned(
                  left: 0,
                  right: 0,
                  top: devices.isEmpty ? devicesY - 6 : devicesY + _nodeH,
                  child: Center(
                    child: TextButton(
                      onPressed: widget.onMore,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 32),
                      ),
                      child: Text(
                        devices.isEmpty
                            ? '${widget.more} device${widget.more == 1 ? '' : 's'} connected ›'
                            : '${widget.more} more device${widget.more == 1 ? '' : 's'} ›',
                        style: KeystoneType.secondary(ks.ac),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static Color _mix(KeystoneColors ks) => Color.lerp(ks.line, ks.ac, .45)!;

  Color _lineColor(KeystoneColors ks) =>
      widget.barsColor ?? widget.problem ?? ks.ac;

  Widget _line(String line, Color color, int? bars) {
    final text = Text(
      line,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: KeystoneType.caption(color),
    );
    if (bars == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SignalBars(bars, color: color),
        const SizedBox(width: 5),
        Flexible(child: text),
      ],
    );
  }

  Widget _internetPill(KeystoneColors ks) => Semantics(
    button: widget.onInternet != null,
    child: InkWell(
      onTap: widget.onInternet,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 46,
        padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
        decoration: BoxDecoration(
          color: ks.node,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: widget.problem ?? ks.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.internetIcon,
              size: 20,
              color: widget.problem ?? ks.tx2,
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Internet',
                  style: KeystoneType.bodyStrong(ks.tx).copyWith(fontSize: 14),
                ),
                _line(widget.internetLine, _lineColor(ks), widget.internetBars),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _node(
    KeystoneColors ks, {
    required IconData icon,
    required String name,
    required String line,
    required Color lineColor,
    bool round = false,
    Color? alert,
    int? bars,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Container(
            width: _tile,
            height: _tile,
            decoration: BoxDecoration(
              color: alert == null ? ks.node : Color.lerp(ks.bg, alert, .22),
              borderRadius: BorderRadius.circular(round ? _tile : 13),
              border: Border.all(color: alert ?? ks.line),
            ),
            child: Icon(icon, size: 21, color: alert ?? ks.tx2),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: KeystoneType.bodyStrong(ks.tx).copyWith(fontSize: 13),
          ),
          _line(line, lineColor, bars),
        ],
      ),
    ),
  );
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.net,
    required this.netDots,
    required this.netColor,
    required this.netDashed,
    required this.wires,
    required this.dots,
    required this.on,
    required this.off,
    required this.dot,
    required this.shadow,
    required this.shadowAt,
    required this.shadowW,
  });

  final Path net;
  final (double, double) netDots;
  final Color netColor;
  final bool netDashed;
  final List<Path> wires;

  final List<(double, double)> dots;
  final Color on;
  final Color off;
  final Color dot;
  final Color shadow;
  final Offset shadowAt;
  final double shadowW;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Rect.fromCenter(center: shadowAt, width: shadowW, height: 9),
      Paint()
        ..color = shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final dotPaint = Paint()..color = dot;

    void wire(Path p, Color c, (double, double) at, {bool dashed = false}) {
      final (rate, phase) = at;
      for (final m in p.computeMetrics()) {
        if (dashed) {
          for (var d = 0.0; d < m.length; d += 9) {
            canvas.drawPath(
              m.extractPath(d, math.min(d + 4.5, m.length)),
              line..color = c,
            );
          }
          continue;
        }
        canvas.drawPath(p, line..color = c);
        if (rate < FlowMotion.minRate) continue;
        for (var d = phase; d < m.length; d += FlowMotion.gap) {
          final pos = m.getTangentForOffset(d)?.position;
          if (pos != null) canvas.drawCircle(pos, 1.6, dotPaint);
        }
      }
    }

    wire(net, netColor, netDots, dashed: netDashed);
    for (var i = 0; i < wires.length; i++) {
      final active = dots[i].$1 >= FlowMotion.minRate;
      wire(wires[i], active ? on : off, dots[i]);
    }
  }

  @override
  bool shouldRepaint(_FlowPainter o) =>
      o.netDots != netDots ||
      o.netColor != netColor ||
      o.netDashed != netDashed ||
      o.wires.length != wires.length ||
      o.dots.toString() != dots.toString() ||
      o.on != on ||
      o.dot != dot ||
      o.shadowAt != shadowAt;
}
