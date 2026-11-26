// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/router.dart';
import '../modules/noobwrt/alerts/alert_models.dart';
import '../modules/noobwrt/alerts/alerts_client.dart';
import '../modules/noobwrt/datacap/data_plan.dart';

typedef FeedPost =
    Future<Map<String, dynamic>?> Function(Map<String, dynamic> params);

class FeedReply extends AlertsPage {
  const FeedReply({
    required super.events,
    required super.trimmed,
    required super.newest,
    required this.settings,
    this.online,
    this.rsrp,
    this.sinr,
    this.bands,
    this.plan,
  });
  final AlertSettings settings;
  final bool? online;
  final int? rsrp;
  final int? sinr;

  final List<String>? bands;
  final SimPlan? plan;
}

final _random = Random.secure();

String _nonce() => [
  for (var i = 0; i < 16; i++)
    _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
].join();

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

Future<FeedReply?> readFeed(FeedPost post, String key, int since) async {
  final nonce = _nonce();
  final r = await post({
    'since': since,
    'nonce': nonce,
    'proof': _sha('$key:q:$nonce:$since:$key'),
  });
  final body = r?['body'], sig = r?['sig'];
  if (body is! String || sig != _sha('$key:a:$nonce:$body:$key')) return null;
  final Object? j;
  try {
    j = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (j is! Map || j['newest'] is! int) return null;
  final page = AlertsPage.from(Map<String, dynamic>.from(j), since);
  final rsrp = j['rsrp'], sinr = j['sinr'], online = j['online'];
  final bands = j['bands'];
  return FeedReply(
    events: page.events,
    trimmed: page.trimmed,
    newest: page.newest,
    settings: AlertSettings.from(j['settings']),
    online: online is bool ? online : null,
    rsrp: rsrp is num ? rsrp.toInt() : null,
    sinr: sinr is num ? sinr.toInt() : null,
    bands: bands is List
        ? [
            for (final b in bands)
              if (b is String && b.isNotEmpty) b,
          ]
        : null,
    plan: SimPlan.from(j['plan']),
  );
}

const _maxReply = 1024 * 1024;

FeedPost httpFeed(Router r) => (params) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 3)
    ..badCertificateCallback = (_, _, _) => true;
  try {
    final base = r.ipAddress.startsWith('http')
        ? r.ipAddress
        : '${r.useHttps ? 'https' : 'http'}://${r.ipAddress}';
    for (final path in const ['/ubus', '/cgi-bin/luci/admin/ubus']) {
      final out = await _post(client, Uri.parse('$base$path'), {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'call',
        'params': ['0' * 32, 'keystone.alerts', 'feed', params],
      }).timeout(const Duration(seconds: 10));
      final result = out is Map ? out['result'] : null;
      if (result is List && result.length > 1 && result[1] is Map) {
        return Map<String, dynamic>.from(result[1] as Map);
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
};

Future<Object?> _post(HttpClient client, Uri url, Object body) async {
  final req = await client.postUrl(url);
  req.followRedirects = false;
  req.headers.contentType = ContentType.json;
  req.write(jsonEncode(body));
  final res = await req.close();
  if (res.statusCode != 200) return null;
  final bytes = <int>[];
  await for (final chunk in res) {
    bytes.addAll(chunk);
    if (bytes.length > _maxReply) return null;
  }
  try {
    return jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return null;
  }
}
