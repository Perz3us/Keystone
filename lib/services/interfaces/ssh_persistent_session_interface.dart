// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'ssh_service_interface.dart';

enum SshSessionStatus {
  disconnected,
  connecting,
  connected,
  authFailed,
  connectionFailed,
}

class SshConnectResult {
  final SshSessionStatus status;
  final SshTransportErrorType? errorType;
  final String? errorMessage;

  const SshConnectResult({
    required this.status,
    this.errorType,
    this.errorMessage,
  });
}

abstract class ISshPersistentSession {
  Stream<String> get outputStream;

  SshSessionStatus get status;

  Future<SshConnectResult> connect({
    required String host,
    required String username,
    required String password,
    int port = 22,
    Duration connectTimeout = const Duration(seconds: 15),
  });

  void sendInput(String input);

  void sendBytes(List<int> bytes);

  void sendCtrlC() => sendBytes([3]);

  void sendCtrlZ() => sendBytes([0x1A]);

  void sendArrowUp() => sendBytes([0x1B, 0x5B, 0x41]);
  void sendArrowDown() => sendBytes([0x1B, 0x5B, 0x42]);
  void sendArrowRight() => sendBytes([0x1B, 0x5B, 0x43]);
  void sendArrowLeft() => sendBytes([0x1B, 0x5B, 0x44]);

  void sendNewline() => sendBytes([0x0D]);

  void sendRaw(String text);

  void sendBackspace() => sendBytes([0x7F]);

  void sendTab() => sendBytes([0x09]);

  void sendEscape() => sendBytes([0x1B]);

  void resizeTerminal(int width, int height);

  Future<void> disconnect();

  bool get isConnected;
}
