// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import 'channel_check.dart';

export 'channel_check.dart' show ScanUnsupported;

Future<List<Map<String, dynamic>>> scanWifi(AppState app, String device) async {
  final Map<String, dynamic> r;
  try {
    r = await noobCall(app, 'iwinfo', 'scan', {'device': device});
  } on NoobRpcError catch (e) {
    if (const {
      'Not supported',
      'Invalid argument',
      'Not found',
      'No data',
    }.contains(e.message)) {
      throw const ScanUnsupported();
    }
    rethrow;
  }
  final rows = r['results'];
  return [
    if (rows is List)
      for (final n in rows)
        if (n is Map) Map<String, dynamic>.from(n),
  ];
}

class ChannelCheckScreen extends StatefulWidget {
  const ChannelCheckScreen({
    super.key,
    required this.scan,
    required this.is5g,
    required this.current,
    required this.allowed,
  });

  final Future<List<Map<String, dynamic>>> Function() scan;
  final bool is5g;

  final int current;
  final Set<int> allowed;

  @override
  State<ChannelCheckScreen> createState() => _ChannelCheckScreenState();
}

class _ChannelCheckScreenState extends State<ChannelCheckScreen> {
  List<ChannelLoad>? _loads;
  List<ChannelLoad> _heard = const [];
  int? _pick;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _loads = null;
      _error = null;
    });
    try {
      final scan = await widget.scan();
      final loads = channelLoads(scan, is5g: widget.is5g);
      _pick = suggestChannel(
        loads,
        is5g: widget.is5g,
        current: widget.current,
        allowed: widget.allowed,
      );
      final heard = channelLoads(scan, is5g: true);
      _heard = [
        ...heard,
        if (widget.current > 0 &&
            heard.every((l) => l.channel != widget.current))
          ChannelLoad(widget.current, 0, null),
      ]..sort((a, b) => a.channel.compareTo(b.channel));
      _loads = loads;
    } on ScanUnsupported {
      _error = "This router can't scan on this band";
    } catch (_) {
      _error =
          "Couldn't scan. Check you're on the router's Wi-Fi and try again.";
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final loads = _loads, pick = _pick;
    return KsPage(
      title: 'Check channels',
      back: widget.is5g ? '5 GHz' : '2.4 GHz',
      onRefresh: _run,
      children: [
        if (_error != null) ...[
          KsBanner(_error!, bad: true),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _run, child: const Text('Try again')),
        ] else if (loads == null || pick == null) ...[
          const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 10),
          Text(
            'Listening for nearby networks…',
            style: KeystoneType.secondary(ks.mu),
          ),
        ] else ...[
          Text(
            pick == widget.current
                ? 'Channel $pick is already the quietest'
                : 'Channel $pick is the quietest',
            style: KeystoneType.sheetTitle(ks.tx),
          ),
          if (pick != widget.current) ...[
            const SizedBox(height: 6),
            Text(
              'Wi-Fi drops for a few seconds while it switches, and this phone '
              'may need to reconnect.',
              style: KeystoneType.secondary(ks.mu),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(pick),
              child: Text('Use channel $pick'),
            ),
          ],
          const KsSection('Nearby'),
          if (_heard.isEmpty) const KsNote('No other networks heard'),
          for (final l in _heard)
            KsRow(
              title: 'Channel ${l.channel}',
              subtitle: l.networks == 0
                  ? 'No networks'
                  : [
                      '${l.networks} network${l.networks == 1 ? '' : 's'}',
                      if (l.strongest != null) 'loudest ${l.strongest} dBm',
                    ].join(' · '),
              trailing: l.channel == widget.current
                  ? Text('Yours', style: KeystoneType.caption(ks.ac))
                  : null,
            ),
          if (!widget.is5g && _heard.isNotEmpty)
            const KsNote(
              'Networks up to two channels away get in the way too.',
            ),
        ],
      ],
    );
  }
}
