import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/services/api_service.dart';

DioException _e(DioExceptionType t) =>
    DioException(requestOptions: RequestOptions(path: '/ubus'), type: t);

void main() {
  test('a call the router got is never sent again', () {
    expect(tryNextEndpoint(_e(DioExceptionType.receiveTimeout)), isFalse);
    expect(tryNextEndpoint(_e(DioExceptionType.sendTimeout)), isFalse);
  });

  test('a router that is not there is not asked twice', () {
    expect(tryNextEndpoint(_e(DioExceptionType.connectionTimeout)), isFalse);
    expect(tryNextEndpoint(_e(DioExceptionType.connectionError)), isFalse);
  });

  test('a broken first address tries the second', () {
    expect(tryNextEndpoint(_e(DioExceptionType.badResponse)), isTrue);
  });
}
