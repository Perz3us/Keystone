import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

enum DeviceFilter { all, online, offline, limited, blocked }

String _norm(String mac) => mac.toUpperCase().replaceAll('-', ':');

List<Client> withBlocked(List<Client> all, Set<String> blockedOrPaused) {
  final known = {for (final c in all) c.normalizedMac};
  return [
    ...all,
    for (final mac in blockedOrPaused.map(_norm))
      if (!known.contains(mac))
        Client(
          ipAddress: 'N/A',
          macAddress: mac,
          hostname: mac,
          isConnected: false,
          connectionType: ConnectionType.wireless,
        ),
  ];
}

List<Client> filterDevices(
  List<Client> all, {
  required DeviceFilter filter,
  String query = '',
  required Set<String> blocked,
  Set<String> limited = const {},
}) {
  final b = blocked.map(_norm).toSet();
  final l = limited.map(_norm).toSet();
  final q = query.trim().toLowerCase();
  return [
    for (final c in all)
      if (switch (filter) {
            DeviceFilter.all => true,
            DeviceFilter.online =>
              c.isConnected && !b.contains(c.normalizedMac),
            DeviceFilter.offline =>
              !c.isConnected && !b.contains(c.normalizedMac),
            DeviceFilter.limited => l.contains(c.normalizedMac),
            DeviceFilter.blocked => b.contains(c.normalizedMac),
          } &&
          (q.isEmpty ||
              [
                c.displayName,
                c.hostname,
                c.ipAddress,
                c.macAddress,
                c.vendor ?? '',
              ].any((s) => s.toLowerCase().contains(q))))
        c,
  ];
}

class AllDevicesView extends StatefulWidget {
  const AllDevicesView({
    super.key,
    required this.devices,
    required this.blocked,
    required this.paused,
    required this.onOpen,
    this.onRefresh,
    this.loading = false,
    this.limited = const {},
    this.usage = const {},
    this.usageLabel = 'Data used',
    this.startByData = false,
  });

  final List<Client> devices;

  final Set<String> blocked;
  final Set<String> paused;
  final ValueChanged<Client> onOpen;
  final Future<void> Function()? onRefresh;
  final bool loading;

  final Set<String> limited;

  final Map<String, int> usage;
  final String usageLabel;

  final bool startByData;

  @override
  State<AllDevicesView> createState() => _AllDevicesViewState();
}

class _AllDevicesViewState extends State<AllDevicesView> {
  var _filter = DeviceFilter.all;
  var _query = '';
  late var _byData = widget.startByData;

  int _used(Client c) => widget.usage[c.normalizedMac] ?? 0;

  static String _size(int b) => b >= 1e9
      ? '${(b / 1e9).toStringAsFixed(1)} GB'
      : b >= 1e6
      ? '${(b / 1e6).toStringAsFixed(0)} MB'
      : '${(b / 1e3).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final held = {...widget.blocked, ...widget.paused}.map(_norm).toSet();
    int count(DeviceFilter f) => filterDevices(
      widget.devices,
      filter: f,
      blocked: held,
      limited: widget.limited,
    ).length;
    final shown = filterDevices(
      widget.devices,
      filter: _filter,
      query: _query,
      blocked: held,
      limited: widget.limited,
    );
    if (_byData) shown.sort((a, b) => _used(b).compareTo(_used(a)));
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        Text('All devices', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'Everything this router has seen, online or not.',
          style: KeystoneType.secondary(ks.mu),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Name, address or maker',
            prefixIcon: Icon(Icons.search_rounded, color: ks.mu),
            filled: true,
            fillColor: ks.node,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: ks.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: ks.line),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (f, label) in [
              (DeviceFilter.all, 'All'),
              (DeviceFilter.online, 'Online'),
              (DeviceFilter.offline, 'Offline'),
              (DeviceFilter.limited, 'Limited'),
              (DeviceFilter.blocked, 'Blocked'),
            ])
              if (f == DeviceFilter.all ||
                  f == DeviceFilter.online ||
                  f == DeviceFilter.offline ||
                  count(f) > 0)
                ChoiceChip(
                  label: Text('$label ${count(f)}'),
                  selected: _filter == f,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = f),
                  labelStyle: KeystoneType.secondary(
                    _filter == f ? ks.bg : ks.tx2,
                  ),
                  selectedColor: ks.tx,
                  backgroundColor: ks.node,
                  side: BorderSide(color: _filter == f ? ks.tx : ks.line),
                  shape: const StadiumBorder(),
                ),
          ],
        ),
        if (widget.usage.isNotEmpty) ...[
          const SizedBox(height: 8),
          KsChips<bool>(
            options: const [(false, 'A to Z'), (true, 'Most data')],
            selected: _byData,
            onSelected: (v) => setState(() => _byData = v),
          ),
        ],
        const SizedBox(height: 8),
        if (widget.loading && widget.devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              _query.isEmpty ? 'No devices here.' : 'Nothing matches that.',
              style: KeystoneType.body(ks.mu),
            ),
          ),
        for (final c in shown) _row(ks, c),
      ],
    );
    return widget.onRefresh == null
        ? list
        : RefreshIndicator(onRefresh: widget.onRefresh!, child: list);
  }

  Widget _row(KeystoneColors ks, Client c) {
    final mac = c.normalizedMac;
    final blocked = widget.blocked.map(_norm).contains(mac);
    final paused = widget.paused.map(_norm).contains(mac);
    final limited = widget.limited.map(_norm).contains(mac);
    final (status, color) = blocked
        ? ('Blocked', ks.bad)
        : paused
        ? ('Paused', ks.warnTx)
        : limited
        ? ('Limited', ks.warnTx)
        : c.isConnected
        ? ('Online', ks.ok)
        : ('Offline', ks.mu);
    final line = [
      if (c.ipAddress.isNotEmpty && c.ipAddress != 'N/A') c.ipAddress,
      c.macAddress,
      if ((c.vendor ?? '').isNotEmpty) c.vendor!,
      if (c.isDumbApClient && (c.apName ?? '').isNotEmpty) 'via ${c.apName}',
    ].join(' · ');
    final used = _used(c);
    return InkWell(
      onTap: () => widget.onOpen(c),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ks.line)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ks.tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                ClientNamingHelper.getDeviceIcon(c),
                size: 20,
                color: c.isConnected ? ks.tx2 : ks.mu,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KeystoneType.body(c.isConnected ? ks.tx : ks.tx2),
                  ),
                  Text(
                    line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: KeystoneType.caption(ks.mu),
                  ),
                  if (_byData && used > 0)
                    Text(
                      '${_size(used)} ${widget.usageLabel.toLowerCase()}',
                      style: KeystoneType.caption(ks.tx2),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(status, style: KeystoneType.caption(color)),
            Icon(Icons.chevron_right_rounded, color: ks.mu),
          ],
        ),
      ),
    );
  }
}
