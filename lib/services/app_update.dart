// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.url,
    this.notes,
    this.apks = const [],
  });
  final String version;

  final String url;
  final String? notes;
  final List<UpdateApk> apks;
}

@immutable
class UpdateApk {
  const UpdateApk({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
  final String name;
  final String url;
  final int size;
  final String? sha256;
}

// Only the GitHub (community) build installs its own updates; a Play build
// must update through Play.
bool get canSelfUpdate =>
    !kIsWeb && Platform.isAndroid && appFlavor == 'community';

/// The APK built for the phone's preferred ABI, else the universal one.
UpdateApk? pickApk(List<UpdateApk> apks, List<String> abis) {
  for (final abi in [...abis, 'universal']) {
    for (final a in apks) {
      if (a.name.endsWith('-$abi.apk')) return a;
    }
  }
  return null;
}

const _channel = MethodChannel('com.perz3us.keystone/app_lifecycle');

Future<List<String>> deviceAbis() async =>
    (await _channel.invokeListMethod<String>('abis')) ?? const [];

/// Streams the APK into the cache, reporting 0..1 progress. Returns null if
/// [cancelled] turned true.
Future<File?> downloadApk(
  UpdateApk apk,
  void Function(double) onProgress,
  bool Function() cancelled,
) async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final file = File('${dir.path}/${apk.name}');
  final client = http.Client();
  try {
    final res = await client.send(http.Request('GET', Uri.parse(apk.url)));
    if (res.statusCode != 200) throw 'GitHub answered ${res.statusCode}';
    final total = res.contentLength ?? apk.size;
    final sink = file.openWrite();
    var got = 0;
    try {
      await for (final chunk in res.stream) {
        if (cancelled()) return null;
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
    } finally {
      await sink.close();
    }
    if (apk.size > 0 && got != apk.size) throw 'The download was cut short';
    return file;
  } finally {
    client.close();
  }
}

/// Opens Android's installer. The SHA-256 GitHub publishes is checked first.
Future<void> installApk(File file, String? sha256) =>
    _channel.invokeMethod('installApk', {'path': file.path, 'sha256': sha256});

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
            apks: [
              for (final a in (j['assets'] as List? ?? const []))
                if (a is Map && '${a['name']}'.endsWith('.apk'))
                  UpdateApk(
                    name: '${a['name']}',
                    url: '${a['browser_download_url']}',
                    size: (a['size'] as num?)?.toInt() ?? 0,
                    sha256: '${a['digest'] ?? ''}'.startsWith('sha256:')
                        ? '${a['digest']}'.substring(7)
                        : null,
                  ),
            ],
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
