// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/background/alerts_store.dart';
import 'package:yet_another_luci_app/background/background_check.dart';
import 'package:yet_another_luci_app/background/notifier.dart' as notes;
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/services/secure_storage_service.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../history/helper_installer.dart';
import '../noob_rpc.dart';
import 'alert_models.dart';
import 'alert_settings_screen.dart';
import 'alerts_client.dart';

class AlertsPhone {
  const AlertsPhone({
    required this.store,
    required this.routerId,
    required this.readKey,
    required this.writeKey,
    required this.interval,
    required this.setInterval,
    required this.notificationsAllowed,
    required this.askForNotifications,
    required this.openNotificationSettings,
  });

  final AlertsStore store;
  final String routerId;
  final Future<String?> Function() readKey;
  final Future<void> Function(String key) writeKey;
  final Future<Duration?> Function() interval;
  final Future<void> Function(Duration? d) setInterval;
  final Future<bool> Function() notificationsAllowed;
  final Future<bool> Function() askForNotifications;
  final Future<void> Function() openNotificationSettings;

  static Future<AlertsPhone> of(AppState app) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final secure = SecureStorageService();
    final id = app.selectedRouter?.id ?? '';
    final bg = BackgroundPrefs(prefs);
    return AlertsPhone(
      store: AlertsStore(prefs),
      routerId: id,
      readKey: () => secure.readValue(alertsKeyName(id)),
      writeKey: (k) => secure.writeValue(alertsKeyName(id), k),
      interval: () async => bg.interval,
      setInterval: (d) async {
        await bg.setInterval(d);
        await startBackground(changed: true);
      },
      notificationsAllowed: notes.notificationsAllowed,
      askForNotifications: notes.askForNotifications,
      openNotificationSettings: () => const MethodChannel(
        'com.perz3us.keystone/app_lifecycle',
      ).invokeMethod<void>('openNotificationSettings'),
    );
  }

  Future<void> pairIfNeeded(AlertsClient c, String routerKeyId) async {
    final have = await readKey();
    if (have != null && keyId(have) == routerKeyId) return;
    await writeKey(await c.pair());
  }
}

Future<void> openAlerts(BuildContext context, AppState app) async {
  final phone = await AlertsPhone.of(app);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlertsScreen(
        client: AlertsClient.of(app),
        phone: phone,
        install: HelperInstaller(app, package: 'keystone-alerts').install,
      ),
    ),
  );
}

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({
    super.key,
    required this.client,
    required this.phone,
    required this.install,
  });

  final AlertsClient client;
  final AlertsPhone phone;
  final Future<void> Function() install;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  AlertsInfo? _info;
  bool _loading = true, _missing = false, _offline = false, _outages = false;
  bool _installing = false;
  String? _error;
  List<AlertEvent> _events = const [];
  bool _trimmed = false;

  AlertsStore get _store => widget.phone.store;
  String get _id => widget.phone.routerId;

  @override
  void initState() {
    super.initState();
    _events = _store.events(_id);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await widget.client.info();
      if (info == null) {
        _missing = true;
      } else {
        _missing = _offline = false;
        _info = info;
        final got = await collectSince(widget.client, 0);
        await _store.clearEvents(_id);
        await _store.saveEvents(_id, got.events);
        await _store.setLastId(_id, got.newest);
        _trimmed = got.trimmed || _store.trimmed(_id);
        await _store.setTrimmed(_id, false);
        _events = _store.events(_id);
        if (await widget.phone.readKey() != null) {
          await widget.phone.pairIfNeeded(widget.client, info.keyId);
        }
      }
    } catch (_) {
      _offline = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await widget.install();
    } catch (e) {
      _error = e is NoobRpcError
          ? e.message
          : "Couldn't reach the router. Check you're on its Wi-Fi.";
    }
    if (!mounted) return;
    setState(() => _installing = false);
    if (_error == null) await _load();
  }

  Future<void> _settings() async {
    final info = _info;
    if (info == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AlertSettingsScreen(
          client: widget.client,
          phone: widget.phone,
          settings: info.settings,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    if (_missing) return _installPage(ks);
    final shown = [
      for (final e in _events)
        if (!_outages || e.type == AlertType.internet) e,
    ];
    return KsPage(
      title: 'Alerts',
      subtitle: 'What happened on the router, newest first',
      onRefresh: _load,
      actions: [
        if (_info != null)
          IconButton(
            tooltip: 'Alert settings',
            onPressed: _settings,
            icon: Icon(Icons.tune_rounded, color: ks.mu),
          ),
      ],
      children: [
        if (_loading && _events.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_offline)
          const KsBanner(
            "Can't reach the router. Showing what this phone already has.",
          ),
        if (_trimmed)
          const KsBanner(
            'Older events were removed before this phone could collect them',
          ),
        const SizedBox(height: 12),
        KsChips<bool>(
          options: const [(false, 'All'), (true, 'Outages')],
          selected: _outages,
          onSelected: (v) => setState(() => _outages = v),
        ),
        const SizedBox(height: 4),
        if (shown.isEmpty && !_loading)
          KsNote(_outages ? 'No outages' : 'Nothing has happened yet'),
        for (final e in shown) _EventRow(e),
      ],
    );
  }

  Widget _installPage(KeystoneColors ks) => KsPage(
    title: 'Alerts',
    children: [
      Text('Get alerts from your router', style: KeystoneType.title(ks.tx)),
      const SizedBox(height: 8),
      Text(
        'A small service on the router watches for outages, weak signal, new '
        'devices and data use, and keeps a log for this app. It also installs '
        'signal history if it is not there yet.',
        style: KeystoneType.body(ks.tx2),
      ),
      if (_error != null) KsBanner(_error!, bad: true),
      const SizedBox(height: 20),
      if (_installing)
        const LinearProgressIndicator(minHeight: 2)
      else
        FilledButton(onPressed: _install, child: const Text('Install')),
    ],
  );
}

String clockWords(
  DateTime t,
  DateTime now, {
  String Function(DateTime)? clock,
}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = clock?.call(t) ?? '${two(t.hour)}:${two(t.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${t.day} ${m[t.month - 1]} $time';
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e);
  final AlertEvent e;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final start = e.start;
    final drops = e.detail['drops'];
    final when = start == null
        ? null
        : '${e.approx ? 'about ' : ''}${clockWords(start, DateTime.now(), clock: (d) => TimeOfDay.fromDateTime(d).format(context))}';
    final tone = switch (e.type) {
      AlertType.internet => e.end == null ? ks.bad : ks.warn,
      AlertType.signal => ks.warn,
      AlertType.data => ks.warn,
      AlertType.device || AlertType.restart => ks.mu,
    };
    return KsRow(
      leading: KsDot(tone),
      title: alertTitle(e),
      subtitle: [
        ?when,
        if (drops is int && drops > 1) 'dropped $drops times',
      ].join(' · '),
    );
  }
}
