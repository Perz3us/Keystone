import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/models/router.dart' as model;
import 'package:yet_another_luci_app/services/interfaces/api_service_interface.dart';
import 'package:yet_another_luci_app/services/interfaces/auth_service_interface.dart';
import 'package:yet_another_luci_app/services/router_service.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/controllers/session_controller.dart';
import 'package:yet_another_luci_app/utils/http_client_manager.dart';
import 'package:yet_another_luci_app/utils/router_support.dart';

class _Routers implements RouterService {
  final list = <model.Router>[];

  @override
  List<model.Router> get routers => list;
  @override
  model.Router? get selectedRouter => list.firstOrNull;
  @override
  model.Router createRouter(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    String? name,
    String? lastKnownHostname,
  }) => model.Router(
    id: RouterService.generateId(ip, user, useHttps),
    ipAddress: ip,
    username: user,
    password: pass,
    useHttps: useHttps,
    name: name,
    lastKnownHostname: lastKnownHostname,
  );
  @override
  Future<void> addRouter(model.Router router) async => list.add(router);
  @override
  Future<void> updateRouter(model.Router router, {String? oldId}) async {
    final i = list.indexWhere((r) => r.id == (oldId ?? router.id));
    if (i != -1) list[i] = router;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements IAuthService {
  _Auth({this.accept = true, this.throwThis});
  final bool accept;
  final Object? throwThis;
  bool _authed = false;

  @override
  bool get isAuthenticated => _authed;
  @override
  String? get sysauth => _authed ? 'sid' : null;
  @override
  bool get useHttps => false;
  @override
  Future<void> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    dynamic context,
  }) async {
    if (throwThis != null) throw throwThis!;
    _authed = accept;
  }

  @override
  Future<void> logout() async => _authed = false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Api implements IApiService {
  _Api(this.board);
  final dynamic board;

  @override
  Future<dynamic> call(
    String ipAddress,
    String sysauth,
    bool useHttps, {
    required String object,
    required String method,
    Map<String, dynamic>? params,
    dynamic context,
  }) async => board;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _openWrtBoard = [
  0,
  {
    'model': 'Arcadyan AW1000',
    'hostname': 'NoobWRT',
    'release': {'distribution': 'OpenWrt'},
  },
];

SessionController _session(_Routers r, _Auth a, _Api api) => SessionController(
  initialReviewerMode: false,
  apiServiceRef: () => api,
  authServiceRef: () => a,
  routerServiceRef: () => r,
  secureStorageServiceRef: () => SecureStorageService(),
  httpClientManagerRef: () => HttpClientManager(),
  dashboardControllerRef: () => null,
  cancelThroughputTimer: () {},
  startThroughputTimer: () {},
  fetchDashboardData: ({bool force = false}) async {},
  initializeServices: () {},
  setLoadingState: (_) {},
  setErrorState: (_) {},
  notifyListeners: () {},
);

void main() {
  test('a rejected password is a wrong password', () async {
    final s = _session(_Routers(), _Auth(accept: false), _Api(_openWrtBoard));
    expect(await s.login('192.168.1.1', 'root', 'x', false), isFalse);
    expect(s.lastLoginFailure, LoginFailure.wrongPassword);
  });

  test('nothing answering is unreachable', () async {
    final s = _session(
      _Routers(),
      _Auth(throwThis: const RouterUnreachableException('192.168.1.1')),
      _Api(_openWrtBoard),
    );
    expect(await s.login('192.168.1.1', 'root', '', false), isFalse);
    expect(s.lastLoginFailure, LoginFailure.unreachable);
  });

  test('a device that is not OpenWrt is told apart', () async {
    final s = _session(
      _Routers(),
      _Auth(),
      _Api([
        0,
        {'model': 'Some camera'},
      ]),
    );
    expect(await s.login('192.168.1.1', 'root', '', false), isFalse);
    expect(s.lastLoginFailure, LoginFailure.notOpenWrt);
  });

  test('success clears the failure and remembers the model', () async {
    final routers = _Routers();
    final s = _session(routers, _Auth(), _Api(_openWrtBoard));
    expect(await s.login('192.168.1.1', 'root', '', false), isTrue);
    expect(s.lastLoginFailure, LoginFailure.none);
    expect(routers.list.single.lastKnownModel, 'Arcadyan AW1000');
  });

  test('the model survives saving, and old profiles still load', () {
    final r = model.Router(
      id: 'a',
      ipAddress: '192.168.1.1',
      username: 'root',
      password: '',
      useHttps: false,
      lastKnownModel: 'Arcadyan AW1000',
    );
    expect(model.Router.fromJson(r.toJson()).lastKnownModel, 'Arcadyan AW1000');
    expect(
      model.Router.fromJson({
        'id': 'b',
        'ipAddress': '10.0.0.1',
      }).lastKnownModel,
      isNull,
    );
    expect(r.copyWith(name: 'Home').lastKnownModel, 'Arcadyan AW1000');
  });
}
