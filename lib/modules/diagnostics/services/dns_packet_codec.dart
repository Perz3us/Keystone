// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:typed_data';

class DnsPacketResponse {
  final int queryId;
  final bool isResponse;
  final int opcode;
  final bool isAuthoritative;
  final bool isTruncated;
  final bool recursionDesired;
  final bool recursionAvailable;
  final int rcode;
  final int questionCount;
  final int answerCount;
  final int authorityCount;
  final int additionalCount;
  final String? errorMessage;

  const DnsPacketResponse({
    required this.queryId,
    required this.isResponse,
    required this.opcode,
    required this.isAuthoritative,
    required this.isTruncated,
    required this.recursionDesired,
    required this.recursionAvailable,
    required this.rcode,
    required this.questionCount,
    required this.answerCount,
    required this.authorityCount,
    required this.additionalCount,
    this.errorMessage,
  });

  bool get isSuccessfulResponse =>
      isResponse && (rcode == 0 || rcode == 3 || rcode == 5);

  String get rcodeDescription {
    switch (rcode) {
      case 0:
        return 'NoError';
      case 1:
        return 'FormatError';
      case 2:
        return 'ServerFailure';
      case 3:
        return 'NameError (NXDOMAIN)';
      case 4:
        return 'NotImplemented';
      case 5:
        return 'Refused (Policy / Filtered)';
      default:
        return 'RCODE $rcode';
    }
  }
}

class DnsPacketCodec {
  const DnsPacketCodec();

  static Uint8List buildQuery(
    String domain,
    int queryId, {
    int qtype = 1,
    int qclass = 1,
  }) {
    final clean = domain.trim().toLowerCase();
    final buffer = BytesBuilder();

    buffer.addByte((queryId >> 8) & 0xff);
    buffer.addByte(queryId & 0xff);

    buffer.addByte(0x01);
    buffer.addByte(0x00);

    buffer.addByte(0x00);
    buffer.addByte(0x01);

    buffer.addByte(0x00);
    buffer.addByte(0x00);

    buffer.addByte(0x00);
    buffer.addByte(0x00);

    buffer.addByte(0x00);
    buffer.addByte(0x00);

    for (final label in clean.split('.')) {
      if (label.isEmpty) continue;
      final bytes = label.codeUnits;
      buffer.addByte(bytes.length & 0xff);
      buffer.add(bytes);
    }
    buffer.addByte(0x00);

    buffer.addByte((qtype >> 8) & 0xff);
    buffer.addByte(qtype & 0xff);

    buffer.addByte((qclass >> 8) & 0xff);
    buffer.addByte(qclass & 0xff);

    return buffer.toBytes();
  }

  static DnsPacketResponse parseResponse(Uint8List data, int expectedQueryId) {
    if (data.length < 12) {
      return const DnsPacketResponse(
        queryId: 0,
        isResponse: false,
        opcode: 0,
        isAuthoritative: false,
        isTruncated: false,
        recursionDesired: false,
        recursionAvailable: false,
        rcode: -1,
        questionCount: 0,
        answerCount: 0,
        authorityCount: 0,
        additionalCount: 0,
        errorMessage: 'Truncated packet: header less than 12 bytes',
      );
    }

    final queryId = (data[0] << 8) | data[1];
    if (queryId != expectedQueryId) {
      return DnsPacketResponse(
        queryId: queryId,
        isResponse: false,
        opcode: 0,
        isAuthoritative: false,
        isTruncated: false,
        recursionDesired: false,
        recursionAvailable: false,
        rcode: -1,
        questionCount: 0,
        answerCount: 0,
        authorityCount: 0,
        additionalCount: 0,
        errorMessage:
            'Query ID mismatch (expected 0x${expectedQueryId.toRadixString(16)}, got 0x${queryId.toRadixString(16)})',
      );
    }

    final flags = (data[2] << 8) | data[3];
    final isResponse = ((flags >> 15) & 0x01) == 1;
    final opcode = (flags >> 11) & 0x0f;
    final isAuthoritative = ((flags >> 10) & 0x01) == 1;
    final isTruncated = ((flags >> 9) & 0x01) == 1;
    final recursionDesired = ((flags >> 8) & 0x01) == 1;
    final recursionAvailable = ((flags >> 7) & 0x01) == 1;
    final rcode = flags & 0x0f;

    final qdcount = (data[4] << 8) | data[5];
    final ancount = (data[6] << 8) | data[7];
    final nscount = (data[8] << 8) | data[9];
    final arcount = (data[10] << 8) | data[11];

    return DnsPacketResponse(
      queryId: queryId,
      isResponse: isResponse,
      opcode: opcode,
      isAuthoritative: isAuthoritative,
      isTruncated: isTruncated,
      recursionDesired: recursionDesired,
      recursionAvailable: recursionAvailable,
      rcode: rcode,
      questionCount: qdcount,
      answerCount: ancount,
      authorityCount: nscount,
      additionalCount: arcount,
    );
  }
}
