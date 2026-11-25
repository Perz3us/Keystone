// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';

class UrlParser {
  static const int defaultHttpPort = 80;
  static const int defaultHttpsPort = 443;

  static ParsedUrl parse(String input) {
    String cleanInput = input.trim();

    while (cleanInput.endsWith('/')) {
      cleanInput = cleanInput.substring(0, cleanInput.length - 1);
    }

    if (cleanInput.startsWith('http://') || cleanInput.startsWith('https://')) {
      return _parseWithScheme(cleanInput);
    }

    return _parseWithoutScheme(cleanInput);
  }

  static ParsedUrl _parseWithScheme(String input) {
    try {
      final uri = Uri.parse(input);
      final scheme = uri.scheme.toLowerCase();
      final useHttps = scheme == 'https';

      final String host = uri.host;
      int? port = uri.hasPort ? uri.port : null;

      port ??= useHttps ? defaultHttpsPort : defaultHttpPort;

      return ParsedUrl(
        host: host,
        port: port,
        useHttps: useHttps,
        isValid: host.isNotEmpty,
      );
    } catch (e) {
      return ParsedUrl(
        host: '',
        port: defaultHttpPort,
        useHttps: false,
        isValid: false,
        error: 'Invalid URL format',
      );
    }
  }

  static ParsedUrl _parseWithoutScheme(String input) {
    final parts = input.split(':');

    if (parts.length == 1) {
      return ParsedUrl(
        host: parts[0],
        port: defaultHttpPort,
        useHttps: false,
        isValid: _isValidHost(parts[0]),
      );
    } else if (parts.length == 2) {
      final host = parts[0];
      final portStr = parts[1];

      final port = int.tryParse(portStr);
      if (port == null || port < 1 || port > 65535) {
        return ParsedUrl(
          host: '',
          port: defaultHttpPort,
          useHttps: false,
          isValid: false,
          error: 'Invalid port number',
        );
      }

      final useHttps = port == 443 || port == 8443;

      return ParsedUrl(
        host: host,
        port: port,
        useHttps: useHttps,
        isValid: _isValidHost(host),
      );
    } else {
      if (input.contains('[') && input.contains(']')) {
        return _parseIPv6(input);
      }

      final parsedIp = InternetAddress.tryParse(input);
      if (parsedIp != null && parsedIp.type == InternetAddressType.IPv6) {
        return ParsedUrl(
          host: '[$input]',
          port: defaultHttpPort,
          useHttps: false,
          isValid: true,
        );
      }

      return ParsedUrl(
        host: '',
        port: defaultHttpPort,
        useHttps: false,
        isValid: false,
        error: 'Invalid address format',
      );
    }
  }

  static ParsedUrl _parseIPv6(String input) {
    final match = RegExp(r'\[([^\]]+)\](?::(\d+))?').firstMatch(input);
    if (match != null) {
      final host = match.group(1)!;
      final portStr = match.group(2);

      int port = defaultHttpPort;
      bool useHttps = false;

      if (portStr != null) {
        final parsedPort = int.tryParse(portStr);
        if (parsedPort != null && parsedPort >= 1 && parsedPort <= 65535) {
          port = parsedPort;
          useHttps = port == 443 || port == 8443;
        }
      }

      return ParsedUrl(
        host: '[$host]',
        port: port,
        useHttps: useHttps,
        isValid: true,
      );
    }

    return ParsedUrl(
      host: '',
      port: defaultHttpPort,
      useHttps: false,
      isValid: false,
      error: 'Invalid IPv6 address format',
    );
  }

  static bool _isValidHost(String host) {
    if (host.isEmpty) return false;
    return InternetAddress.tryParse(host) != null ||
        Uri.tryParse('http://$host')?.hasAuthority == true;
  }

  static String buildUrl(String host, int port, bool useHttps) {
    final scheme = useHttps ? 'https' : 'http';

    if ((useHttps && port == defaultHttpsPort) ||
        (!useHttps && port == defaultHttpPort)) {
      return '$scheme://$host';
    }

    if (host.startsWith('[') && host.endsWith(']')) {
      return '$scheme://$host:$port';
    }

    return '$scheme://$host:$port';
  }
}

class ParsedUrl {
  final String host;
  final int port;
  final bool useHttps;
  final bool isValid;
  final String? error;

  ParsedUrl({
    required this.host,
    required this.port,
    required this.useHttps,
    required this.isValid,
    this.error,
  });

  String get displayUrl => UrlParser.buildUrl(host, port, useHttps);

  String get hostWithPort {
    if ((useHttps && port == UrlParser.defaultHttpsPort) ||
        (!useHttps && port == UrlParser.defaultHttpPort)) {
      return host;
    }
    return '$host:$port';
  }
}
