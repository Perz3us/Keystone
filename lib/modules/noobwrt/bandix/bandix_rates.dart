// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/main.dart';

import '../noob_rpc.dart';
import '../noob_widgets.dart';

class BandixRate {
  final num down;
  final num up;
  final num usedDown;
  final num usedUp;
  const BandixRate(this.down, this.up, this.usedDown, this.usedUp);
}

final bandixRatesProvider = StreamProvider.autoDispose<Map<String, BandixRate>>(
  (ref) {
    final app = ref.read(appStateProvider);
    final out = StreamController<Map<String, BandixRate>>();
    Timer? timer;

    Future<void> poll() async {
      try {
        final r = await noobCall(app, 'luci.bandix', 'getStatus');
        final list = r['d'];
        if (out.isClosed) return;
        out.add({
          if (list is List)
            for (final d in list)
              if (d is Map && d['mac'] != null)
                d['mac'].toString().toLowerCase(): BandixRate(
                  (d['t_rx_r'] as num?) ?? 0,
                  (d['t_tx_r'] as num?) ?? 0,
                  (d['t_rx_b'] as num?) ?? 0,
                  (d['t_tx_b'] as num?) ?? 0,
                ),
        });
      } catch (_) {
        timer?.cancel();
        if (!out.isClosed) out.add(const {});
      }
    }

    poll();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => poll());
    ref.onDispose(() {
      timer?.cancel();
      out.close();
    });
    return out.stream;
  },
);

class BandixSpeed extends ConsumerWidget {
  final String mac;
  const BandixSpeed({super.key, required this.mac});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = ref.watch(bandixRatesProvider).valueOrNull?[mac.toLowerCase()];
    if (rate == null) return const SizedBox.shrink();
    final style = KeystoneType.caption(
      context.ks.mu,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('↓ ${noobBytes(rate.down)}/s', style: style),
        Text('↑ ${noobBytes(rate.up)}/s', style: style),
      ],
    );
  }
}
