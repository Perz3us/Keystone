import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/screens/devices/devices_view.dart';
import 'package:yet_another_luci_app/screens/home/home_view.dart';
import 'package:yet_another_luci_app/screens/main_screen.dart';
import 'package:yet_another_luci_app/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  SharedPreferences.setMockInitialValues({});

  setUp(() async {
    final app = AppState.instance;
    await app.setReviewerMode(true);
    app.markReviewerNoticeShown();
  });

  Future<void> pump(WidgetTester t, {int tab = 0}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: MainScreen(initialTab: tab)),
      ),
    );
    await t.pump(const Duration(seconds: 2));
  }

  Finder dock(String label) => find.bySemanticsLabel(RegExp('^$label, tab'));

  testWidgets('four tabs: Home, Devices, Wi-Fi, More', (t) async {
    await pump(t);
    expect(dock('Home'), findsOneWidget);
    expect(dock('Devices'), findsOneWidget);
    expect(dock('Wi-Fi'), findsOneWidget);
    expect(dock('More'), findsOneWidget);
    expect(dock('Network'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('tab 4 of 4')), findsOneWidget);
  });

  testWidgets('Home is the new Home', (t) async {
    await pump(t);
    expect(find.byType(HomeView), findsOneWidget);
  });

  testWidgets('Network lives in More', (t) async {
    await pump(t, tab: 4);
    await t.scrollUntilVisible(
      find.text('Network'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Network'), findsOneWidget);
  });

  testWidgets('swipe left and right moves between tabs', (t) async {
    await pump(t);
    await t.fling(find.byType(HomeView), const Offset(-300, 0), 1500);
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(DevicesView), findsOneWidget);
    expect(find.byType(HomeView), findsNothing);
    await t.fling(find.byType(DevicesView), const Offset(300, 0), 1500);
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(HomeView), findsOneWidget);
  });
}
