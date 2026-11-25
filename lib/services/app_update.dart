// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppUpdate {
  const AppUpdate({required this.version, required this.url, this.notes});
  final String version;

  final String url;
  final String? notes;
}

bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[+_~-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest), b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  final p = _preRelease.firstMatch(latest), q = _preRelease.firstMatch(current);
  if (p == null || q == null) return p == null && q != null;
  final stage = p[1]!.compareTo(q[1]!);
  if (stage != 0) return stage > 0;
  return (int.tryParse(p[2]!) ?? 0) > (int.tryParse(q[2]!) ?? 0);
}

final _preRelease = RegExp(r'[-_~](alpha|beta|pre|rc)\.?(\d*)');

bool isPreRelease(String v) => _preRelease.hasMatch(v);

class AppUpdateChecker {
  AppUpdateChecker._();
  static final instance = AppUpdateChecker._();

  static const _latest =
      'https://api.github.com/repos/Perz3us/Keystone/releases/latest';
  static const _lastKey = 'app_update_last_check';
  static const _foundKey = 'app_update_found';

  final available = ValueNotifier<AppUpdate?>(null);

  Future<AppUpdate?> check() async {
    final res = await http
        .get(
          Uri.parse(_latest),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) return available.value = null;
    if (res.statusCode != 200) throw 'GitHub answered ${res.statusCode}';
    final j = jsonDecode(res.body);
    final tag = j is Map ? j['tag_name']?.toString() : null;
    if (tag == null) return available.value = null;
    final current = (await PackageInfo.fromPlatform()).version;
    return available.value = isNewerVersion(tag, current)
        ? AppUpdate(
            version: tag.replaceFirst(RegExp(r'^v'), ''),
            url:
                j['html_url']?.toString() ??
                'https://github.com/Perz3us/Keystone/releases/latest',
            notes: (j['body'] as String?)?.trim(),
          )
        : null;
  }

  Future<void> checkDaily() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last < const Duration(hours: 24).inMilliseconds) {
        final saved = prefs.getStringList(_foundKey);
        if (saved != null && saved.length == 2) {
          final current = (await PackageInfo.fromPlatform()).version;
          if (isNewerVersion(saved[0], current)) {
            available.value = AppUpdate(version: saved[0], url: saved[1]);
          }
        }
        return;
      }
      final u = await check();
      await prefs.setInt(_lastKey, now);
      if (u == null) {
        await prefs.remove(_foundKey);
      } else {
        await prefs.setStringList(_foundKey, [u.version, u.url]);
      }
    } catch (_) {}
  }
}
