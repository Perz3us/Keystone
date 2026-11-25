// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/models/network_access_policy.dart';
import 'package:yet_another_luci_app/utils/client_naming_helper.dart';
import 'package:yet_another_luci_app/utils/logger.dart';

class StoredPolicySchedule {
  final String targetMac;
  final DateTime scheduleExpiry;
  final DateTime createdAt;
  final NetworkAccessPolicy policy;

  const StoredPolicySchedule({
    required this.targetMac,
    required this.scheduleExpiry,
    required this.createdAt,
    required this.policy,
  });

  bool get isExpired => DateTime.now().isAfter(scheduleExpiry);

  Map<String, dynamic> toJson() => {
    'targetMac': ClientNamingHelper.normalizeMac(targetMac),
    'scheduleExpiry': scheduleExpiry.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'policy': policy.toJson(),
  };

  factory StoredPolicySchedule.fromJson(Map<String, dynamic> json) {
    final mac = ClientNamingHelper.normalizeMac(
      json['targetMac']?.toString() ?? '',
    );
    final expiry =
        DateTime.tryParse(json['scheduleExpiry']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final created =
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now();
    final policyMap = json['policy'] is Map
        ? Map<String, dynamic>.from(json['policy'] as Map)
        : <String, dynamic>{'targetMac': mac};
    final policy = NetworkAccessPolicy.fromJson(policyMap);

    return StoredPolicySchedule(
      targetMac: mac,
      scheduleExpiry: expiry,
      createdAt: created,
      policy: policy,
    );
  }
}

class ClientPolicyScheduleService {
  static const String keyPrefix = 'keystone_policy_schedule_';
  static const String _oldKeyPrefix = 'yala_policy_schedule_';

  static ClientPolicyScheduleService? _instance;
  static ClientPolicyScheduleService get instance =>
      _instance ??= ClientPolicyScheduleService._internal();

  ClientPolicyScheduleService._internal();

  final Map<String, StoredPolicySchedule> _cache = {};
  SharedPreferences? _prefs;
  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> init([SharedPreferences? injectedPrefs]) async {
    _cache.clear();
    try {
      _prefs = injectedPrefs ?? await SharedPreferences.getInstance();
      for (final old in _prefs!.getKeys().toList()) {
        if (!old.startsWith(_oldKeyPrefix)) continue;
        final raw = _prefs!.getString(old);
        final key = keyPrefix + old.substring(_oldKeyPrefix.length);
        if (raw != null && !_prefs!.containsKey(key)) {
          await _prefs!.setString(key, raw);
        }
        await _prefs!.remove(old);
      }
      final allKeys = _prefs!.getKeys();
      for (final key in allKeys) {
        if (!key.startsWith(keyPrefix)) continue;
        final raw = _prefs!.getString(key);
        if (raw == null || raw.trim().isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            final record = StoredPolicySchedule.fromJson(decoded);
            if (record.targetMac.isNotEmpty) {
              _cache[record.targetMac] = record;
            }
          }
        } catch (e) {
          Logger.warning('Corrupted policy schedule removed: $key ($e)');
          await _prefs!.remove(key);
        }
      }
      _initialized = true;
    } catch (e) {
      Logger.error('Failed to initialize ClientPolicyScheduleService: $e');
    }
  }

  DateTime? getExpiry(String mac) {
    final normMac = ClientNamingHelper.normalizeMac(mac);
    return _cache[normMac]?.scheduleExpiry;
  }

  StoredPolicySchedule? getSchedule(String mac) {
    final normMac = ClientNamingHelper.normalizeMac(mac);
    return _cache[normMac];
  }

  Future<void> saveSchedule({
    required NetworkAccessPolicy policy,
    SharedPreferences? injectedPrefs,
  }) async {
    final normMac = ClientNamingHelper.normalizeMac(policy.targetMac);
    if (normMac.isEmpty || policy.scheduleExpiry == null) return;

    final record = StoredPolicySchedule(
      targetMac: normMac,
      scheduleExpiry: policy.scheduleExpiry!,
      createdAt: DateTime.now(),
      policy: policy,
    );
    _cache[normMac] = record;

    try {
      final prefs =
          injectedPrefs ?? _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final key = '$keyPrefix$normMac';
      await prefs
          .setString(key, jsonEncode(record.toJson()))
          .timeout(const Duration(milliseconds: 200), onTimeout: () => false);
    } catch (e) {
      Logger.error('Failed to save policy schedule for $normMac: $e');
    }
  }

  Future<void> clearSchedule(
    String mac, {
    SharedPreferences? injectedPrefs,
  }) async {
    final normMac = ClientNamingHelper.normalizeMac(mac);
    _cache.remove(normMac);

    try {
      final prefs =
          injectedPrefs ?? _prefs ?? await SharedPreferences.getInstance();
      _prefs = prefs;
      final key = '$keyPrefix$normMac';
      await prefs
          .remove(key)
          .timeout(const Duration(milliseconds: 200), onTimeout: () => false);
    } catch (e) {
      Logger.error('Failed to clear policy schedule for $normMac: $e');
    }
  }

  List<StoredPolicySchedule> getAllSchedules() {
    return _cache.values.toList();
  }

  List<StoredPolicySchedule> getExpiredSchedules() {
    return _cache.values.where((s) => s.isExpired).toList();
  }

  void clearMemoryCache() {
    _cache.clear();
    _initialized = false;
  }
}
