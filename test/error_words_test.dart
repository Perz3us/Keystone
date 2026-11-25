import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/utils/error_words.dart';

void main() {
  test('errorWords turns raw errors into plain sentences', () {
    expect(
      errorWords(Exception('SocketException: Connection refused')),
      'Couldn\'t reach the router. Check you\'re on its Wi-Fi.',
    );
    expect(errorWords('HTTP 401'), 'You were signed out. Sign in again.');
    expect(
      errorWords('Access denied by ACL'),
      'The router didn\'t allow that for this account.',
    );
    expect(
      errorWords('Request timed out'),
      'The router took too long. It may be busy.',
    );
    expect(errorWords(null), 'Something went wrong. Try again.');
    expect(errorWords(StateError('#0 stack')), isNot(contains('#0')));
  });
}
