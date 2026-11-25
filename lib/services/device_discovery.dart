// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceKind {
  phone('Phone', Icons.phone_android_rounded),
  tablet('Tablet', Icons.tablet_mac_rounded),
  laptop('Laptop', Icons.laptop_mac_rounded),
  computer('Computer', Icons.desktop_windows_rounded),
  tv('TV or streamer', Icons.tv_rounded),
  console('Game console', Icons.sports_esports_rounded),
  speaker('Speaker', Icons.speaker_rounded),
  printer('Printer', Icons.print_rounded),
  watch('Watch', Icons.watch_rounded),
  camera('Camera', Icons.videocam_rounded),
  smartHome('Smart home', Icons.home_rounded),
  storage('Storage (NAS)', Icons.dns_rounded),
  network('Router or access point', Icons.router_rounded),
  other('Something else', Icons.devices_rounded);

  const DeviceKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

bool _any(String h, List<String> words) => words.any(h.contains);

DeviceKind? kindFromHint(String hint) {
  final h = hint.toLowerCase();
  if (h.isEmpty) return null;
  if (_any(h, ['iphone'])) return DeviceKind.phone;
  if (_any(h, ['ipad'])) return DeviceKind.tablet;
  if (_any(h, ['watch'])) return DeviceKind.watch;
  if (_any(h, ['appletv', 'apple tv'])) return DeviceKind.tv;
  if (_any(h, ['audioaccessory', 'homepod'])) return DeviceKind.speaker;
  if (_any(h, ['macbook'])) return DeviceKind.laptop;
  if (_any(h, ['imac', 'macmini', 'macpro'])) return DeviceKind.computer;
  if (RegExp(r'\bmac\d+,\d+').hasMatch(h)) return DeviceKind.laptop;
  if (_any(h, [
    '_ipp.',
    '_ipps.',
    '_printer.',
    '_pdl-datastream.',
    'printer',
  ])) {
    return DeviceKind.printer;
  }
  if (_any(h, ['xbox', 'playstation', 'ps5', 'ps4', 'nintendo'])) {
    return DeviceKind.console;
  }
  if (_any(h, [
    '_sonos.',
    'sonos',
    'nest mini',
    'nest audio',
    'home mini',
    'google home',
    'echo dot',
    'soundbar',
    'speaker',
  ])) {
    return DeviceKind.speaker;
  }
  if (_any(h, ['microsoft-windows'])) return DeviceKind.computer;
  if (_any(h, [
    '_googlecast.',
    '_androidtvremote',
    '_amzn-wplay.',
    'roku',
    'bravia',
    'webos',
    'tizen',
    'smarttv',
    'smart tv',
    'firetv',
    'fire tv',
    'chromecast',
    'shield',
    'television',
    'mediarenderer',
  ])) {
    return DeviceKind.tv;
  }
  if (_any(h, ['camera', '_axis-video.', 'networkvideotransmitter', 'ipcam'])) {
    return DeviceKind.camera;
  }
  if (_any(h, ['_adisk.', 'synology', 'qnap', 'truenas', 'nas'])) {
    return DeviceKind.storage;
  }
  if (_any(h, ['internetgatewaydevice', 'wlanaccesspoint', 'openwrt'])) {
    return DeviceKind.network;
  }
  if (_any(h, [
    '_hap.',
    '_hue.',
    '_matter',
    'tuya',
    'shelly',
    'tasmota',
    'esphome',
    'homekit',
  ])) {
    return DeviceKind.smartHome;
  }
  if (_any(h, ['android'])) return DeviceKind.phone;
  if (_any(h, [
    '_workstation.',
    '_smb.',
    '_rdp.',
    '_ssh.',
    '_sftp-ssh.',
    'windows',
    'linux',
  ])) {
    return DeviceKind.computer;
  }
  if (_any(h, ['_raop.'])) return DeviceKind.speaker;
  return null;
}

class DeviceKindStore extends ValueNotifier<Map<String, DeviceKind>> {
  DeviceKindStore._() : super(const {});
  static final instance = DeviceKindStore._();
  static const _key = 'device_kinds_v1';

  static String _mac(String mac) => mac.toLowerCase().replaceAll('-', ':');

  DeviceKind? kindOf(String mac) => value[_mac(mac)];

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      final j = raw == null ? null : jsonDecode(raw);
      if (j is! Map) return;
      value = {
        for (final MapEntry(:key, :value) in j.entries)
          '$key': ?DeviceKind.values.asNameMap()[value],
      };
    } catch (_) {}
  }

  Future<void> set(String mac, DeviceKind? kind) async {
    final next = {...value};
    kind == null ? next.remove(_mac(mac)) : next[_mac(mac)] = kind;
    value = next;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode({for (final e in next.entries) e.key: e.value.name}),
      );
    } catch (_) {}
  }
}

class DeviceDiscovery extends ValueNotifier<Map<String, String>> {
  DeviceDiscovery._() : super(const {});
  static final instance = DeviceDiscovery._();

  static const _lock = MethodChannel('com.perz3us.keystone/app_lifecycle');

  static const _services = [
    '_device-info._tcp',
    '_companion-link._tcp',
    '_airplay._tcp',
    '_raop._tcp',
    '_googlecast._tcp',
    '_androidtvremote2._tcp',
    '_amzn-wplay._tcp',
    '_spotify-connect._tcp',
    '_sonos._tcp',
    '_ipp._tcp',
    '_ipps._tcp',
    '_printer._tcp',
    '_pdl-datastream._tcp',
    '_hap._tcp',
    '_hue._tcp',
    '_matter._tcp',
    '_smb._tcp',
    '_adisk._tcp',
    '_workstation._tcp',
    '_ssh._tcp',
    '_rdp._tcp',
    '_axis-video._tcp',
  ];

  DateTime? _last;
  bool _running = false;

  String? hintFor(String ip) => value[ip];

  DeviceKind? kindFor(String ip) => kindFromHint(value[ip] ?? '');

  void maybeScan() {
    if (_running || Platform.environment.containsKey('FLUTTER_TEST')) return;
    final last = _last;
    if (last != null && DateTime.now().difference(last).inMinutes < 3) return;
    _last = DateTime.now();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    _running = true;
    await _lock.invokeMethod('multicastLock', true).catchError((_) => null);
    try {
      final found = <String, Set<String>>{};
      void add(String ip, Iterable<String> words) =>
          (found[ip] ??= {}).addAll(words.map((w) => w.toLowerCase()));
      await Future.wait([
        _mdns(add).catchError((_) {}),
        _ssdp(add).catchError((_) {}),
      ]);
      if (found.isNotEmpty) {
        value = {
          ...value,
          for (final MapEntry(:key, :value) in found.entries)
            key: value.join(' '),
        };
      }
    } finally {
      await _lock.invokeMethod('multicastLock', false).catchError((_) => null);
      _running = false;
    }
  }

  Future<void> _mdns(void Function(String, Iterable<String>) add) async {
    final client = MDnsClient(
      rawDatagramSocketFactory:
          (host, port, {reuseAddress = true, reusePort = false, ttl = 1}) =>
              RawDatagramSocket.bind(host, port, reuseAddress: true, ttl: ttl),
    );
    await client.start();
    try {
      final words = <String, Set<String>>{};
      final ips = <String, Set<String>>{};
      const wait = Duration(seconds: 2);
      await Future.wait([
        for (final service in _services)
          () async {
            await for (final ptr in client.lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('$service.local'),
              timeout: wait,
            )) {
              final instance = ptr.domainName;
              final name = instance.split('._').first;
              (words[name] ??= {}).add('$service.');
              await for (final txt in client.lookup<TxtResourceRecord>(
                ResourceRecordQuery.text(instance),
                timeout: wait,
              )) {
                words[name]!.addAll(txt.text.split('\n'));
              }
              await for (final srv in client.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(instance),
                timeout: wait,
              )) {
                await for (final a in client.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target),
                  timeout: wait,
                )) {
                  (ips[name] ??= {}).add(a.address.address);
                }
              }
            }
          }(),
      ]);
      for (final MapEntry(key: name, value: addrs) in ips.entries) {
        for (final ip in addrs) {
          add(ip, words[name] ?? const {});
        }
      }
    } finally {
      client.stop();
    }
  }

  Future<void> _ssdp(void Function(String, Iterable<String>) add) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final locations = <String, String>{};
    final sub = socket.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = socket.receive();
      if (d == null) return;
      final text = utf8.decode(d.data, allowMalformed: true);
      final head = <String, String>{
        for (final line in const LineSplitter().convert(text))
          if (line.indexOf(':') case final i when i > 0)
            line.substring(0, i).trim().toLowerCase(): line
                .substring(i + 1)
                .trim(),
      };
      final ip = d.address.address;
      add(ip, [?head['server'], ?head['st'], ?head['usn']]);
      if (head['location'] case final l?) locations.putIfAbsent(ip, () => l);
    });
    const search =
        'M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\nMX: 2\r\nST: ssdp:all\r\n\r\n';
    for (var i = 0; i < 2; i++) {
      socket.send(
        utf8.encode(search),
        InternetAddress('239.255.255.250'),
        1900,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    await sub.cancel();
    socket.close();
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      await Future.wait([
        for (final MapEntry(key: ip, value: url) in locations.entries)
          () async {
            final uri = Uri.tryParse(url);
            if (uri == null || uri.host != ip) return;
            final res = await (await http.getUrl(
              uri,
            )).close().timeout(const Duration(seconds: 3));
            final xml = await res.transform(utf8.decoder).join();
            add(ip, [
              for (final tag in [
                'deviceType',
                'friendlyName',
                'manufacturer',
                'modelName',
                'modelDescription',
              ])
                ?RegExp('<$tag>([^<]*)</$tag>').firstMatch(xml)?.group(1),
            ]);
          }().catchError((_) {}),
      ]);
    } finally {
      http.close(force: true);
    }
  }
}
