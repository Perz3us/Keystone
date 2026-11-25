// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'logger.dart';
import 'sha256.dart';

class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;
  Future<void>? _initFuture;

  Future<void> ensureInitialized() {
    _initFuture ??= _loadAcceptedCertificates();
    return _initFuture!;
  }

  HttpClientManager._internal() {
    ensureInitialized();
  }

  final Map<String, Dio> _clients = {};

  final Map<String, String> _acceptedCertFingerprints = {};

  static const String _acceptedCertsKey = 'accepted_certificates';

  String _cacheKey(String hostWithPort, bool useHttps) =>
      '$hostWithPort-$useHttps';

  Dio getClient(String hostWithPort, bool useHttps, {BuildContext? context}) {
    final key = _cacheKey(hostWithPort, useHttps);
    if (_clients.containsKey(key)) {
      return _clients[key]!;
    }

    final host = _extractHostname(hostWithPort);
    final client = _createSecureClient(
      host,
      hostWithPort,
      useHttps,
      context: context,
    );
    _clients[key] = client;
    return client;
  }

  String _extractHostname(String hostWithPort) {
    if (hostWithPort.startsWith('[')) {
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1) {
        return hostWithPort.substring(0, endBracket + 1);
      }
    } else {
      final colonIndex = hostWithPort.lastIndexOf(':');
      if (colonIndex != -1) {
        final portPart = hostWithPort.substring(colonIndex + 1);
        if (int.tryParse(portPart) != null) {
          return hostWithPort.substring(0, colonIndex);
        }
      }
    }
    return hostWithPort;
  }

  int _extractPort(String hostWithPort) {
    if (hostWithPort.startsWith('[')) {
      final closeBracket = hostWithPort.indexOf(']');
      if (closeBracket != -1 && closeBracket + 1 < hostWithPort.length) {
        final rest = hostWithPort.substring(closeBracket + 1);
        if (rest.startsWith(':')) {
          return int.tryParse(rest.substring(1)) ?? 443;
        }
      }
    } else {
      final colonIndex = hostWithPort.lastIndexOf(':');
      if (colonIndex != -1) {
        final portPart = hostWithPort.substring(colonIndex + 1);
        final port = int.tryParse(portPart);
        if (port != null) return port;
      }
    }
    return 443;
  }

  static String _certFingerprint(X509Certificate cert) {
    return Sha256.hex(cert.der);
  }

  Dio _createSecureClient(
    String host,
    String hostWithPort,
    bool useHttps, {
    BuildContext? context,
  }) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          Logger.error(
            'HTTP ${e.requestOptions.method} ${e.requestOptions.uri} failed',
            e,
            e.stackTrace,
          );

          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.connectionError ||
              e.error is SocketException) {
            Logger.info(
              'Network transition or socket failure detected for $host. Evicting stale client.',
            );
            disposeClient(hostWithPort, useHttps, forceCloseAdapter: false);
          }

          handler.next(e);
        },
      ),
    );

    final adapter = IOHttpClientAdapter();
    adapter.createHttpClient = () => newHttpClient(hostWithPort);
    dio.httpClientAdapter = adapter;

    return dio;
  }

  HttpClient newHttpClient(String hostWithPort) {
    final host = _extractHostname(hostWithPort);
    final httpClient = HttpClient();
    httpClient.connectionTimeout = const Duration(seconds: 15);
    httpClient.badCertificateCallback = (cert, certHost, port) {
      if (_isLocalOrPrivateHost(certHost) || _isLocalOrPrivateHost(host)) {
        return true;
      }

      final certKey = '$certHost:$port';
      final storedFingerprint = _acceptedCertFingerprints[certKey];
      if (storedFingerprint != null) {
        final presentedFingerprint = _certFingerprint(cert);
        if (presentedFingerprint == storedFingerprint) {
          return true;
        }
        Logger.warning(
          'Certificate fingerprint mismatch for $certKey. '
          'Stored: $storedFingerprint, Presented: $presentedFingerprint',
        );
        _acceptedCertFingerprints.remove(certKey);
      }

      return false;
    };
    return httpClient;
  }

  static bool _isLocalOrPrivateHost(String host) {
    if (host.isEmpty) return false;
    var lowerHost = host.toLowerCase().trim();
    if (lowerHost.startsWith('[') && lowerHost.endsWith(']')) {
      lowerHost = lowerHost.substring(1, lowerHost.length - 1).trim();
    }

    if (lowerHost == 'localhost' ||
        lowerHost == 'openwrt' ||
        lowerHost.endsWith('.local') ||
        lowerHost.endsWith('.lan')) {
      return true;
    }

    try {
      final parts = host.split('.');
      if (parts.length == 4) {
        final octets = parts.map(int.tryParse).toList();
        if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
          final o0 = octets[0]!;
          final o1 = octets[1]!;

          if (o0 == 127) return true;
          if (o0 == 10) return true;
          if (o0 == 172 && o1 >= 16 && o1 <= 31) return true;
          if (o0 == 192 && o1 == 168) return true;
          if (o0 == 169 && o1 == 254) return true;
        }
      }
    } catch (_) {}

    if (host.contains(':')) {
      if (lowerHost == '::1' ||
          lowerHost.startsWith('fe80:') ||
          lowerHost.startsWith('fc00:') ||
          lowerHost.startsWith('fd00:')) {
        return true;
      }
    }

    return false;
  }

  Future<void> _loadAcceptedCertificates() async {
    try {
      const storage = FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      if (certsJson != null) {
        final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
        _acceptedCertFingerprints.clear();
        certs.forEach((key, value) {
          if (value is String && value.isNotEmpty) {
            _acceptedCertFingerprints[key] = value;
          }
        });
      }
    } catch (e) {
      Logger.warning('Error loading accepted certificate fingerprints: $e');
    }
  }

  Future<void> _saveAcceptedCertificates() async {
    try {
      const storage = FlutterSecureStorage();
      await storage.write(
        key: _acceptedCertsKey,
        value: jsonEncode(_acceptedCertFingerprints),
      );
    } catch (e) {
      Logger.warning('Error saving accepted certificate fingerprints: $e');
    }
  }

  void disposeClient(
    String hostWithPort,
    bool useHttps, {
    bool forceCloseAdapter = false,
  }) {
    final hostname = _extractHostname(hostWithPort);

    final exactKeys = [
      _cacheKey(hostWithPort, useHttps),
      _cacheKey(hostname, useHttps),
    ];

    final keysToRemove = _clients.keys
        .where((k) => exactKeys.contains(k))
        .toList();

    for (final key in keysToRemove) {
      final dio = _clients.remove(key);
      if (forceCloseAdapter) {
        final adapter = dio?.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
  }

  void disposeAll({bool forceCloseAdapter = false}) {
    for (final dio in _clients.values) {
      if (forceCloseAdapter) {
        final adapter = dio.httpClientAdapter;
        if (adapter is IOHttpClientAdapter) {
          adapter.close(force: true);
        }
      }
    }
    _clients.clear();
  }

  Future<void> clearAcceptedCertificates() async {
    _acceptedCertFingerprints.clear();

    disposeAll(forceCloseAdapter: true);

    try {
      const storage = FlutterSecureStorage();
      await storage.delete(key: _acceptedCertsKey);
    } catch (e) {
      Logger.warning('Error clearing accepted certificates: $e');
    }
  }

  Future<void> clearCertificatesForHost(String host) async {
    final hostname = _extractHostname(host);

    _acceptedCertFingerprints.removeWhere(
      (key, _) => key == hostname || key.startsWith('$hostname:'),
    );

    final keysToRemove = _clients.keys.where((key) {
      final lastDash = key.lastIndexOf('-');
      if (lastDash == -1) return false;
      final keyHost = key.substring(0, lastDash);
      final keyHostname = _extractHostname(keyHost);
      return keyHostname == hostname;
    }).toList();

    for (final key in keysToRemove) {
      _clients[key]?.close();
      _clients.remove(key);
    }

    await _saveAcceptedCertificates();
  }

  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String hostWithPort,
    required bool useHttps,
  }) async {
    if (!useHttps) return true;
    if (!context.mounted) return false;

    final host = _extractHostname(hostWithPort);
    final port = _extractPort(hostWithPort);

    final certKey = '$host:$port';

    if (_acceptedCertFingerprints.containsKey(certKey)) return true;

    if (_isLocalOrPrivateHost(host)) return true;

    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 15);

    X509Certificate? presentedCert;
    String? presentedFingerprint;

    testClient.badCertificateCallback = (cert, certHost, certPort) {
      presentedCert = cert;
      presentedFingerprint = _certFingerprint(cert);
      return false;
    };

    try {
      final uri = Uri.parse('https://$hostWithPort');
      final request = await testClient.getUrl(uri);
      await request.close();
      return true;
    } catch (e) {
      if (e is HandshakeException && presentedCert != null && context.mounted) {
        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) => CertificateWarningDialog(
            certificate: presentedCert!,
            fingerprint: presentedFingerprint ?? '',
            host: host,
            port: port,
          ),
        );

        if (result == true && presentedFingerprint != null) {
          _acceptedCertFingerprints[certKey] = presentedFingerprint!;
          await _saveAcceptedCertificates();
          disposeClient(hostWithPort, useHttps, forceCloseAdapter: true);
          return true;
        }
      }
    } finally {
      testClient.close();
    }

    return false;
  }
}

class CertificateWarningDialog extends StatelessWidget {
  final X509Certificate certificate;
  final String fingerprint;
  final String host;
  final int port;

  const CertificateWarningDialog({
    super.key,
    required this.certificate,
    required this.fingerprint,
    required this.host,
    required this.port,
  });

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    String day(DateTime d) =>
        MaterialLocalizations.of(context).formatMediumDate(d.toLocal());
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: KeystoneType.caption(ks.mu)),
          SelectableText(value, style: KeystoneType.secondary(ks.tx)),
        ],
      ),
    );
    return AlertDialog(
      backgroundColor: ks.sheet,
      title: Text('Trust this router?', style: KeystoneType.sheetTitle(ks.tx)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$host:$port uses a certificate your phone doesn\'t know. '
              'Routers often make their own, which is normal. Only trust it '
              'if this is your router.',
              style: KeystoneType.body(ks.tx2),
            ),
            line('Made for', certificate.subject),
            line('Made by', certificate.issuer),
            line(
              'Good from',
              '${day(certificate.startValidity)} to '
                  '${day(certificate.endValidity)}',
            ),
            if (fingerprint.isNotEmpty) line('Fingerprint', fingerprint),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: KeystoneType.body(ks.tx)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('Trust it', style: KeystoneType.body(ks.bad)),
        ),
      ],
    );
  }
}
