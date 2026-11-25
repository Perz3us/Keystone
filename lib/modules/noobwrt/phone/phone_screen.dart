// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yet_another_luci_app/main.dart';

import '../noob_rpc.dart';
import '../noob_widgets.dart';
import 'call_log.dart';
import 'phone_more.dart';

const phoneStateLabels = {
  'idle': 'Idle',
  'dialtone': 'Off hook',
  'digits': 'Dialling',
  'calling': 'Calling',
  'talking': 'In call',
  'ringing': 'Ringing',
  'busy': 'Busy',
};

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  int _tab = 0;
  Timer? _timer;
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _versions;
  List<PhoneCall> _calls = const [];
  List<Map<String, dynamic>> _sms = const [];
  bool _smsModem = false;
  bool _hasVoice = false;
  Map<String, dynamic>? _sip;
  String? _error;
  bool _loading = true;

  Future<Map<String, dynamic>> _call(
    String obj,
    String method, [
    Map<String, dynamic>? p,
  ]) => noobCall(ref.read(appStateProvider), obj, method, p);

  @override
  void initState() {
    super.initState();
    _loadAll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final s = await _call('fxs', 'status');
      if (!mounted) return;
      final changed = s['state'] != _status?['state'];
      setState(() {
        _status = s;
        _error = null;
        _loading = false;
      });
      if (changed) unawaited(_loadCalls());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadCalls() async {
    try {
      final h = await _call('fxs', 'history');
      final live = (_status?['state'] ?? 'idle') != 'idle';
      if (mounted) {
        setState(
          () => _calls = parseCallLog(h['log']?.toString() ?? '', live: live),
        );
      }
    } catch (_) {}
  }

  Future<void> _loadSms() async {
    try {
      final r = await _call('aw1000-voice', 'sms_list');
      final list = r['messages'];
      if (!mounted) return;
      setState(() {
        _hasVoice = true;
        _smsModem = r['modem'] == true;
        _sms = [
          if (list is List)
            for (final m in list)
              if (m is Map) Map<String, dynamic>.from(m),
        ]..sort((a, b) => ((b['time'] ?? 0) as num).compareTo(a['time'] ?? 0));
      });
    } catch (_) {
      if (mounted) setState(() => _hasVoice = false);
    }
  }

  Future<void> _loadAll() async {
    await _loadStatus();
    try {
      final v = await _call('fxs', 'version');
      if (mounted) setState(() => _versions = v);
    } catch (_) {}
    await Future.wait([_loadCalls(), _loadSms(), _loadSip()]);
  }

  Future<void> _act(
    String obj,
    String method,
    Map<String, dynamic> p,
    String done,
  ) async {
    try {
      await _call(obj, method, p);
      if (mounted) ksSay(context, done);
      await _loadStatus();
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Back', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(top: false, child: _status == null ? _missing() : _tabs()),
    );
  }

  Widget _missing() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return NoobProblem(
      title: 'Phone port not found',
      detail:
          'The phone screen needs fxsd and aw1000-voice on the router. '
          'Install the AW1000 phone packages, then check that '
          'Services > Phone opens in LuCI.',
      error: _error,
      onRetry: () {
        setState(() => _loading = true);
        _loadAll();
      },
    );
  }

  Widget _tabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const KsTitle('Phone'),
              KsChips<int>(
                options: const [
                  (0, 'Line'),
                  (1, 'Calls'),
                  (2, 'Texts'),
                  (3, 'SIP phones'),
                ],
                selected: _tab,
                onSelected: (t) => setState(() => _tab = t),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_tab) {
            1 => _callsTab(),
            2 => _smsTab(),
            3 => _sipTab(),
            _ => _lineTab(),
          },
        ),
      ],
    );
  }

  Widget _lineTab() {
    final s = _status!;
    final ks = context.ks;
    final state = s['state']?.toString() ?? '?';
    final busy = state != 'idle';
    final enabled = s['enabled'] == true;
    final peer = noobValue(s['peer']);

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          NoobSection(
            title: 'The line',
            icon: busy ? Icons.phone_in_talk : Icons.phone,
            children: [
              KsSwitchRow(
                title: 'Phone port',
                subtitle: phoneStateLabels[state] ?? state,
                value: enabled,
                onChanged: (v) => _act('fxs', 'set_enabled', {
                  'enabled': v,
                }, v ? 'Phone port on' : 'Phone port off'),
              ),
              if (peer != null) NoobRow('Number', peer),
              NoobRow('Handset', s['offhook'] == true ? 'Off hook' : 'On hook'),
              if (s['dnd'] == true) const NoobRow('Do not disturb', 'On'),
              if (s['hd'] == true) const NoobRow('Audio', 'HD'),
              if (s['sipon'] == true)
                NoobRow('SIP', s['siptitle']?.toString() ?? 'On'),
              if (s['recmode'] != null && s['recmode'] != 'off')
                NoobRow('Recording', s['recmode'].toString()),
            ],
          ),
          if (s['guard'] == true && s['running'] != true)
            NoobSection(
              title: 'Line guard tripped',
              icon: Icons.warning_amber,
              children: [
                Text(
                  'The router stopped the line after a fault. Check the cable '
                  'and the handset, then clear it.',
                  style: KeystoneType.body(ks.tx2),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () =>
                      _act('fxs', 'clear_guard', {}, 'Guard cleared'),
                  child: const Text('Clear guard'),
                ),
              ],
            ),
          if (!(s['running'] == true && s['module'] == true))
            NoobSection(
              title: 'Not ready',
              icon: Icons.error_outline,
              children: [
                NoobRow(
                  'Phone service (fxsd)',
                  s['running'] == true ? 'Running' : 'Stopped',
                ),
                NoobRow(
                  'Driver',
                  s['module'] == true ? 'Loaded' : 'Not loaded',
                ),
                NoobRow('Line chip patch', s['patch'] == true ? 'Yes' : 'No'),
              ],
            ),
          NoobSection(
            title: 'Test',
            icon: Icons.notifications_active_outlined,
            children: [
              KsRow(
                title: 'Ring the phone',
                subtitle: busy
                    ? 'Wait until the line is free'
                    : 'Check the handset and its cable work',
                onTap: busy
                    ? null
                    : () => _act('fxs', 'ring_test', {}, 'Ringing'),
              ),
            ],
          ),
          NoobSection(
            title: 'Calls and settings',
            icon: Icons.tune_rounded,
            children: [
              for (final (name, page) in <(String, Widget)>[
                ('Blocked numbers', const BlockedNumbersPage()),
                ('Quiet hours', const QuietHoursPage()),
                ('Call forwarding', const CallForwardingPage()),
                ('Balance and codes', const UssdPage()),
                ('Call recordings', const RecordingsPage()),
                ('Line and SIP settings', const LineSettingsPage()),
                ('Missed-call alerts', const MissedCallAlertsPage()),
              ])
                KsRow(
                  title: name,
                  onTap: () async {
                    await Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => page));
                    await _loadStatus();
                  },
                ),
            ],
          ),
          NoobSection(
            title: 'Line readings',
            icon: Icons.electrical_services,
            children: [
              NoobRow('Battery voltage', _volts(s['vbat'])),
              NoobRow('Line voltage', _volts(s['vline'])),
              NoobRow(
                'Loop current',
                s['iloop'] == null ? null : '${s['iloop']}',
              ),
            ],
          ),
          if (_versions != null)
            NoobSection(
              title: 'Versions',
              icon: Icons.info_outline,
              children: [
                for (final e in _versions!.entries)
                  if (noobValue(e.value) != null) NoobRow(e.key, '${e.value}'),
              ],
            ),
          const SizedBox(height: 12),
          Text('Updated every 3 seconds', style: KeystoneType.caption(ks.mu)),
        ],
      ),
    );
  }

  Widget _callsTab() {
    if (_calls.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCalls,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: const [KsNote('No calls yet.')],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCalls,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        itemCount: _calls.length,
        itemBuilder: (_, i) {
          final c = _calls[i];
          final talked = c.talked;
          final ks = context.ks;
          return KsRow(
            leading: Icon(_callIcon(c), size: 20, color: _callColor(ks, c)),
            title: c.number.isEmpty ? 'Unknown number' : c.number,
            subtitle: [
              switch (c.status) {
                final st? when st.isNotEmpty =>
                  st[0].toUpperCase() + st.substring(1),
                _ => '',
              },
              if (talked != null) _dur(talked),
              noobAgo(c.start),
            ].where((x) => x.isNotEmpty).join(' · '),
            trailing: c.number.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Call back',
                    icon: Icon(Icons.call_outlined, color: ks.ac),
                    onPressed: () => _callBack(c.number),
                  ),
          );
        },
      ),
    );
  }

  Future<void> _loadSip() async {
    try {
      final r = await _call('modem-sip', 'status');
      if (mounted) setState(() => _sip = r);
    } catch (_) {
      if (mounted) setState(() => _sip = null);
    }
  }

  Future<String?> _ask(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ks.sheet,
        title: Text(title, style: KeystoneType.sheetTitle(context.ks.tx)),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: ksInput(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _sipDo(
    String method,
    Map<String, dynamic> p,
    String done,
  ) async {
    try {
      final r = await _call('modem-sip', method, p);
      if (r['result'] == false) {
        throw NoobRpcError(r['error']?.toString() ?? 'Failed');
      }
      if (mounted) ksSay(context, done);
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
    await _loadSip();
  }

  Future<void> _sipLogin(String name) async {
    try {
      final r = await _call('modem-sip', 'phone_login', {'name': name});
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.ks.sheet,
          title: Text(
            'Sign-in for $name',
            style: KeystoneType.sheetTitle(context.ks.tx),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              NoobRow('Server', r['server']?.toString()),
              NoobRow('Port', r['port']?.toString()),
              NoobRow('Username', r['user']?.toString()),
              NoobRow('Password', r['password']?.toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
  }

  Widget _sipTab() {
    final s = _sip;
    if (s == null) {
      return NoobProblem(
        title: 'SIP phones',
        detail:
            'SIP phones need luci-app-modem-sip on the router. Install it, '
            'then add phones here.',
        onRetry: _loadSip,
      );
    }
    final phones = [
      if (s['phones'] is List)
        for (final p in s['phones'] as List)
          if (p is Map) Map<String, dynamic>.from(p),
    ];
    final ks = context.ks;
    Future<void> add() async {
      final name = await _ask('Name the new phone');
      if (name != null && name.isNotEmpty) {
        await _sipDo('phone_add', {'name': name}, 'Added $name');
      }
    }

    return RefreshIndicator(
      onRefresh: _loadSip,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          NoobRow(
            'SIP service',
            s['running'] == true ? 'Running' : 'Stopped',
            color: s['running'] == true ? ks.ok : ks.warnTx,
          ),
          KsSection(
            'Phones · ${phones.length}',
            trailing: TextButton(onPressed: add, child: const Text('Add')),
          ),
          if (phones.isEmpty)
            const KsNote('No SIP phones yet. Tap Add to make one.'),
          for (final p in phones)
            KsRow(
              leading: KsDot(p['online'] == true ? ks.ok : ks.line),
              title: p['name']?.toString() ?? '',
              subtitle:
                  '${p['user'] ?? ''} · '
                  '${p['online'] == true ? 'online' : 'offline'}',
              onTap: () => _sipLogin(p['name'].toString()),
              trailing: PopupMenuButton<String>(
                tooltip: 'More',
                color: ks.sheet,
                icon: Icon(Icons.more_horiz_rounded, color: ks.mu),
                onSelected: (a) async {
                  final name = p['name'].toString();
                  if (a == 'qr') {
                    await showSipQr(context, ref.read(appStateProvider), name);
                  } else if (a == 'rename') {
                    final n = await _ask('Rename $name', initial: name);
                    if (n != null && n.isNotEmpty && n != name) {
                      await _sipDo('phone_rename', {
                        'name': name,
                        'new': n,
                      }, 'Renamed');
                    }
                  } else if (a == 'remove' &&
                      await ksConfirm(
                        context,
                        title: 'Remove $name?',
                        body:
                            'It can no longer make or take calls through '
                            'the router.',
                        action: 'Remove',
                        danger: true,
                      )) {
                    await _sipDo('phone_remove', {
                      'name': name,
                    }, 'Removed $name');
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'qr',
                    child: Text('Set up with a QR code'),
                  ),
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _callBack(String number) async {
    final how = await ksSheet<String>(
      context,
      (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Call $number', style: KeystoneType.sheetTitle(ctx.ks.tx)),
          const SizedBox(height: 8),
          KsRow(
            title: 'Ring the router phone',
            subtitle:
                'The handset rings; pick it up and the call goes out on '
                'the SIM',
            onTap: () => Navigator.pop(ctx, 'router'),
          ),
          KsRow(
            title: 'Call from this phone',
            subtitle: 'Opens the dialer',
            onTap: () => Navigator.pop(ctx, 'here'),
          ),
        ],
      ),
    );
    if (how == 'router') {
      await _act('fxs', 'click_call', {
        'number': number,
      }, 'Pick up the handset to call $number');
    } else if (how == 'here') {
      await launchUrl(Uri(scheme: 'tel', path: number));
    }
  }

  Widget _smsTab() {
    if (!_hasVoice) {
      return NoobProblem(
        title: 'SMS not available',
        detail: 'SMS needs aw1000-voice on the router.',
        onRetry: _loadSms,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSms,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          if (_smsModem)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _sendSms,
                child: const Text('Write a text'),
              ),
            ),
          if (_sms.isEmpty) const KsNote('No texts.'),
          for (final m in _sms)
            KsRow(
              leading: Icon(
                m['direction'] == 'out'
                    ? Icons.call_made_rounded
                    : Icons.call_received_rounded,
                size: 18,
                color: context.ks.mu,
              ),
              title: noobValue(m['name']) ?? m['number']?.toString() ?? '',
              subtitle: [
                m['text']?.toString() ?? '',
                if (m['time'] is num) noobAgo((m['time'] as num).toInt()),
              ].join('\n'),
              onTap: () => _deleteSms(m),
              chevron: false,
            ),
        ],
      ),
    );
  }

  Future<void> _sendSms() async {
    final number = TextEditingController();
    final text = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.ks.sheet,
        title: Text('New text', style: KeystoneType.sheetTitle(context.ks.tx)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: number,
              keyboardType: TextInputType.phone,
              decoration: ksInput(context, hint: 'Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: text,
              minLines: 2,
              maxLines: 6,
              decoration: ksInput(context, hint: 'Message'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true || number.text.trim().isEmpty || text.text.isEmpty) return;
    try {
      await _call('aw1000-voice', 'sms_send', {
        'number': number.text.trim(),
        'text': text.text,
      });
      if (mounted) ksSay(context, 'Sent.');
      await _loadSms();
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
  }

  Future<void> _deleteSms(Map<String, dynamic> m) async {
    final ok = await ksConfirm(
      context,
      title: 'Delete this text?',
      body: m['text']?.toString() ?? '',
      action: 'Delete',
      danger: true,
    );
    if (ok != true) return;
    try {
      await _call('aw1000-voice', 'sms_delete', {
        'indexes': [m['index']],
      });
      await _loadSms();
    } catch (e) {
      if (mounted) ksSay(context, e.toString());
    }
  }
}

IconData _callIcon(PhoneCall c) => switch (c.status) {
  'missed' => Icons.call_missed,
  'blocked' => Icons.block,
  'active' => Icons.phone_in_talk,
  _ => c.dir == CallDir.incoming ? Icons.call_received : Icons.call_made,
};

Color _callColor(KeystoneColors ks, PhoneCall c) => switch (c.status) {
  'missed' || 'blocked' || 'failed' => ks.bad,
  'active' => ks.ok,
  _ => ks.mu,
};

String _dur(Duration d) {
  final m = d.inMinutes, s = d.inSeconds % 60;
  return m > 0 ? '${m}m ${s}s' : '${s}s';
}

String? _volts(dynamic mv) =>
    mv is num ? '${(mv / 1000).toStringAsFixed(1)} V' : null;
