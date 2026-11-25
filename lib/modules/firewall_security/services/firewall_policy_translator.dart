// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/models/router_capabilities.dart';
import 'package:yet_another_luci_app/modules/firewall_security/models/firewall_info.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';

class RecognizedDevicePolicy {
  final String targetMac;
  final bool hasActiveBlock;
  final bool isLegacy;
  final List<String> matchingSectionKeys;
  final Set<String> blockedFamilies;
  final NetworkAccessPolicy policy;

  const RecognizedDevicePolicy({
    required this.targetMac,
    required this.hasActiveBlock,
    required this.isLegacy,
    required this.matchingSectionKeys,
    required this.blockedFamilies,
    required this.policy,
  });
}

enum UciMutationType { add, set, delete, none }

class UciRuleMutation {
  final UciMutationType type;
  final String? sectionKey;
  final Map<String, dynamic> values;

  const UciRuleMutation({
    required this.type,
    this.sectionKey,
    this.values = const {},
  });
}

class FirewallPolicyTranslator {
  static const String legacyNoInternetRuleName = 'nointernet_wireless_clients';
  static const String legacyPausePrefix = 'Pause_Internet_';
  static const String legacyBanPrefix = 'Ban_Client_';
  static const String legacyKickPrefix = 'Kick_Client_';
  static const String rulePrefix = 'Keystone_Block_';

  static const String oldRulePrefix = 'Yala_Block_';

  static String formatRuleName(String mac, {String family = 'any'}) {
    final cleanMac = mac.toUpperCase().replaceAll(':', '').replaceAll('-', '');
    if (family == 'ipv4') {
      return '${rulePrefix}IPv4_$cleanMac';
    } else if (family == 'ipv6') {
      return '${rulePrefix}IPv6_$cleanMac';
    }
    return '$rulePrefix$cleanMac';
  }

  static bool isLegacyBlockRule(FirewallCustomRule rule) {
    final name = rule.name;
    return name == legacyNoInternetRuleName ||
        name.startsWith(legacyPausePrefix) ||
        name.startsWith(legacyBanPrefix) ||
        name.startsWith(legacyKickPrefix);
  }

  static RecognizedDevicePolicy recognizePolicy({
    required String targetMac,
    required List<FirewallCustomRule> rules,
  }) {
    final normMac = ClientNamingHelper.normalizeMac(targetMac);
    final rawMacNoDelim = normMac.replaceAll(':', '').toLowerCase();

    bool hasBlock = false;
    bool isLegacy = false;
    final matchingSectionKeys = <String>[];
    final blockedFamilies = <String>{};

    for (final rule in rules) {
      if (!rule.enabled) continue;

      final target = rule.target.toUpperCase();
      final isDropOrReject =
          target == 'DROP' || target == 'REJECT' || target == 'STOP';
      if (!isDropOrReject) continue;

      bool macMatches = false;
      for (final sm in rule.srcMac) {
        if (ClientNamingHelper.normalizeMac(sm) == normMac) {
          macMatches = true;
          break;
        }
      }

      final lowerName = rule.name.toLowerCase();
      if (!macMatches && lowerName.contains(rawMacNoDelim)) {
        macMatches = true;
      }

      if (macMatches) {
        hasBlock = true;
        matchingSectionKeys.add(rule.sectionKey);
        if (isLegacyBlockRule(rule)) {
          isLegacy = true;
        }
        final fam = rule.family.toLowerCase();
        if (fam.isEmpty || fam == 'any' || fam == 'all') {
          blockedFamilies.add('ipv4');
          blockedFamilies.add('ipv6');
        } else {
          blockedFamilies.add(fam);
        }
      }
    }

    if (!hasBlock) {
      return RecognizedDevicePolicy(
        targetMac: normMac,
        hasActiveBlock: false,
        isLegacy: false,
        matchingSectionKeys: const [],
        blockedFamilies: const {},
        policy: NetworkAccessPolicy.unrestricted(normMac),
      );
    }

    final blocksIpv4 = blockedFamilies.contains('ipv4');
    final blocksIpv6 = blockedFamilies.contains('ipv6');
    final blocksBoth = blocksIpv4 && blocksIpv6;

    final policy = NetworkAccessPolicy(
      targetMac: normMac,
      internetAccess: !blocksBoth,
      ipv4Access: !blocksIpv4,
      ipv6Access: !blocksIpv6,
    );

    return RecognizedDevicePolicy(
      targetMac: normMac,
      hasActiveBlock: true,
      isLegacy: isLegacy,
      matchingSectionKeys: matchingSectionKeys,
      blockedFamilies: blockedFamilies,
      policy: policy,
    );
  }

  static List<UciRuleMutation> translatePolicyToUci({
    required NetworkAccessPolicy policy,
    required RouterCapabilities capabilities,
    required List<FirewallCustomRule> existingRules,
  }) {
    final normMac = ClientNamingHelper.normalizeMac(policy.targetMac);
    final mutations = <UciRuleMutation>[];

    final recognized = recognizePolicy(
      targetMac: normMac,
      rules: existingRules,
    );

    if (policy.effectiveInternetAccess &&
        policy.effectiveIpv4Access &&
        policy.effectiveIpv6Access) {
      for (final secKey in recognized.matchingSectionKeys) {
        final existingRule = existingRules.firstWhere(
          (r) => r.sectionKey == secKey,
          orElse: () => FirewallCustomRule(
            sectionKey: secKey,
            name: '',
            srcZone: '',
            destZone: '',
            target: '',
            enabled: false,
          ),
        );

        if (existingRule.srcMac.length > 1) {
          final updatedMacs = existingRule.srcMac
              .where((m) => ClientNamingHelper.normalizeMac(m) != normMac)
              .toList();
          mutations.add(
            UciRuleMutation(
              type: UciMutationType.set,
              sectionKey: secKey,
              values: {'src_mac': updatedMacs},
            ),
          );
        } else {
          mutations.add(
            UciRuleMutation(type: UciMutationType.delete, sectionKey: secKey),
          );
        }
      }
      return mutations;
    }

    String targetFamily = 'any';
    if (!policy.effectiveInternetAccess ||
        (!policy.effectiveIpv4Access && !policy.effectiveIpv6Access)) {
      targetFamily = 'any';
    } else if (!policy.effectiveIpv4Access && policy.effectiveIpv6Access) {
      targetFamily = 'ipv4';
    } else if (policy.effectiveIpv4Access && !policy.effectiveIpv6Access) {
      if (capabilities.supportsIpv6InternetFirewall) {
        targetFamily = 'ipv6';
      } else {
        return mutations;
      }
    }

    final ruleName = formatRuleName(normMac, family: targetFamily);

    String? existingSecKey;
    for (final rule in existingRules) {
      if (rule.name == ruleName ||
          ((rule.name.startsWith(rulePrefix) ||
                  rule.name.startsWith(oldRulePrefix)) &&
              rule.srcMac.any(
                (m) => ClientNamingHelper.normalizeMac(m) == normMac,
              ))) {
        existingSecKey = rule.sectionKey;
        break;
      }
    }

    final ruleValues = <String, dynamic>{
      'name': ruleName,
      'src': '*',
      'dest': 'wan',
      'src_mac': [normMac],
      'target': 'DROP',
      'enabled': '1',
    };
    if (targetFamily != 'any') {
      ruleValues['family'] = targetFamily;
    }

    if (existingSecKey != null) {
      mutations.add(
        UciRuleMutation(
          type: UciMutationType.set,
          sectionKey: existingSecKey,
          values: ruleValues,
        ),
      );
    } else {
      mutations.add(
        UciRuleMutation(type: UciMutationType.add, values: ruleValues),
      );
    }

    return mutations;
  }
}
