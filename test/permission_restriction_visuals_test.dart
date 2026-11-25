// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

RouterCapabilities createCompleteCaps() {
  return RouterCapabilities(
    routerId: 'test-router',
    ubusObjects: const {'uci', 'system', 'luci-rpc', 'file', 'iwinfo'},
    ubusMethods: const {
      'uci': ['get', 'set', 'commit'],
      'system': ['info', 'reboot'],
      'luci-rpc': ['getWirelessDevices'],
      'file': ['read', 'stat', 'exec'],
    },
    packageEngine: PackageManagerEngine.opkg,
    firewallBackend: FirewallBackend.fw4,
    networkModel: NetworkModel.dsa,
    releaseVersion: 'OpenWrt 23.05.3',
    boardName: 'test-board',
    probedAt: DateTime.now(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouterCapabilities RPC Check Logic', () {
    test('Correctly identifies missing RPC modules and permissions', () {
      final incompleteCaps = RouterCapabilities(
        routerId: 'test-router',
        ubusObjects: const {'uci', 'system'},
        ubusMethods: const {
          'uci': ['get', 'set'],
          'system': ['info'],
          'file': ['read'],
        },
        packageEngine: PackageManagerEngine.opkg,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt 23.05.3',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      expect(incompleteCaps.hasFileExec, isFalse);
      expect(incompleteCaps.hasLuciRpc, isFalse);
      expect(incompleteCaps.isRpcComplete, isFalse);
    });

    test('Correctly identifies complete RPC capability', () {
      final completeCaps = createCompleteCaps();

      expect(completeCaps.hasFileExec, isTrue);
      expect(completeCaps.hasLuciRpc, isTrue);
      expect(completeCaps.isRpcComplete, isTrue);
    });

    test('Correctly handles wildcard * in ubusObjects and ubusMethods', () {
      final wildcardCaps = RouterCapabilities(
        routerId: 'wildcard-router',
        ubusObjects: const {'*'},
        ubusMethods: const {
          '*': ['*'],
        },
        uciPermissions: const {
          '*': ['*'],
        },
        packageEngine: PackageManagerEngine.apk,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt SNAPSHOT',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      expect(wildcardCaps.hasObject('file'), isTrue);
      expect(wildcardCaps.hasObject('luci-rpc'), isTrue);
      expect(wildcardCaps.hasObject('iwinfo'), isTrue);
      expect(wildcardCaps.hasFileExec, isTrue);
      expect(wildcardCaps.hasLuciRpc, isTrue);
      expect(wildcardCaps.hasUciWriteAccess, isTrue);
      expect(wildcardCaps.isRpcComplete, isTrue);
    });

    test(
      'Correctly identifies stock OpenWrt standard LuCI ACL permissions (from session.access)',
      () {
        final stockLuciCaps = RouterCapabilities(
          routerId: 'stock-openwrt',
          ubusObjects: const {
            'dsl',
            'file',
            'fingerprint',
            'hostapd.*',
            'iwinfo',
            'log',
            'luci',
            'luci-rpc',
            'network',
            'network.device',
            'network.interface',
            'rc',
            'service',
            'session',
            'system',
            'uci',
          },
          ubusMethods: const {
            'file': ['read', 'write', 'list', 'remove', 'exec', 'stat'],
            'iwinfo': [
              'assoclist',
              'countrylist',
              'freqlist',
              'txpowerlist',
              'scan',
              'info',
            ],
            'luci-rpc': [
              'getBoardJSON',
              'getHostHints',
              'getNetworkDevices',
              'getWirelessDevices',
              'getDHCPLeases',
              'getDUIDHints',
            ],
            'system': ['board', 'info', 'validate_firmware_image', 'reboot'],
            'uci': [
              'get',
              'set',
              'commit',
              'changes',
              'add',
              'apply',
              'confirm',
              'delete',
              'order',
              'rename',
            ],
          },
          uciPermissions: const {
            'attendedsysupgrade': ['read', 'write'],
            'dhcp': ['read', 'write'],
            'dropbear': ['read', 'write'],
            'firewall': ['read', 'write'],
            'fstab': ['read', 'write'],
            'luci': ['read', 'write'],
            'network': ['read', 'write'],
            'system': ['read', 'write'],
            'uhttpd': ['read', 'write'],
            'wireless': ['read', 'write'],
          },
          packageEngine: PackageManagerEngine.apk,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt 24.10.0',
          boardName: 'stock-board',
          probedAt: DateTime.now(),
        );

        expect(stockLuciCaps.hasFileExec, isTrue);
        expect(stockLuciCaps.hasLuciRpc, isTrue);
        expect(stockLuciCaps.hasUciWriteAccess, isTrue);
        expect(stockLuciCaps.isRpcComplete, isTrue);
      },
    );

    test('Serializes and deserializes uciPermissions', () {
      final original = RouterCapabilities(
        routerId: 'test-serial',
        ubusObjects: const {'file', 'uci'},
        ubusMethods: const {
          'file': ['exec'],
        },
        uciPermissions: const {
          'network': ['read', 'write'],
          'wireless': ['read'],
        },
        packageEngine: PackageManagerEngine.opkg,
        firewallBackend: FirewallBackend.fw4,
        networkModel: NetworkModel.dsa,
        releaseVersion: 'OpenWrt 23.05.3',
        boardName: 'test-board',
        probedAt: DateTime.now(),
      );

      final json = original.toJson();
      final recovered = RouterCapabilities.fromJson(json);

      expect(recovered.uciPermissions.containsKey('network'), isTrue);
      expect(recovered.uciPermissions['network'], contains('write'));
      expect(recovered.uciPermissions['wireless'], contains('read'));
      expect(recovered.hasUciWriteAccess, isTrue);
    });
  });

  group('SQM Widget Permission Restriction Visuals', () {});

  group('DashboardScreen & MoreScreen Zero Visual Cues', () {});

  group('ClientsScreen & PackageManagerScreen Visual Cues', () {});

  group('Router Capabilities & Edge Cases', () {
    test(
      'Router with iwinfo (alternative RPC provider) + file.exec is considered RPC complete',
      () {
        final iwinfoCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {'uci', 'system', 'iwinfo', 'file'},
          ubusMethods: const {
            'uci': ['get', 'set'],
            'system': ['info'],
            'iwinfo': ['info', 'scan'],
            'file': ['exec', 'read'],
          },
          packageEngine: PackageManagerEngine.opkg,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt 23.05.3',
          boardName: 'test-board',
          probedAt: DateTime.now(),
        );

        expect(iwinfoCaps.hasLuciRpc, isTrue);
        expect(iwinfoCaps.hasFileExec, isTrue);
        expect(iwinfoCaps.isRpcComplete, isTrue);

        AppState.instance.setCapabilitiesForTesting(iwinfoCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test(
      'Network failure during capability probe (probeFailed=true) does NOT trigger false visual cues',
      () {
        final failedProbeCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {},
          ubusMethods: const {},
          packageEngine: PackageManagerEngine.none,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt',
          boardName: 'unknown',
          probedAt: DateTime.now(),
          probeFailed: true,
          lastProbeError: 'Connection refused',
        );

        AppState.instance.setCapabilitiesForTesting(failedProbeCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test(
      'Empty ubusObjects (fresh load / connecting) does NOT trigger false visual cues',
      () {
        final freshCaps = RouterCapabilities(
          routerId: 'test-router',
          ubusObjects: const {},
          ubusMethods: const {},
          packageEngine: PackageManagerEngine.none,
          firewallBackend: FirewallBackend.fw4,
          networkModel: NetworkModel.dsa,
          releaseVersion: 'OpenWrt',
          boardName: 'unknown',
          probedAt: DateTime.now(),
        );

        AppState.instance.setCapabilitiesForTesting(freshCaps);
        expect(AppState.instance.isMissingRpcPackages, isFalse);
      },
    );

    test('Null capabilities does NOT trigger false visual cues', () {
      AppState.instance.setCapabilitiesForTesting(null);
      expect(AppState.instance.isMissingRpcPackages, isFalse);
    });
  });
}
