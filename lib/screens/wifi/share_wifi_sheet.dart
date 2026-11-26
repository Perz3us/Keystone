import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/screens/wifi/wifi_info.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

Future<void> showShareWifi(
  BuildContext context, {
  required WifiNet home,
  WifiNet? guest,
}) {
  return ksSheet<void>(context, (_) => _ShareSheet(home: home, guest: guest));
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({required this.home, this.guest});
  final WifiNet home;
  final WifiNet? guest;

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _guest = false;
  bool _reveal = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final net = _guest && widget.guest != null ? widget.guest! : widget.home;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Text('Share Wi-Fi', style: KeystoneType.sheetTitle(ks.tx)),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: ks.mu),
                ),
              ),
            ],
          ),
          if (widget.guest != null) ...[
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Home')),
                ButtonSegment(value: true, label: Text('Guest')),
              ],
              selected: {_guest},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() {
                _guest = v.first;
                _reveal = false;
                _copied = false;
              }),
            ),
          ],
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: KeystoneColors.paper,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ks.line),
              ),
              child: QrImageView(
                data: wifiQrPayload(net),
                size: 176,
                padding: EdgeInsets.zero,
                semanticsLabel: 'QR code to join ${net.ssid}',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Point a phone camera at this to join.',
            textAlign: TextAlign.center,
            style: KeystoneType.secondary(ks.mu),
          ),
          const SizedBox(height: 14),
          Text('Network', style: KeystoneType.body(ks.tx)),
          Text(net.ssid, style: KeystoneType.caption(ks.mu)),
          if (!net.open) ...[
            Divider(color: ks.line, height: 20),
            Text('Password', style: KeystoneType.body(ks.tx)),
            Row(
              children: [
                Flexible(
                  child: Text(
                    _reveal ? (net.key ?? '') : '••••••••••',
                    style: KeystoneType.caption(ks.mu),
                  ),
                ),
                IconButton(
                  tooltip: _reveal ? 'Hide password' : 'Show password',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _reveal = !_reveal),
                  icon: Icon(
                    _reveal
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: ks.mu,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: net.open
                      ? 'Wi-Fi: ${net.ssid}'
                      : 'Wi-Fi: ${net.ssid}\nPassword: ${net.key ?? ''}',
                ),
              );
              setState(() => _copied = true);
            },
            style: FilledButton.styleFrom(
              backgroundColor: ks.tx,
              foregroundColor: ks.bg,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(
              _copied ? 'Copied' : 'Copy',
              style: KeystoneType.bodyStrong(ks.bg),
            ),
          ),
        ],
      ),
    );
  }
}
