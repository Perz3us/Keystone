import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/speed_chart.dart';

enum ControlState { idle, applying, failed }

class DeviceView extends StatelessWidget {
  const DeviceView({
    super.key,
    required this.name,
    required this.line,
    required this.weak,
    required this.wifi,
    required this.mbps,
    this.usedBytes,
    required this.samples,
    required this.paused,
    this.limitLine,
    required this.ip,
    required this.mac,
    required this.onPause,
    required this.onLimit,
    required this.onSchedule,
    this.onBlock,
    this.onWhy,
    this.pauseState = ControlState.idle,
    this.limitState = ControlState.idle,
    this.onRetryPause,
    this.onRetryLimit,
    this.blocked = false,
    this.extraDetails = const [],
    this.onForgetAddress,
  });

  final String name;
  final String line;
  final bool weak;
  final bool wifi;
  final double mbps;
  final int? usedBytes;
  final List<double> samples;
  final bool paused;

  final String? limitLine;
  final String ip;
  final String mac;
  final ValueChanged<bool> onPause;
  final ValueChanged<bool> onLimit;
  final VoidCallback onSchedule;
  final VoidCallback? onBlock;
  final VoidCallback? onWhy;
  final ControlState pauseState;
  final ControlState limitState;
  final VoidCallback? onRetryPause;
  final VoidCallback? onRetryLimit;

  final bool blocked;

  final List<(String, String)> extraDetails;

  final VoidCallback? onForgetAddress;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text(name, style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(line, style: KeystoneType.secondary(weak ? ks.warnTx : ks.mu)),
            if (weak && onWhy != null)
              TextButton(
                onPressed: onWhy,
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text('Why?', style: KeystoneType.secondary(ks.ac)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 6,
          children: [
            Text(
              '${mbps.toStringAsFixed(1)} Mbps',
              style: KeystoneType.sheetTitle(ks.tx),
            ),
            Text(
              [
                'right now',
                if (usedBytes != null && usedBytes! > 0)
                  '${_size(usedBytes!)} used',
              ].join(' · '),
              style: KeystoneType.secondary(ks.mu),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: samples.length < 3 ? null : SpeedChart(down: samples),
        ),
        const SizedBox(height: 16),
        _switch(
          ks,
          icon: Icons.pause_circle_outline_rounded,
          title: 'Pause internet',
          line: 'Stays on the network, no internet',
          value: paused,
          onChanged: onPause,
          state: pauseState,
        ),
        if (pauseState == ControlState.failed)
          _failed(ks, "Couldn't pause it", onRetryPause),
        _switch(
          ks,
          icon: Icons.speed_rounded,
          title: 'Limit speed',
          line: limitLine ?? 'Off',
          value: limitLine != null,
          onChanged: onLimit,
          state: limitState,
        ),
        if (limitState == ControlState.failed)
          _failed(ks, "Couldn't change the limit", onRetryLimit),
        _row(
          ks,
          icon: Icons.schedule_rounded,
          title: 'Schedule',
          line: 'Pause for a while',
          onTap: onSchedule,
        ),
        const SizedBox(height: 20),
        Text('Details', style: KeystoneType.secondary(ks.mu)),
        const SizedBox(height: 6),
        _detail(ks, 'Address', ip),
        _detail(ks, 'MAC', mac),
        for (final (label, value) in extraDetails) _detail(ks, label, value),
        if (onForgetAddress != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onForgetAddress,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                'Forget its fixed address',
                style: KeystoneType.secondary(ks.ac),
              ),
            ),
          ),
        if (wifi && onBlock != null) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onBlock,
              style: TextButton.styleFrom(
                backgroundColor: ks.node,
                foregroundColor: ks.bad,
                minimumSize: const Size(44, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                blocked ? 'Unblock this device…' : 'Block this device…',
                style: KeystoneType.body(
                  ks.bad,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _size(int bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(0)} MB';
    return '${(bytes / 1e3).toStringAsFixed(0)} KB';
  }

  Widget _icon(KeystoneColors ks, IconData icon) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: ks.tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, size: 18, color: ks.tx2),
  );

  Widget _texts(KeystoneColors ks, String title, String line) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: KeystoneType.body(ks.tx)),
      Text(line, style: KeystoneType.caption(ks.mu)),
    ],
  );

  Widget _switch(
    KeystoneColors ks, {
    required IconData icon,
    required String title,
    required String line,
    required bool value,
    required ValueChanged<bool> onChanged,
    ControlState state = ControlState.idle,
  }) {
    final applying = state == ControlState.applying;
    return InkWell(
      onTap: applying ? null : () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ks.line)),
        ),
        child: Row(
          children: [
            _icon(ks, icon),
            const SizedBox(width: 12),
            Expanded(
              child: applying
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: KeystoneType.body(ks.tx)),
                        Text(
                          'Applying on the router…',
                          style: KeystoneType.caption(ks.ac),
                        ),
                      ],
                    )
                  : _texts(ks, title, line),
            ),
            if (applying)
              Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ks.ac,
                  ),
                ),
              )
            else
              Switch(
                value: value,
                onChanged: onChanged,
                activeTrackColor: ks.ac,
              ),
          ],
        ),
      ),
    );
  }

  Widget _failed(KeystoneColors ks, String title, VoidCallback? onRetry) =>
      Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: ks.node,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ks.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.error_outline_rounded, size: 18, color: ks.bad),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: KeystoneType.bodyStrong(ks.tx)),
                  Text(
                    "The router didn't answer. Nothing was changed.",
                    style: KeystoneType.caption(ks.mu),
                  ),
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  backgroundColor: ks.tx,
                  minimumSize: const Size(44, 44),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  'Try again',
                  style: KeystoneType.secondary(
                    ks.bg,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      );

  Widget _row(
    KeystoneColors ks, {
    required IconData icon,
    required String title,
    required String line,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ks.line)),
      ),
      child: Row(
        children: [
          _icon(ks, icon),
          const SizedBox(width: 12),
          Expanded(child: _texts(ks, title, line)),
          Icon(Icons.chevron_right_rounded, color: ks.mu),
        ],
      ),
    ),
  );

  Widget _detail(KeystoneColors ks, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(label, style: KeystoneType.secondary(ks.mu)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(value, style: KeystoneType.address(ks.tx2)),
        ),
      ],
    ),
  );
}
