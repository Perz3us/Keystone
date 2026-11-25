// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import 'modem_metrics.dart';

double alignPitch(double rsrp) =>
    300 + (rsrp.clamp(-120.0, -70.0) + 120) / 50 * 900;

const _channel = MethodChannel('com.perz3us.keystone/app_lifecycle');

void _defaultTone(double hz) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    _channel.invokeMethod('tone', {'hz': hz, 'ms': 150}).ignore();
  } else {
    HapticFeedback.selectionClick();
  }
}

class AlignScreen extends StatefulWidget {
  const AlignScreen({super.key, required this.read, this.tone});

  final Future<ModemMetrics> Function() read;
  final void Function(double hz)? tone;

  @override
  State<AlignScreen> createState() => _AlignScreenState();
}

class _AlignScreenState extends State<AlignScreen> with WidgetsBindingObserver {
  Timer? _timer;
  ModemMetrics? _m;
  double? _rsrp;
  double? _best;
  bool _tone = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_timer == null) _start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_busy) return;
    _busy = true;
    ModemMetrics? m;
    try {
      m = await widget.read().timeout(const Duration(seconds: 5));
    } catch (_) {}
    _busy = false;
    if (!mounted) return;
    final r = double.tryParse(m?['rsrp'] ?? '');
    setState(() {
      _m = m;
      _rsrp = r;
      if (r != null && (_best == null || r > _best!)) _best = r;
    });
    if (r != null && _tone) (widget.tone ?? _defaultTone)(alignPitch(r));
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final m = _m;
    return KsPage(
      title: 'Aim the antenna',
      subtitle: 'Turn it slowly. A higher pitch means a better signal.',
      children: [
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              m?['rsrp'] != null && _rsrp != null ? m!['rsrp']! : '–',
              style: KeystoneType.bodyStrong(
                m?.rsrpQuality.tone(ks) ?? ks.mu,
              ).copyWith(fontSize: 72, height: 1),
            ),
            const SizedBox(width: 8),
            Text('dBm', style: KeystoneType.body(ks.mu)),
          ],
        ),
        const SizedBox(height: 16),
        _row('SINR (dB)', m?['sinr']),
        _row('RSRQ (dB)', m?['rsrq']),
        KsRow(
          title: 'Best so far',
          subtitle: _best == null ? '–' : '${_fmt(_best!)} dBm',
          trailing: TextButton(
            onPressed: () => setState(() => _best = _rsrp),
            child: const Text('Reset'),
          ),
        ),
        KsSwitchRow(
          title: 'Tone',
          value: _tone,
          onChanged: (v) => setState(() => _tone = v),
        ),
      ],
    );
  }

  Widget _row(String title, String? v) => KsRow(
    title: title,
    trailing: Text(v ?? '–', style: KeystoneType.bodyStrong(context.ks.tx)),
  );

  String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
}
