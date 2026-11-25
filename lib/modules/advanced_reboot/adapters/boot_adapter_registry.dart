// SPDX-License-Identifier: GPL-3.0-or-later

import '../models/reboot_capability.dart';
import 'acpi_poweroff_adapter.dart';
import 'boot_mechanism_adapter.dart';
import 'standard_reboot_adapter.dart';
import 'ubi_dual_boot_adapter.dart';
import 'uboot_boot_part_adapter.dart';
import 'uboot_boot_part_ready_adapter.dart';
import 'uboot_dual_image_flag_adapter.dart';

class BootAdapterRegistry {
  static final BootAdapterRegistry instance = BootAdapterRegistry();

  final List<BootMechanismAdapter> _adapters;

  BootAdapterRegistry({List<BootMechanismAdapter>? adapters})
    : _adapters =
          adapters ??
          [
            const StandardRebootAdapter(),
            const UBootBootPartReadyAdapter(),
            const UBootBootPartAdapter(),
            const UBootDualImageFlagAdapter(),
            const UbiDualBootAdapter(),
            const AcpiPowerOffAdapter(),
          ];

  List<BootMechanismAdapter> get allAdapters => List.unmodifiable(_adapters);

  BootMechanismAdapter? getAdapter(String adapterId) {
    for (final adapter in _adapters) {
      if (adapter.adapterId == adapterId) {
        return adapter;
      }
    }
    return null;
  }

  List<BootMechanismAdapter> adaptersFor(RebootOperationType operation) {
    return _adapters
        .where((adapter) => adapter.supportedOperations.contains(operation))
        .toList();
  }

  void registerAdapter(BootMechanismAdapter adapter) {
    _adapters.removeWhere((a) => a.adapterId == adapter.adapterId);
    _adapters.add(adapter);
  }
}
