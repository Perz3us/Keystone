// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/state/app_state.dart';
import 'package:yet_another_luci_app/widgets/keystone/ks_kit.dart';

import '../noob_rpc.dart';

final _numberRe = RegExp(r'^\+?[0-9]{3,20}$');
final _timeRe = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');

String phoneError(Object e) {
  final code = e is NoobRpcError ? e.message : e.toString();
  return switch (code) {
    'refused' => 'The mobile network turned that down.',
    'timeout' => 'The modem didn\'t answer. Try again.',
    'stopped' => 'The phone service isn\'t running on the router.',
    'exists' => 'That number is already on the list.',
    'number' => 'Enter a phone number.',
    'busy' => 'That call is still being recorded.',
    'reply' => 'The modem sent back nothing useful. Try again.',
    'code' => 'Enter a code like *#100#.',
    _ => code,
  };
}

Future<Map<String, dynamic>> phoneDo(
  AppState app,
  String obj,
  String method, [
  Map<String, dynamic>? p,
]) async {
  final r = await noobCall(app, obj, method, p);
  if (r['result'] == false || r['ok'] == false) {
    throw NoobRpcError(r['error']?.toString() ?? 'Failed');
  }
  return r;
}

Future<void> _uciWrite(
  AppState app,
  String config,
  String method,
  Map<String, dynamic> p,
) async {
  await noobCall(app, 'uci', method, {'config': config, ...p});
  await noobUciCommit(app, config);
}

Future<Map<String, Map<String, dynamic>>> _uciByName(
  AppState app,
  String config,
) async {
  final list = await noobUciSections(app, config);
  return {for (final s in list) s['.name'].toString(): s};
}

String? _str(dynamic v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

List<String> _list(dynamic v) => v is List
    ? [for (final x in v) x.toString()]
    : (_str(v)?.split(RegExp(r'\s+')) ?? const []);

class BlockedNumbersPage extends ConsumerStatefulWidget {
  const BlockedNumbersPage({super.key});
  @override
  ConsumerState<BlockedNumbersPage> createState() => _BlockedState();
}

class _BlockedState extends ConsumerState<BlockedNumbersPage> {
  AppState get _app => ref.read(appStateProvider);
  bool _hidden = false;
  List<Map<String, dynamic>>? _blocks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await noobUciSections(_app, 'fxs');
      if (!mounted) return;
      setState(() {
        _hidden = all.any(
          (s) => s['.name'] == 'main' && s['block_private'] == '1',
        );
        _blocks = [
          for (final s in all)
            if (s['.type'] == 'block') s,
        ];
      });
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  Future<void> _add() async {
    final r = await ksFormRoute<(String, String)>(
      context,
      const _NumberForm(title: 'Block a number', action: 'Block'),
    );
    if (r == null) return;
    try {
      await phoneDo(_app, 'fxs', 'add_number', {
        'kind': 'block',
        'name': r.$1,
        'number': r.$2,
      });
      if (mounted) ksSay(context, '${r.$1.isEmpty ? r.$2 : r.$1} is blocked.');
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    await _load();
  }

  Future<void> _remove(Map<String, dynamic> b) async {
    final label = _str(b['name']) ?? b['number'].toString();
    if (!await ksConfirm(
      context,
      title: 'Unblock $label?',
      body: 'Calls from this number will ring the phone again.',
      action: 'Unblock',
    )) {
      return;
    }
    try {
      await _uciWrite(_app, 'fxs', 'delete', {'section': b['.name']});
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final blocks = _blocks;
    return KsPage(
      title: 'Blocked numbers',
      subtitle: 'These calls are turned away without ringing the phone.',
      onRefresh: _load,
      children: [
        if (blocks == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          KsSwitchRow(
            title: 'Block hidden numbers',
            subtitle: 'Turn away calls that don\'t show a number',
            value: _hidden,
            onChanged: (v) async {
              try {
                await noobUciSet(_app, 'fxs', 'main', {
                  'block_private': v ? '1' : '0',
                });
              } catch (e) {
                if (mounted) ksSay(this.context, phoneError(e));
              }
              await _load();
            },
          ),
          KsSection(
            'Numbers · ${blocks.length}',
            trailing: TextButton(onPressed: _add, child: const Text('Add')),
          ),
          if (blocks.isEmpty) const KsNote('No blocked numbers.'),
          for (final b in blocks)
            KsRow(
              title: _str(b['name']) ?? b['number'].toString(),
              subtitle: _str(b['name']) == null ? null : b['number'].toString(),
              chevron: false,
              trailing: IconButton(
                tooltip: 'Unblock',
                icon: Icon(Icons.close_rounded, color: context.ks.mu),
                onPressed: () => _remove(b),
              ),
            ),
        ],
      ],
    );
  }
}

class _NumberForm extends StatefulWidget {
  const _NumberForm({required this.title, required this.action});
  final String title;
  final String action;
  @override
  State<_NumberForm> createState() => _NumberFormState();
}

class _NumberFormState extends State<_NumberForm> {
  final _form = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _name = TextEditingController();

  @override
  Widget build(BuildContext context) => KsFormPage(
    title: widget.title,
    action: widget.action,
    formKey: _form,
    onAction: () {
      if (_form.currentState?.validate() != true) return;
      Navigator.pop(context, (_name.text.trim(), _number.text.trim()));
    },
    children: [
      KsField(
        label: 'Number',
        controller: _number,
        hint: '0771234567',
        keyboardType: TextInputType.phone,
        validator: (v) =>
            _numberRe.hasMatch(v?.trim() ?? '') ? null : 'Enter a phone number',
      ),
      KsField(label: 'Name', controller: _name, help: 'Optional'),
    ],
  );
}

const _days = [
  ('mon', 'Mon'),
  ('tue', 'Tue'),
  ('wed', 'Wed'),
  ('thu', 'Thu'),
  ('fri', 'Fri'),
  ('sat', 'Sat'),
  ('sun', 'Sun'),
];

class QuietHoursPage extends ConsumerStatefulWidget {
  const QuietHoursPage({super.key});
  @override
  ConsumerState<QuietHoursPage> createState() => _QuietState();
}

class _QuietState extends ConsumerState<QuietHoursPage> {
  AppState get _app => ref.read(appStateProvider);
  Map<String, dynamic>? _st;
  List<Map<String, dynamic>> _windows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await noobCall(_app, 'fxs', 'quiet_status');
      final all = await noobUciSections(_app, 'fxs');
      if (!mounted) return;
      setState(() {
        _st = st;
        _windows = [
          for (final s in all)
            if (s['.type'] == 'quiet') s,
        ];
      });
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  Future<void> _quiet(int minutes) async {
    try {
      await phoneDo(_app, 'fxs', 'quiet_set', {'minutes': minutes});
      if (mounted) {
        ksSay(context, minutes == 0 ? 'The phone rings again.' : 'Quiet on.');
      }
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    await _load();
  }

  String _state() {
    final st = _st!;
    if (st['on'] == true) {
      final until = (st['until'] as num?)?.toInt() ?? 0;
      if (until <= 0) return 'Quiet until you turn it off.';
      final t = TimeOfDay.fromDateTime(
        DateTime.fromMillisecondsSinceEpoch(until * 1000),
      );
      return 'Quiet until ${MaterialLocalizations.of(context).formatTimeOfDay(t)}.';
    }
    if (st['scheduled'] == true) return 'Quiet now, from a weekly window.';
    return 'The phone rings as normal.';
  }

  String _windowLine(Map<String, dynamic> w) {
    final days = _list(w['days']);
    final names = [
      for (final d in _days)
        if (days.contains(d.$1)) d.$2,
    ];
    return [
      names.length == 7 ? 'Every day' : names.join(' '),
      '${w['from'] ?? '?'}–${w['to'] ?? '?'}',
      if (w['enabled'] == '0') 'Off',
    ].join(' · ');
  }

  Future<void> _edit([Map<String, dynamic>? w]) async {
    final saved = await ksFormRoute<bool>(context, _WindowForm(window: w));
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = _st;
    return KsPage(
      title: 'Quiet hours',
      subtitle: st == null ? null : _state(),
      onRefresh: _load,
      children: [
        if (st == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          const KsSection('Quiet now'),
          KsChips<int>(
            options: const [
              (60, '1 hour'),
              (120, '2 hours'),
              (480, '8 hours'),
              (-1, 'Until I turn it off'),
            ],
            selected: -2,
            onSelected: _quiet,
          ),
          if (st['on'] == true)
            KsRow(title: 'Let it ring again', onTap: () => _quiet(0)),
          KsSection(
            'Every week',
            trailing: TextButton(
              onPressed: () => _edit(),
              child: const Text('Add'),
            ),
          ),
          if (_windows.isEmpty)
            const KsNote(
              'No quiet windows. Add one, like every night 22:00–07:00.',
            ),
          for (final w in _windows)
            KsRow(
              title: _str(w['name']) ?? 'Quiet window',
              subtitle: _windowLine(w),
              onTap: () => _edit(w),
            ),
          const SizedBox(height: 12),
          Text(
            'Only the RJ11 phone goes quiet. SIP phones, emergency numbers '
            'and contacts marked Important still ring, and every call still '
            'shows in the history.',
            style: KeystoneType.caption(context.ks.mu),
          ),
        ],
      ],
    );
  }
}

class _WindowForm extends ConsumerStatefulWidget {
  const _WindowForm({this.window});
  final Map<String, dynamic>? window;
  @override
  ConsumerState<_WindowForm> createState() => _WindowFormState();
}

class _WindowFormState extends ConsumerState<_WindowForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: _str(widget.window?['name']));
  late final _from = TextEditingController(
    text: _str(widget.window?['from']) ?? '22:00',
  );
  late final _to = TextEditingController(
    text: _str(widget.window?['to']) ?? '07:00',
  );
  late final Set<String> _on = {
    ...(widget.window == null
        ? [for (final d in _days) d.$1]
        : _list(widget.window!['days'])),
  };
  late String _mode = _str(widget.window?['mode']) ?? 'repeat';
  late String _action = _str(widget.window?['action']) ?? 'silent';
  late bool _enabled = widget.window?['enabled'] != '0';
  bool _busy = false;

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    if (_on.isEmpty) {
      ksSay(context, 'Pick at least one day.');
      return;
    }
    setState(() => _busy = true);
    final values = <String, dynamic>{
      'enabled': _enabled ? '1' : '0',
      'name': _name.text.trim(),
      'days': [
        for (final d in _days)
          if (_on.contains(d.$1)) d.$1,
      ],
      'from': _from.text.trim(),
      'to': _to.text.trim(),
      'mode': _mode,
      'action': _action,
    };
    final app = ref.read(appStateProvider);
    try {
      if (widget.window == null) {
        await _uciWrite(app, 'fxs', 'add', {'type': 'quiet', 'values': values});
      } else {
        await _uciWrite(app, 'fxs', 'set', {
          'section': widget.window!['.name'],
          'values': values,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ksSay(context, phoneError(e));
      }
    }
  }

  Future<void> _delete() async {
    if (!await ksConfirm(
      context,
      title: 'Remove this window?',
      body: 'The phone will ring at these times again.',
      action: 'Remove',
      danger: true,
    )) {
      return;
    }
    try {
      await _uciWrite(ref.read(appStateProvider), 'fxs', 'delete', {
        'section': widget.window!['.name'],
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  String? _time(String? v) =>
      _timeRe.hasMatch(v?.trim() ?? '') ? null : 'Enter a time like 22:00';

  @override
  Widget build(BuildContext context) => KsFormPage(
    title: widget.window == null ? 'New quiet window' : 'Quiet window',
    action: 'Save',
    busy: _busy,
    formKey: _form,
    onAction: _save,
    children: [
      KsSwitchRow(
        title: 'On',
        value: _enabled,
        onChanged: (v) => setState(() => _enabled = v),
      ),
      KsField(label: 'Name', controller: _name, hint: 'Night'),
      const KsSection('Days'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final d in _days)
            KsChip(
              d.$2,
              many: true,
              selected: _on.contains(d.$1),
              onTap: () => setState(
                () => _on.contains(d.$1) ? _on.remove(d.$1) : _on.add(d.$1),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      KsField(
        label: 'From',
        controller: _from,
        keyboardType: TextInputType.datetime,
        validator: _time,
      ),
      KsField(
        label: 'Until',
        controller: _to,
        keyboardType: TextInputType.datetime,
        help:
            'A window past midnight belongs to the day it starts. '
            'The same time in both means the whole day.',
        validator: _time,
      ),
      KsChoice<String>(
        label: 'Who can ring',
        value: _mode,
        options: const [
          ('repeat', 'Important, Always ring and repeat callers'),
          ('allowed', 'Important and Always ring'),
          ('all', 'Important contacts only'),
        ],
        onChanged: (v) => setState(() => _mode = v),
      ),
      KsChoice<String>(
        label: 'Other calls',
        value: _action,
        options: const [
          ('silent', 'Stay silent'),
          ('once', 'One short ring'),
          ('busy', 'Caller hears busy'),
        ],
        onChanged: (v) => setState(() => _action = v),
      ),
      if (widget.window != null)
        KsRow(title: 'Remove this window', danger: true, onTap: _delete),
    ],
  );
}

const _reasons = [
  ('always', 'All calls'),
  ('busy', 'When you\'re on a call'),
  ('noanswer', 'When you don\'t answer'),
  ('unreachable', 'When the router is off or has no signal'),
];

class CallForwardingPage extends ConsumerStatefulWidget {
  const CallForwardingPage({super.key});
  @override
  ConsumerState<CallForwardingPage> createState() => _ForwardState();
}

class _ForwardState extends ConsumerState<CallForwardingPage> {
  AppState get _app => ref.read(appStateProvider);
  final Map<String, String> _now = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final r in _reasons) {
      if (mounted) setState(() => _now[r.$1] = 'Checking…');
      String line;
      try {
        final res = await phoneDo(_app, 'fxs', 'forward_get', {'reason': r.$1});
        line = _str(res['text']) ?? 'Off';
      } catch (e) {
        line = phoneError(e);
      }
      if (!mounted) return;
      setState(() => _now[r.$1] = line);
    }
  }

  Future<void> _change(String reason, String label) async {
    final done = await ksSheet<bool>(
      context,
      (_) => _ForwardSheet(reason: reason, label: label),
    );
    if (done == true) await _load();
  }

  @override
  Widget build(BuildContext context) => KsPage(
    title: 'Call forwarding',
    subtitle: 'The mobile network sends calls on to another number.',
    onRefresh: _load,
    children: [
      for (final r in _reasons)
        KsRow(
          title: r.$2,
          subtitle: _now[r.$1],
          onTap: () => _change(r.$1, r.$2),
        ),
    ],
  );
}

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet({required this.reason, required this.label});
  final String reason;
  final String label;
  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  final _number = TextEditingController();
  String _seconds = '20';
  bool _busy = false;
  String? _error;

  Future<void> _send(String number) async {
    if (number.isNotEmpty && !_numberRe.hasMatch(number)) {
      setState(() => _error = 'Enter a phone number');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await phoneDo(ref.read(appStateProvider), 'fxs', 'forward_set', {
        'reason': widget.reason,
        'number': number,
        'seconds': widget.reason == 'noanswer' && number.isNotEmpty
            ? _seconds
            : '',
      });
      if (!mounted) return;
      ksSay(
        context,
        number.isEmpty ? 'Forwarding stopped.' : 'Calls go to $number.',
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = phoneError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Forward ${widget.label.toLowerCase()}',
          style: KeystoneType.sheetTitle(ks.tx),
        ),
        const SizedBox(height: 12),
        KsField(
          label: 'To',
          controller: _number,
          hint: '0771234567',
          keyboardType: TextInputType.phone,
          validator: (_) => _error,
        ),
        if (_error != null)
          Text(_error!, style: KeystoneType.secondary(ks.bad)),
        if (widget.reason == 'noanswer')
          KsChoice<String>(
            label: 'Ring for',
            value: _seconds,
            options: const [
              ('5', '5 seconds'),
              ('10', '10 seconds'),
              ('15', '15 seconds'),
              ('20', '20 seconds'),
              ('25', '25 seconds'),
              ('30', '30 seconds'),
            ],
            onChanged: (v) => setState(() => _seconds = v),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _send(_number.text.trim()),
          child: const Text('Forward'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _send(''),
          child: const Text('Stop forwarding'),
        ),
      ],
    );
  }
}

class UssdPage extends ConsumerStatefulWidget {
  const UssdPage({super.key});
  @override
  ConsumerState<UssdPage> createState() => _UssdState();
}

class _UssdState extends ConsumerState<UssdPage> {
  final _code = TextEditingController();
  final _reply = TextEditingController();
  String? _text;
  bool _more = false;
  bool _busy = false;

  Future<void> _send({bool reply = false}) async {
    final v = (reply ? _reply : _code).text.trim();
    if (!reply && !RegExp(r'^[*#][0-9*#]*#$').hasMatch(v)) {
      ksSay(context, 'Enter a code like *#100#.');
      return;
    }
    if (reply && !RegExp(r'^[0-9]{1,16}$').hasMatch(v)) {
      ksSay(context, 'Answer with the number of a choice.');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await phoneDo(
        ref.read(appStateProvider),
        'fxs',
        'ussd',
        reply ? {'reply': v} : {'code': v},
      );
      if (!mounted) return;
      setState(() {
        _text = _str(r['text']) ?? 'Done. The network sent no message.';
        _more = r['more'] == true;
        _reply.clear();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _text = phoneError(e);
          _more = false;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    try {
      await noobCall(ref.read(appStateProvider), 'fxs', 'ussd_end');
    } catch (_) {}
    if (mounted) setState(() => _more = false);
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return KsPage(
      title: 'Balance and codes',
      subtitle: 'Send a code like *#100# to the network through the SIM.',
      children: [
        KsField(
          label: 'Code',
          controller: _code,
          hint: '*#100#',
          keyboardType: TextInputType.phone,
        ),
        FilledButton(
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Waiting for the network…' : 'Send'),
        ),
        if (_text != null) ...[
          const KsSection('Reply'),
          SelectableText(_text!, style: KeystoneType.address(ks.tx)),
        ],
        if (_more) ...[
          const SizedBox(height: 12),
          KsField(
            label: 'Your answer',
            controller: _reply,
            keyboardType: TextInputType.number,
          ),
          Row(
            children: [
              FilledButton(
                onPressed: _busy ? null : () => _send(reply: true),
                child: const Text('Answer'),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _end, child: const Text('End')),
            ],
          ),
        ],
      ],
    );
  }
}

class RecordingsPage extends ConsumerStatefulWidget {
  const RecordingsPage({super.key});
  @override
  ConsumerState<RecordingsPage> createState() => _RecState();
}

class _RecState extends ConsumerState<RecordingsPage> {
  AppState get _app => ref.read(appStateProvider);
  Map<String, dynamic>? _st;
  String _mode = 'off';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await noobCall(_app, 'fxs', 'rec_status');
      final main = (await _uciByName(_app, 'fxs'))['main'];
      if (!mounted) return;
      setState(() {
        _st = st;
        _mode = _str(main?['rec_mode']) ?? 'off';
      });
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  Future<void> _setMode(String v) async {
    try {
      await noobUciSet(_app, 'fxs', 'main', {'rec_mode': v});
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    await _load();
  }

  Future<void> _file(String method, Map<String, dynamic> p, String done) async {
    try {
      await phoneDo(_app, 'fxs', method, p);
      if (mounted) ksSay(context, done);
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    await _load();
  }

  static String _title(String name) {
    final m = RegExp(
      r'^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})\d{2}-(\d+)\.wav$',
    ).firstMatch(name);
    if (m == null) return name;
    return '${m[6]} · ${m[1]}-${m[2]}-${m[3]} ${m[4]}:${m[5]}';
  }

  static String _mb(num bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final st = _st;
    final files = [
      if (st?['files'] is List)
        for (final f in st!['files'] as List)
          if (f is Map) Map<String, dynamic>.from(f),
    ]..sort((a, b) => b['name'].toString().compareTo(a['name'].toString()));
    return KsPage(
      title: 'Call recordings',
      subtitle: st == null
          ? null
          : 'Using ${_mb(st['used'] ?? 0)} of ${_mb(st['limit'] ?? 0)}. '
                'The oldest are deleted when it fills, unless you keep them.',
      onRefresh: _load,
      children: [
        if (st == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          KsChoice<String>(
            label: 'Record',
            value: _mode,
            options: const [
              ('off', 'Off'),
              ('every', 'All calls'),
              ('all', 'All calls except Never record'),
              ('chosen', 'Only numbers marked Always record'),
            ],
            onChanged: _setMode,
          ),
          if (_mode != 'off')
            Text(
              'Tell the other person when a call is recorded. In many '
              'places that\'s the law.',
              style: KeystoneType.caption(context.ks.warnTx),
            ),
          KsSection('Recordings · ${files.length}'),
          if (files.isEmpty) const KsNote('No recordings.'),
          for (final f in files)
            KsRow(
              title: _title(f['name'].toString()),
              subtitle: [
                _mb(f['size'] ?? 0),
                if (f['usb'] == true) 'USB stick',
                if (f['keep'] == true) 'Kept',
              ].join(' · '),
              chevron: false,
              trailing: PopupMenuButton<String>(
                tooltip: 'More',
                color: context.ks.sheet,
                icon: Icon(Icons.more_horiz_rounded, color: context.ks.mu),
                onSelected: (a) async {
                  final name = f['name'].toString();
                  if (a == 'keep') {
                    await _file(
                      'rec_keep',
                      {'name': name, 'keep': f['keep'] != true},
                      f['keep'] == true ? 'It can be cleaned up now.' : 'Kept.',
                    );
                  } else if (await ksConfirm(
                    context,
                    title: 'Delete this recording?',
                    body: _title(name),
                    action: 'Delete',
                    danger: true,
                  )) {
                    await _file('rec_delete', {'name': name}, 'Deleted.');
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'keep',
                    child: Text(f['keep'] == true ? 'Don\'t keep' : 'Keep'),
                  ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class LineSettingsPage extends ConsumerStatefulWidget {
  const LineSettingsPage({super.key});
  @override
  ConsumerState<LineSettingsPage> createState() => _LineSettingsState();
}

class _LineSettingsState extends ConsumerState<LineSettingsPage> {
  AppState get _app => ref.read(appStateProvider);
  final _form = GlobalKey<FormState>();
  Map<String, String> _was = const {};
  final Map<String, String> _now = {};
  Map<String, dynamic>? _sip;
  final _port = TextEditingController();
  final _rtpFrom = TextEditingController();
  final _rtpTo = TextEditingController();
  bool _sipHd = false;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final main = (await _uciByName(_app, 'fxs'))['main'] ?? const {};
      Map<String, dynamic>? sip;
      try {
        sip = await noobCall(_app, 'modem-sip', 'settings');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _was = {
          for (final e in main.entries)
            if (!e.key.startsWith('.')) e.key: e.value.toString(),
        };
        _now
          ..clear()
          ..addAll(_was);
        _sip = sip;
        if (sip != null) {
          _port.text = '${sip['port'] ?? ''}';
          _rtpFrom.text = '${sip['rtp_from'] ?? ''}';
          _rtpTo.text = '${sip['rtp_to'] ?? ''}';
          _sipHd = sip['hd'] == true;
        }
        _loaded = true;
      });
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  String _v(String k, String fallback) => _now[k] ?? fallback;
  void _set(String k, String v) => setState(() => _now[k] = v);

  String? _portCheck(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    return (n == null || n < 1 || n > 65535) ? 'Use 1 to 65535' : null;
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    setState(() => _busy = true);
    try {
      final changed = {
        for (final e in _now.entries)
          if (_was[e.key] != e.value) e.key: e.value,
      };
      if (changed.isNotEmpty) {
        await noobUciSet(_app, 'fxs', 'main', changed);
      }
      final sip = _sip;
      if (sip != null) {
        final p = int.parse(_port.text.trim());
        final a = int.parse(_rtpFrom.text.trim());
        final b = int.parse(_rtpTo.text.trim());
        if (p != sip['port'] ||
            a != sip['rtp_from'] ||
            b != sip['rtp_to'] ||
            _sipHd != (sip['hd'] == true)) {
          await phoneDo(_app, 'modem-sip', 'set_settings', {
            'port': p,
            'rtp_from': a,
            'rtp_to': b,
            'hd': _sipHd,
          });
        }
      }
      if (mounted) {
        ksSay(context, 'Saved.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ksSay(context, phoneError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pattern = _v('ring_pattern', 'standard');
    return KsFormPage(
      title: 'Line and SIP settings',
      action: 'Save',
      busy: _busy,
      formKey: _form,
      onAction: _loaded ? _save : null,
      children: !_loaded
          ? const [Center(child: CircularProgressIndicator())]
          : [
              const KsSection('RJ11 phone'),
              KsChoice<String>(
                label: 'Earpiece volume',
                value: _v('volume', '5'),
                options: [
                  for (var i = 0; i <= 5; i++)
                    ('$i', i == 0 ? '0 (quietest)' : '$i'),
                ],
                onChanged: (v) => _set('volume', v),
              ),
              KsChoice<String>(
                label: 'Ring pattern',
                value: pattern,
                options: [
                  ('standard', 'Standard, 2 s ring and 4 s pause'),
                  ('short', 'Short, 1 s ring and 4 s pause'),
                  ('double', 'Double ring, as in the UK and Australia'),
                  if (pattern == 'custom') ('custom', 'Custom (set in LuCI)'),
                ],
                onChanged: (v) => _set('ring_pattern', v),
              ),
              KsChoice<String>(
                label: 'Caller ID',
                value: _v('callerid', 'bellcore'),
                help: 'If the handset shows no number, try another kind.',
                options: const [
                  ('bellcore', 'FSK (Bellcore)'),
                  ('etsi', 'FSK (ETSI)'),
                  ('dtmf', 'DTMF'),
                  ('off', 'Off'),
                ],
                onChanged: (v) => _set('callerid', v),
              ),
              KsSwitchRow(
                title: 'HD calling',
                subtitle: 'Clearer sound when the network supports it',
                value: _v('hd', '0') == '1',
                onChanged: (v) => _set('hd', v ? '1' : '0'),
              ),
              KsSwitchRow(
                title: 'Call waiting',
                subtitle: 'Beep when a second call comes in',
                value: _v('call_waiting', '0') == '1',
                onChanged: (v) => _set('call_waiting', v ? '1' : '0'),
              ),
              KsSwitchRow(
                title: 'Ringback tone',
                subtitle: 'Hear ringing while your call connects',
                value: _v('ringback', '1') == '1',
                onChanged: (v) => _set('ringback', v ? '1' : '0'),
              ),
              if (_sip != null) ...[
                const KsSection('SIP'),
                KsSwitchRow(
                  title: 'HD voice for SIP phones',
                  value: _sipHd,
                  onChanged: (v) => setState(() => _sipHd = v),
                ),
                KsField(
                  label: 'SIP port',
                  controller: _port,
                  keyboardType: TextInputType.number,
                  validator: _portCheck,
                ),
                KsField(
                  label: 'Audio ports from',
                  controller: _rtpFrom,
                  keyboardType: TextInputType.number,
                  validator: _portCheck,
                ),
                KsField(
                  label: 'Audio ports to',
                  controller: _rtpTo,
                  keyboardType: TextInputType.number,
                  help:
                      'Leave these as they are unless a phone app has no sound.',
                  validator: (v) {
                    final bad = _portCheck(v);
                    if (bad != null) return bad;
                    final a = int.tryParse(_rtpFrom.text.trim()) ?? 0;
                    return int.parse(v!.trim()) <= a
                        ? 'Make it higher than the first port'
                        : null;
                  },
                ),
              ],
            ],
    );
  }
}

const _alertKeys = [
  'enabled',
  'service',
  'ntfy_url',
  'ntfy_token',
  'telegram_token',
  'telegram_chat',
  'webhook_url',
];

class MissedCallAlertsPage extends ConsumerStatefulWidget {
  const MissedCallAlertsPage({super.key});
  @override
  ConsumerState<MissedCallAlertsPage> createState() => _AlertsState();
}

class _AlertsState extends ConsumerState<MissedCallAlertsPage> {
  AppState get _app => ref.read(appStateProvider);
  final _form = GlobalKey<FormState>();
  final _c = {for (final k in _alertKeys.skip(2)) k: TextEditingController()};
  Map<String, String> _was = const {};
  bool _enabled = false;
  String _service = 'ntfy';
  String? _lastError;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final n = (await _uciByName(_app, 'aw1000_voice'))['notify'] ?? const {};
      Map<String, dynamic> st = const {};
      try {
        st = await noobCall(_app, 'aw1000-voice', 'notify_status');
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _was = {for (final k in _alertKeys) k: n[k]?.toString() ?? ''};
        _enabled = _was['enabled'] == '1';
        _service = _str(_was['service']) ?? 'ntfy';
        for (final e in _c.entries) {
          e.value.text = _was[e.key]!;
        }
        _lastError = _str(st['last_error']);
        _loaded = true;
      });
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
  }

  Map<String, String> get _values => {
    'enabled': _enabled ? '1' : '0',
    'service': _service,
    for (final e in _c.entries) e.key: e.value.text.trim(),
  };

  Future<bool> _store() async {
    if (_form.currentState?.validate() != true) return false;
    final changed = {
      for (final e in _values.entries)
        if (_was[e.key] != e.value) e.key: e.value,
    };
    if (_enabled && _was['events']?.isEmpty != false) {
      changed['events'] = 'missed';
    }
    if (changed.isNotEmpty) {
      await noobUciSet(_app, 'aw1000_voice', 'notify', changed);
    }
    _was = _values;
    return true;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      if (await _store() && mounted) {
        ksSay(context, 'Saved.');
        Navigator.pop(context);
        return;
      }
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      if (await _store()) {
        await phoneDo(_app, 'aw1000-voice', 'notify_test');
        if (mounted) ksSay(context, 'Test sent. Check your phone.');
      }
    } catch (e) {
      if (mounted) ksSay(context, phoneError(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  String? _need(String? v) =>
      (v?.trim().isEmpty ?? true) && _enabled ? 'Needed to send alerts' : null;

  @override
  Widget build(BuildContext context) => KsFormPage(
    title: 'Missed-call alerts',
    subtitle: 'Get a message on your phone when you miss a call.',
    action: 'Save',
    busy: _busy,
    formKey: _form,
    onAction: _loaded ? _save : null,
    children: !_loaded
        ? const [Center(child: CircularProgressIndicator())]
        : [
            if (_lastError != null)
              KsBanner('The last alert failed: $_lastError', bad: true),
            KsSwitchRow(
              title: 'Send alerts',
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            KsChoice<String>(
              label: 'Send with',
              value: _service,
              options: const [
                ('ntfy', 'ntfy'),
                ('telegram', 'Telegram'),
                ('webhook', 'A webhook'),
              ],
              onChanged: (v) => setState(() => _service = v),
            ),
            if (_service == 'ntfy') ...[
              KsField(
                label: 'Topic URL',
                controller: _c['ntfy_url']!,
                hint: 'https://ntfy.sh/my-phone',
                keyboardType: TextInputType.url,
                help: 'Subscribe to the same topic in the ntfy app.',
                validator: _need,
              ),
              KsField(
                label: 'Access token',
                controller: _c['ntfy_token']!,
                help: 'Only for a protected topic',
                obscure: true,
              ),
            ],
            if (_service == 'telegram') ...[
              KsField(
                label: 'Bot token',
                controller: _c['telegram_token']!,
                obscure: true,
                validator: _need,
              ),
              KsField(
                label: 'Chat ID',
                controller: _c['telegram_chat']!,
                validator: _need,
              ),
            ],
            if (_service == 'webhook')
              KsField(
                label: 'Webhook URL',
                controller: _c['webhook_url']!,
                keyboardType: TextInputType.url,
                help: 'Gets a JSON post for each missed call.',
                validator: _need,
              ),
            KsRow(
              title: 'Send a test alert',
              subtitle: 'Saves these settings first',
              onTap: _busy ? null : _test,
            ),
          ],
  );
}

Future<void> showSipQr(BuildContext context, AppState app, String phone) async {
  Map<String, dynamic> r;
  try {
    r = await noobCall(app, 'fxs', 'sip_qr', {'phone': phone});
  } catch (e) {
    if (context.mounted) ksSay(context, phoneError(e));
    return;
  }
  final needs = r['needs'] is List ? (r['needs'] as List).join(' ') : '';
  final url = _str(r['url']);
  if (!context.mounted) return;
  if (url == null) {
    ksSay(context, needs.isEmpty ? 'The router made no code.' : needs);
    return;
  }
  final expires = (r['expires'] as num?)?.toInt();
  final mins = expires == null
      ? null
      : (DateTime.fromMillisecondsSinceEpoch(
                  expires * 1000,
                ).difference(DateTime.now()).inSeconds /
                60)
            .ceil();
  await ksSheet<void>(context, (ctx) {
    final ks = ctx.ks;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Set up $phone', style: KeystoneType.sheetTitle(ks.tx)),
        const SizedBox(height: 4),
        Text(
          'Scan this in Linphone on the phone: Assistant, then Fetch '
          'remote configuration, then QR code.',
          textAlign: TextAlign.center,
          style: KeystoneType.secondary(ks.mu),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(data: url, size: 220),
        ),
        const SizedBox(height: 12),
        Text(
          [
            if (_str(r['user']) != null) 'Signs in as ${r['user']}.',
            if (mins != null && mins > 0)
              'The code stops working in $mins minutes.',
            if (_str(r['note']) != null) _str(r['note'])!,
          ].join(' '),
          textAlign: TextAlign.center,
          style: KeystoneType.caption(ks.mu),
        ),
      ],
    );
  });
}
