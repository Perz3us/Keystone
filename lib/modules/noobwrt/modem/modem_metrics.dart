// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';

import '../noob_rpc.dart';

enum SignalQuality { excellent, good, fair, poor, unknown }

extension SignalQualityColor on SignalQuality {
  Color tone(KeystoneColors ks) => switch (this) {
    SignalQuality.excellent || SignalQuality.good => ks.okTx,
    SignalQuality.fair => ks.warnTx,
    SignalQuality.poor => ks.bad,
    SignalQuality.unknown => ks.mu,
  };
}

SignalQuality _grade(String? v, List<double> steps) {
  final n = double.tryParse(v ?? '');
  if (n == null) return SignalQuality.unknown;
  if (n >= steps[0]) return SignalQuality.excellent;
  if (n >= steps[1]) return SignalQuality.good;
  if (n >= steps[2]) return SignalQuality.fair;
  return SignalQuality.poor;
}

class ModemCarrier {
  final String label;
  final String band;
  final String? pci;
  final String? earfcn;
  const ModemCarrier(this.label, this.band, this.pci, this.earfcn);
}

class ModemMetrics {
  final Map<String, dynamic> raw;
  final int? age;
  const ModemMetrics(this.raw, {this.age});

  static const staleAfter = 180;

  bool get stale => (age ?? 0) > staleAfter;

  String? operator [](String k) => noobValue(raw[k]);

  String? get temperature => this['mtemp']?.replaceAll('&deg;', '°');

  SignalQuality get rsrpQuality => _grade(this['rsrp'], [-80, -90, -100]);
  SignalQuality get rsrqQuality => _grade(this['rsrq'], [-10, -15, -20]);
  SignalQuality get sinrQuality => _grade(this['sinr'], [20, 13, 0]);

  int? get signalPercent => int.tryParse(this['signal'] ?? '');

  bool get connected => !stale && this['ipaddr'] != null;

  List<ModemCarrier> get carriers => [
    if (this['pband'] != null)
      ModemCarrier('Primary', this['pband']!, this['pci'], this['earfcn']),
    for (var i = 1; i <= 4; i++)
      if (this['s${i}band'] != null)
        ModemCarrier(
          'Secondary $i',
          this['s${i}band']!,
          this['s${i}pci'],
          this['s${i}earfcn'],
        ),
  ];
}
