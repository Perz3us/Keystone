// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/widgets/local_network_permission_dialog.dart';

class LocalNetworkPermissionService {
  static const MethodChannel _channel = MethodChannel(
    'com.perz3us.keystone/local_network_permission',
  );

  static Future<bool> isGranted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'checkLocalNetworkPermission',
      );
      return result ?? true;
    } on PlatformException catch (e) {
      debugPrint('Error checking local network permission: $e');
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> requestPermission() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? granted = await _channel.invokeMethod<bool>(
        'requestLocalNetworkPermission',
      );
      return granted ?? true;
    } on PlatformException catch (e) {
      debugPrint('Error requesting local network permission: $e');
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<bool> openAppSettings() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final bool? result = await _channel.invokeMethod<bool>(
          'openAppSettings',
        );
        return result ?? false;
      } on PlatformException catch (e) {
        debugPrint('Error opening app settings: $e');
        return false;
      } on MissingPluginException {
        return false;
      }
    } else if (Platform.isIOS) {
      try {
        final uri = Uri.parse('app-settings:');
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      } catch (_) {}
    }
    return false;
  }

  static Future<bool> requestWithRationale(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final alreadyGranted = await isGranted();
    if (alreadyGranted) return true;

    if (!context.mounted) return false;

    final proceed = await LocalNetworkPermissionDialog.show(context);
    if (proceed != true) return false;

    final granted = await requestPermission();
    if (granted) return true;

    if (context.mounted) {
      await LocalNetworkPermissionDialog.show(
        context,
        isPermanentlyDenied: true,
      );
    }
    return false;
  }

  static Future<bool> ensurePermissionGranted() async {
    final granted = await isGranted();
    if (!granted) {
      return await requestPermission();
    }
    return true;
  }
}
