import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/client.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/screens/devices/device_info.dart';

enum _Filter { all, wifi, wired }

class DevicesView extends StatefulWidget {
  const DevicesView({
    super.key,
    required this.routerName,
    required this.clients,
    required this.pausedMacs,
    this.loading = false,
    this.onRouterMenu,
    required this.onOpen,
    required this.onResume,
    this.onAllDetails,
    this.onRefresh,
  });

  final String routerName;

  final List<Client> clients;
  final Set<String> pausedMacs;
  final bool loading;
  final VoidCallback? onRouterMenu;
  final ValueChanged<Client> onOpen;
  final ValueChanged<Client> onResume;
  final VoidCallback? onAllDetails;
  final Future<void> Function()? onRefresh;

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  _Filter _filter = _Filter.all;
  String _search = '';
  bool _searching = false;

  bool _wifi(Client c) => c.connectionType == ConnectionType.wireless;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final all = widget.clients;
    final shown = all.where((c) {
      if (_filter == _Filter.wifi && !_wifi(c)) return false;
      if (_filter == _Filter.wired && _wifi(c)) return false;
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return c.displayName.toLowerCase().contains(q) ||
          c.ipAddress.contains(q) ||
          c.macAddress.toLowerCase().contains(q);
    }).toList();
    final g = DeviceGroups.from(shown, widget.pausedMacs);
    final inUse = all.fold<double>(0, (s, c) => s + deviceMbps(c));
    final wifi = all.where(_wifi).length;

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onRouterMenu,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(44, 44),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          widget.routerName,
                          overflow: TextOverflow.ellipsis,
                          style: KeystoneType.bodyStrong(
                            ks.tx,
                          ).copyWith(fontSize: 18),
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, size: 20, color: ks.mu),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Search',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _search = '';
              }),
              icon: Icon(
                _searching ? Icons.close_rounded : Icons.search_rounded,
                color: ks.mu,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Devices', style: KeystoneType.title(ks.tx)),
        const SizedBox(height: 4),
        Text(
          '${all.length} online · ${inUse.toStringAsFixed(1)} Mbps in use',
          style: KeystoneType.secondary(ks.mu),
        ),
        if (_searching) ...[
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _search = v.trim()),
            style: KeystoneType.body(ks.tx),
            decoration: InputDecoration(
              hintText: 'Name, address or MAC',
              filled: true,
              fillColor: ks.node,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: ks.line),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(ks, _Filter.all, 'All ${all.length}'),
            _chip(ks, _Filter.wifi, 'Wi-Fi $wifi'),
            _chip(ks, _Filter.wired, 'Wired ${all.length - wifi}'),
          ],
        ),
        const SizedBox(height: 8),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              widget.loading
                  ? 'Looking for devices…'
                  : 'No devices are connected.',
              style: KeystoneType.body(ks.mu),
            ),
          ),
        ..._section(ks, 'Using the most', g.using),
        ..._section(ks, 'Quiet', g.quiet),
        ..._section(ks, 'Paused', g.paused, paused: true),
        if (widget.onAllDetails != null) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onAllDetails,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
              ),
              child: Text(
                'All device details',
                style: KeystoneType.body(ks.ac),
              ),
            ),
          ),
        ],
      ],
    );

    return SafeArea(
      bottom: false,
      child: widget.onRefresh == null
          ? list
          : RefreshIndicator(onRefresh: widget.onRefresh!, child: list),
    );
  }

  Widget _chip(KeystoneColors ks, _Filter f, String label) {
    final on = _filter == f;
    return Material(
      color: on ? ks.tx : ks.tint,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => setState(() => _filter = f),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: KeystoneType.secondary(
                  on ? ks.bg : ks.tx2,
                ).copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _section(
    KeystoneColors ks,
    String title,
    List<Client> devices, {
    bool paused = false,
  }) {
    if (devices.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      Text(title, style: KeystoneType.secondary(ks.mu)),
      const SizedBox(height: 4),
      for (final d in devices) _row(ks, d, paused),
    ];
  }

  Widget _row(KeystoneColors ks, Client d, bool paused) {
    final weak = isWeak(d);
    final mbps = deviceMbps(d);
    return InkWell(
      onTap: () => widget.onOpen(d),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: ks.line)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ks.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    ClientNamingHelper.getDeviceIcon(d),
                    size: 20,
                    color: ks.tx2,
                  ),
                ),
                if (!paused)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: weak ? ks.warn : ks.ok,
                        shape: BoxShape.circle,
                        border: Border.all(color: ks.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KeystoneType.body(ks.tx),
                  ),
                  Text(
                    paused ? 'No internet' : deviceLine(d),
                    style: KeystoneType.caption(weak ? ks.warnTx : ks.mu),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (paused)
              FilledButton(
                onPressed: () => widget.onResume(d),
                style: FilledButton.styleFrom(
                  backgroundColor: ks.tint,
                  foregroundColor: ks.tx,
                  minimumSize: const Size(44, 44),
                  shape: const StadiumBorder(),
                ),
                child: Text('Resume', style: KeystoneType.secondary(ks.tx)),
              )
            else if (mbps >= 0.1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    mbps.toStringAsFixed(1),
                    style: KeystoneType.bodyStrong(ks.tx),
                  ),
                  Text('Mbps', style: KeystoneType.caption(ks.mu)),
                ],
              )
            else
              Text('Idle', style: KeystoneType.caption(ks.mu)),
            if (!paused) Icon(Icons.chevron_right_rounded, color: ks.mu),
          ],
        ),
      ),
    );
  }
}
