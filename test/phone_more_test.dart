// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/modules/noobwrt/phone/phone_more.dart';

void main() {
  test('phone error codes read as sentences', () {
    expect(phoneError(const NoobRpcError('refused')), contains('network'));
    expect(phoneError(const NoobRpcError('exists')), contains('already'));
    expect(
      phoneError(const NoobRpcError('Permission denied')),
      'Permission denied',
    );
  });
}
