// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class Logger {
  static const String _tag = 'Keystone';

  static void debug(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 300);
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 800);
    }
  }

  static void warning(String message) {
    if (kDebugMode) {
      developer.log(message, name: _tag, level: 900);
    }
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      developer.log(
        message,
        name: _tag,
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void exception(
    String context,
    Object exception,
    StackTrace stackTrace,
  ) {
    error('$context: $exception', exception, stackTrace);
  }
}
