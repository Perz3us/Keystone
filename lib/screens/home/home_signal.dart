// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/modem_metrics.dart';
import 'package:yet_another_luci_app/modules/noobwrt/modem/signal_overview.dart';
import 'package:yet_another_luci_app/screens/home/home_prefs.dart';

class SignalBars extends StatelessWidget {
  const SignalBars(this.bars, {super.key, required this.color});
  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$bars of 4 signal bars',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 3,
            height: 3.0 * i,
            margin: EdgeInsets.only(right: i == 4 ? 0 : 1.5),
            decoration: BoxDecoration(
              color: i <= bars ? color : context.ks.line,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    ),
  );
}

String _n(String v) => v.replaceFirst('-', '−');

String _word(SignalQuality q) => switch (q) {
  SignalQuality.excellent => 'Excellent',
  SignalQuality.good => 'Good',
  SignalQuality.fair => 'Fair',
  SignalQuality.poor => 'Weak',
  SignalQuality.unknown => '',
};

String? signalLine(SignalOverview s) => s.percent != null
    ? '${s.percent}%'
    : s.rsrp != null
    ? '${_n(s.rsrp!)} dBm'
    : null;

class SignalReadings extends StatelessWidget {
  const SignalReadings(
    this.signal, {
    super.key,
    required this.items,
    this.onTap,
  });

  final SignalOverview signal;
  final List<SignalItem> items;
  final VoidCallback? onTap;

  bool get isEmpty => _lines(KeystoneColors.light).isEmpty;

  List<Widget> _lines(KeystoneColors ks) {
    Widget? text(String? v, {bool strong = false}) => v == null
        ? null
        : Text(
            v,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: strong
                ? KeystoneType.bodyStrong(ks.tx).copyWith(fontSize: 14)
                : KeystoneType.caption(ks.mu),
          );
    Widget? reading(String name, String? v, SignalQuality q) => v == null
        ? null
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$name  ', style: KeystoneType.caption(ks.mu)),
                TextSpan(text: _n(v), style: KeystoneType.caption(q.tone(ks))),
              ],
            ),
            semanticsLabel: '$name $v ${_word(q)}'.trimRight(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
    return [
      for (final i in SignalItem.values)
        if (items.contains(i))
          ?switch (i) {
            SignalItem.type => text(signal.type, strong: true),
            SignalItem.operatorName => text(signal.operatorName),
            SignalItem.rsrp => reading('RSRP', signal.rsrp, signal.rsrpQuality),
            SignalItem.sinr => reading('SINR', signal.sinr, signal.sinrQuality),
            SignalItem.rsrq => reading('RSRQ', signal.rsrq, signal.rsrqQuality),
            SignalItem.bands => text(signal.bands),
            SignalItem.width => text(signal.totalWidth),
          },
    ];
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in _lines(context.ks))
              Padding(padding: const EdgeInsets.only(bottom: 2), child: l),
          ],
        ),
      ),
    ),
  );
}

class SignalDetails extends StatelessWidget {
  const SignalDetails(
    this.signal, {
    super.key,
    required this.prefs,
    this.onTap,
  });

  final SignalOverview signal;
  final HomePrefs prefs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final s = signal;
    final numbers = [
      if (s.rsrp != null) ('RSRP', s.rsrp!, 'dBm', s.rsrpQuality),
      if (s.sinr != null) ('SINR', s.sinr!, 'dB', s.sinrQuality),
    ];
    final rows = s.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Signal', style: KeystoneType.secondary(ks.mu)),
            ),
            if (onTap != null)
              TextButton(
                onPressed: onTap,
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                child: Text('Details', style: KeystoneType.secondary(ks.ac)),
              ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.symmetric(horizontal: BorderSide(color: ks.line)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    s.type ?? 'Mobile network',
                    style: KeystoneType.bodyStrong(ks.tx),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.operatorName ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: KeystoneType.secondary(ks.mu),
                    ),
                  ),
                ],
              ),
              if (s.summary != null)
                Text(s.summary!, style: KeystoneType.secondary(ks.mu)),
              if (prefs.signalNumbers && numbers.isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (name, v, unit, q) in numbers)
                      Expanded(child: _number(ks, name, v, unit, q)),
                  ],
                ),
              ],
              if (prefs.signalBar && s.carriers.isNotEmpty) ...[
                const SizedBox(height: 14),
                _CarrierBar(s.carriers),
              ],
              if (prefs.signalList && rows.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final (a, b) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a, style: KeystoneType.secondary(ks.mu)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            b,
                            textAlign: TextAlign.end,
                            style: KeystoneType.secondary(ks.tx),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _number(
    KeystoneColors ks,
    String name,
    String value,
    String unit,
    SignalQuality q,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(name, style: KeystoneType.caption(ks.mu)),
      const SizedBox(height: 2),
      Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(
            _n(value),
            semanticsLabel: value,
            style: KeystoneType.sheetTitle(
              q.tone(ks),
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text(
            '$unit  ${_word(q)}'.trimRight(),
            style: KeystoneType.caption(ks.mu),
          ),
        ],
      ),
    ],
  );
}

class _CarrierBar extends StatelessWidget {
  const _CarrierBar(this.carriers);
  final List<SignalCarrier> carriers;

  int _flex(SignalCarrier c) {
    if (carriers.any((c) => c.width == null)) return 100;
    final total = carriers.fold(0.0, (s, c) => s + c.width!);
    // narrow carriers still need room for their name
    return (c.width! / total * 1000).round().clamp(
      450 ~/ carriers.length,
      1000,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Semantics(
      label: [
        for (final c in carriers) c.resting ? '${c.band} idle' : c.band,
      ].join(', '),
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            height: MediaQuery.textScalerOf(context).scale(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, c) in carriers.indexed) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(flex: _flex(c), child: _piece(ks, c, i == 0)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _piece(KeystoneColors ks, SignalCarrier c, bool main) {
    final (back, front) = c.resting
        ? (ks.tint, ks.mu)
        : main
        ? (ks.ac, ks.bg)
        : (Color.lerp(ks.acSoft, ks.ac, .2)!, ks.tx);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: back,
        border: c.resting ? Border.all(color: ks.line) : null,
      ),
      child: Text(
        c.band,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: KeystoneType.caption(front),
      ),
    );
  }
}
