import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/main.dart';
import 'package:yet_another_luci_app/modules/core/luci_module_registry.dart';
import 'package:yet_another_luci_app/modules/noobwrt/noob_rpc.dart';
import 'package:yet_another_luci_app/screens/speed/speed_test.dart';
import 'package:yet_another_luci_app/screens/speed/speed_view.dart';

const _bin = '/usr/bin/ookla-speedtest';
const _out = '/tmp/keystone_speedtest.jsonl';
const _historyKey = 'speed_history';
const _keep = 10;

class SpeedScreen extends ConsumerStatefulWidget {
  const SpeedScreen({super.key});

  @override
  ConsumerState<SpeedScreen> createState() => _SpeedScreenState();
}

class _SpeedScreenState extends ConsumerState<SpeedScreen> {
  Timer? _poll;
  bool _following = false;
  DateTime? _startedAt;
  SpeedTestProgress? _progress;
  bool _available = true;
  List<SpeedResult> _history = const [];

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _sh(String script) =>
      noobCall(ref.read(appStateProvider), 'file', 'exec', {
        'command': '/bin/sh',
        'params': ['-c', script],
      });

  Future<void> _open() async {
    _history = await _loadHistory();
    var available = false;
    var running = false;
    try {
      final r = await _sh('[ -x $_bin ] && echo yes; pidof ookla-speedtest');
      final out = r['stdout']?.toString() ?? '';
      available = out.contains('yes');
      running = RegExp(r'\d').hasMatch(out.replaceAll('yes', ''));
    } catch (_) {}
    if (!mounted) return;
    setState(() => _available = available);
    if (running) {
      _startedAt = DateTime.now();
      _follow();
    }
  }

  Future<void> _start() async {
    setState(() => _progress = const SpeedTestProgress());
    try {
      await _sh(
        'exec 0<&- 1>&- 2>&-; : > $_out; $_bin --accept-license '
        '--accept-gdpr --format=jsonl --progress=yes > $_out 2>&1 &',
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _progress = SpeedTestProgress(
            phase: SpeedPhase.failed,
            error: '$e',
          ),
        );
      }
      return;
    }
    _startedAt = DateTime.now();
    _follow();
  }

  void _follow() {
    _poll?.cancel();
    _following = true;
    _tick();
  }

  Future<void> _tick() async {
    if (!_following || !mounted) return;
    await _readOnce();
    if (_following && mounted) {
      _poll = Timer(const Duration(milliseconds: 400), _tick);
    }
  }

  Future<void> _readOnce() async {
    {
      String text;
      try {
        text = await noobReadFile(ref.read(appStateProvider), _out);
      } catch (_) {
        return;
      }
      final p = SpeedTestProgress.parse(text);
      final late =
          _startedAt != null &&
          DateTime.now().difference(_startedAt!) > const Duration(minutes: 2);
      final shown = p.running && late
          ? const SpeedTestProgress(
              phase: SpeedPhase.failed,
              error: 'The router stopped answering during the test.',
            )
          : p;
      if (!mounted || !_following) return;
      setState(() => _progress = shown);
      if (shown.running) return;
      _following = false;
      _poll?.cancel();
      if (shown.phase == SpeedPhase.done) await _remember(shown);
    }
  }

  Future<void> _cancel() async {
    _following = false;
    _poll?.cancel();
    setState(() => _progress = null);
    try {
      await _sh('killall ookla-speedtest 2>/dev/null; : > $_out');
    } catch (_) {}
  }

  Future<List<SpeedResult>> _loadHistory() async {
    final raw =
        (await SharedPreferences.getInstance()).getStringList(_historyKey) ??
        const [];
    return [for (final s in raw) ?_decode(s)];
  }

  static SpeedResult? _decode(String s) {
    try {
      return SpeedResult.fromJson(
        (jsonDecode(s) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _remember(SpeedTestProgress p) async {
    final r = SpeedResult(
      at: DateTime.now(),
      downMbps: p.downMbps ?? 0,
      upMbps: p.upMbps ?? 0,
      pingMs: p.pingMs,
      server: p.server,
    );
    final list = [r, ..._history].take(_keep).toList();
    await (await SharedPreferences.getInstance()).setStringList(_historyKey, [
      for (final h in list) jsonEncode(h.toJson()),
    ]);
    if (mounted) setState(() => _history = list.skip(1).toList());
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    final app = ref.watch(appStateProvider);
    final mobile =
        LuciModuleRegistry.instance
            .getModule('noobwrt_modem')
            ?.isAvailableOn(app.capabilities) ==
        true;
    return Scaffold(
      backgroundColor: ks.bg,
      appBar: AppBar(
        backgroundColor: ks.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ks.tx,
        titleSpacing: 0,
        title: Text('Back', style: KeystoneType.body(ks.mu)),
      ),
      body: SafeArea(
        top: false,
        child: SpeedView(
          progress: _progress,
          available: _available,
          mobileData: mobile,
          history: _history,
          onStart: _start,
          onCancel: _cancel,
        ),
      ),
    );
  }
}
