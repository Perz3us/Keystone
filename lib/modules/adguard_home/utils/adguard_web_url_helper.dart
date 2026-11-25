// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:url_launcher/url_launcher.dart';

class AdGuardWebUrlHelper {
  AdGuardWebUrlHelper._();

  static String formatHost(String host) {
    final trimmed = host.trim();
    if (trimmed.isEmpty) return '127.0.0.1';
    if (trimmed.contains(':') && !trimmed.startsWith('[')) {
      return '[$trimmed]';
    }
    return trimmed;
  }

  static String buildWebUrl({
    required String host,
    required int port,
    bool useHttps = false,
  }) {
    final formattedHost = formatHost(host);
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$formattedHost:$port';
  }

  static Future<bool> launchWebInterface({
    required BuildContext context,
    required bool isReviewerMode,
    required String host,
    required int port,
    bool useHttps = false,
  }) async {
    if (isReviewerMode) {
      if (context.mounted) {
        ksSay(context, 'The demo has no AdGuard Home page to open.');
      }
      return false;
    }

    final urlString = buildWebUrl(host: host, port: port, useHttps: useHttps);
    final uri = Uri.tryParse(urlString);
    if (uri != null && await canLaunchUrl(uri)) {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
