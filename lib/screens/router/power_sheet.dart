import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/controllers/advanced_reboot_controller.dart';
import 'package:yet_another_luci_app/modules/advanced_reboot/models/reboot_capability.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

Future<void> showPowerSheet(BuildContext context) =>
    ksSheet<void>(context, (_) => const _PowerSheet());

class _PowerSheet extends ConsumerWidget {
  const _PowerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(advancedRebootControllerProvider);
    final c = ref.read(advancedRebootControllerProvider.notifier);
    final caps = s.capabilities;
    final alt = caps?.alternatePartitionBoot;
    final slot = alt?.targetIdentifier;
    final os = caps?.environment.alternateOs;
    final p = s.progress;
    return PowerOptionsView(
      checking: s.isDetecting,
      otherFirmware: alt != null && alt.isSupported && slot != null
          ? ['Slot $slot', if (os != null && os.isNotEmpty) os].join(' · ')
          : null,
      canPowerOff: caps?.powerOff.isSupported ?? false,
      busy: p.isBusy && !p.isIdle,
      status: p.isIdle
          ? null
          : p.isFailed
          ? 'That didn\'t work: ${p.failureReason ?? p.message}'
          : p.message,
      onOtherFirmware: () => c.executeOperation(
        RebootOperationType.alternatePartitionBoot,
        targetSlot: slot,
      ),
      onPowerOff: () => c.executeOperation(RebootOperationType.powerOff),
    );
  }
}

class PowerOptionsView extends StatelessWidget {
  const PowerOptionsView({
    super.key,
    required this.checking,
    this.otherFirmware,
    this.canPowerOff = false,
    this.busy = false,
    this.status,
    this.onOtherFirmware,
    this.onPowerOff,
  });

  final bool checking;

  final String? otherFirmware;
  final bool canPowerOff;
  final bool busy;
  final String? status;
  final VoidCallback? onOtherFirmware;
  final VoidCallback? onPowerOff;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Other firmware or power off',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 8),
        if (checking)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Checking what this router can do…',
                  style: KeystoneType.body(ks.mu),
                ),
              ],
            ),
          )
        else if (otherFirmware == null && !canPowerOff)
          const KsNote(
            'This router can only restart normally. Use Restart router in '
            'the menu.',
          )
        else ...[
          if (otherFirmware != null)
            KsRow(
              title: 'Start the other firmware',
              subtitle: otherFirmware,
              onTap: busy
                  ? null
                  : () async {
                      if (await ksConfirm(
                        context,
                        title: 'Start the other firmware?',
                        body:
                            'The router restarts into $otherFirmware. It may '
                            'be an older build with different Wi-Fi names, '
                            'passwords or addresses, so you may need to '
                            'reconnect by hand.',
                        action: 'Restart',
                        danger: true,
                      )) {
                        onOtherFirmware?.call();
                      }
                    },
            ),
          if (canPowerOff)
            KsRow(
              title: 'Power off',
              subtitle:
                  'Turn it back on with its power button or by '
                  'unplugging it',
              danger: true,
              onTap: busy
                  ? null
                  : () async {
                      if (await ksConfirm(
                        context,
                        title: 'Power off the router?',
                        body:
                            'Everything loses the internet until someone '
                            'turns it back on by hand.',
                        action: 'Power off',
                        danger: true,
                      )) {
                        onPowerOff?.call();
                      }
                    },
            ),
        ],
        if (status != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (busy) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(status!, style: KeystoneType.secondary(ks.tx2)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
