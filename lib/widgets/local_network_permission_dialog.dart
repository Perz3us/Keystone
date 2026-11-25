import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/services/local_network_permission_service.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

class LocalNetworkPermissionDialog extends StatelessWidget {
  const LocalNetworkPermissionDialog({
    super.key,
    this.isPermanentlyDenied = false,
  });

  final bool isPermanentlyDenied;

  static Future<bool?> show(
    BuildContext context, {
    bool isPermanentlyDenied = false,
  }) => ksSheet<bool>(
    context,
    (_) =>
        LocalNetworkPermissionDialog(isPermanentlyDenied: isPermanentlyDenied),
  );

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final denied = isPermanentlyDenied;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          denied ? 'Keystone can\'t reach your router' : 'Find your router',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 8),
        Text(
          denied
              ? 'Local network access is off for Keystone. Turn it on in '
                    'Settings, under Permissions.'
              : 'Android asks before an app talks to devices on your '
                    'Wi-Fi. Keystone only talks to your router, and nothing '
                    'leaves your home network.',
          style: KeystoneType.body(ks.tx2),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(!denied);
            if (denied) LocalNetworkPermissionService.openAppSettings();
          },
          child: Text(denied ? 'Open Settings' : 'Continue'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
