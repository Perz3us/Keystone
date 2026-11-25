// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'package:flutter/foundation.dart';

@immutable
class AdGuardCredentials {
  final String username;
  final String password;
  final bool useRouterCredentials;
  final DateTime? updatedAt;

  const AdGuardCredentials({
    required this.username,
    required this.password,
    this.useRouterCredentials = false,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'username': username,
    'password': password,
    'useRouterCredentials': useRouterCredentials,
    'updatedAt':
        updatedAt?.toIso8601String() ??
        DateTime.now().toUtc().toIso8601String(),
  };

  factory AdGuardCredentials.fromJson(Map<String, dynamic> json) =>
      AdGuardCredentials(
        username: json['username']?.toString() ?? '',
        password: json['password']?.toString() ?? '',
        useRouterCredentials: json['useRouterCredentials'] == true,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString())
            : null,
      );

  String toBasicAuthHeader() {
    final bytes = utf8.encode('$username:$password');
    return 'Basic ${base64Encode(bytes)}';
  }

  @override
  String toString() =>
      'AdGuardCredentials(username: $username, useRouterCredentials: $useRouterCredentials, password: [REDACTED])';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardCredentials &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          password == other.password &&
          useRouterCredentials == other.useRouterCredentials;

  @override
  int get hashCode => Object.hash(username, password, useRouterCredentials);
}

@immutable
class AdGuardConfig {
  final String? customHost;
  final int customPort;
  final bool useHttps;
  final int pollingIntervalSeconds;

  const AdGuardConfig({
    this.customHost,
    this.customPort = 3000,
    this.useHttps = false,
    this.pollingIntervalSeconds = 10,
  });

  Map<String, dynamic> toJson() => {
    'customHost': customHost,
    'customPort': customPort,
    'useHttps': useHttps,
    'pollingIntervalSeconds': pollingIntervalSeconds,
  };

  factory AdGuardConfig.fromJson(Map<String, dynamic> json) => AdGuardConfig(
    customHost: json['customHost']?.toString(),
    customPort: (json['customPort'] as num?)?.toInt() ?? 3000,
    useHttps: json['useHttps'] == true,
    pollingIntervalSeconds:
        (json['pollingIntervalSeconds'] as num?)?.toInt() ?? 10,
  );

  @override
  String toString() =>
      'AdGuardConfig(customHost: $customHost, customPort: $customPort, useHttps: $useHttps, pollingIntervalSeconds: $pollingIntervalSeconds)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdGuardConfig &&
          runtimeType == other.runtimeType &&
          customHost == other.customHost &&
          customPort == other.customPort &&
          useHttps == other.useHttps &&
          pollingIntervalSeconds == other.pollingIntervalSeconds;

  @override
  int get hashCode =>
      Object.hash(customHost, customPort, useHttps, pollingIntervalSeconds);
}

enum AdGuardApiErrorType {
  networkFailure,

  timeout,

  authRequired,

  httpError,

  invalidPayload,

  malformedJson,

  unsupportedEndpoint,

  rateLimited,

  serviceUnavailable,

  unknown,
}

class AdGuardApiException implements Exception {
  final AdGuardApiErrorType type;
  final String message;
  final int? statusCode;
  final dynamic underlyingError;
  final Duration? retryAfter;

  const AdGuardApiException({
    required this.type,
    required this.message,
    this.statusCode,
    this.underlyingError,
    this.retryAfter,
  });

  @override
  String toString() =>
      'AdGuardApiException(type: $type, statusCode: $statusCode, retryAfter: $retryAfter, message: $message)';
}

@immutable
class AdGuardApiResult<T> {
  final T? data;
  final AdGuardApiException? error;
  final bool isSuccess;

  const AdGuardApiResult._({this.data, this.error, required this.isSuccess});

  factory AdGuardApiResult.success(T data) =>
      AdGuardApiResult._(data: data, isSuccess: true);

  factory AdGuardApiResult.failure(AdGuardApiException error) =>
      AdGuardApiResult._(error: error, isSuccess: false);

  factory AdGuardApiResult.authRequired([
    String message = 'AdGuard Home authentication required',
  ]) => AdGuardApiResult._(
    error: AdGuardApiException(
      type: AdGuardApiErrorType.authRequired,
      statusCode: 401,
      message: message,
    ),
    isSuccess: false,
  );

  bool get isAuthRequired => error?.type == AdGuardApiErrorType.authRequired;

  T get requireData {
    if (isSuccess && data != null) return data!;
    throw error ??
        const AdGuardApiException(
          type: AdGuardApiErrorType.unknown,
          message: 'Operation failed without error detail',
        );
  }
}
