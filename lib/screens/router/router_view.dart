import 'package:flutter/material.dart';
import 'package:yet_another_luci_app/design/keystone_tokens.dart';
import 'package:yet_another_luci_app/models/router_lights.dart';
import 'package:yet_another_luci_app/screens/router/light_meanings.dart';
import 'package:yet_another_luci_app/widgets/keystone/router_drawing.dart';
import 'package:yet_another_luci_app/widgets/keystone/speed_chart.dart';

class RouterView extends StatelessWidget {
  const RouterView({
    super.key,
    required this.name,
    this.model,
    this.firmware,
    this.upLine,
    required this.lights,
    required this.rows,
    this.onReboot,
    this.onNightLights,
    this.health = const [],
    this.temps = const [],
    this.storage = const [],
    this.cpuSamples = const [],
    this.memSamples = const [],
    this.onLogs,
    this.onPowerOptions,
  });

  final String name;
  final String? model;
  final String? firmware;
  final String? upLine;
  final RouterLights lights;
  final List<LightRow> rows;
  final VoidCallback? onReboot;

  final VoidCallback? onNightLights;

  final List<RouterGauge> health;

  final List<(String, String)> temps;

  final List<RouterGauge> storage;

  final List<double> cpuSamples;
  final List<double> memSamples;

  final VoidCallback? onLogs;

  final VoidCallback? onPowerOptions;

  static Color _dot(LightColor c) => switch (c) {
    LightColor.green => KeystoneColors.ledGreen,
    LightColor.red => KeystoneColors.ledRed,
    LightColor.blue => KeystoneColors.ledBlue,
    LightColor.off => KeystoneColors.ledOff,
  };

  Future<void> _confirmReboot(BuildContext context) async {
    final ks = context.ks;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: ks.sheet,
        title: Text('Restart $name?', style: KeystoneType.sheetTitle(ks.tx)),
        content: Text(
          'Everything loses the internet for about a minute while it starts '
          'up again.',
          style: KeystoneType.body(ks.tx2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text('Cancel', style: KeystoneType.body(ks.tx)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('Restart', style: KeystoneType.body(ks.bad)),
          ),
        ],
      ),
    );
    if (ok == true) onReboot?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Row(
          children: [
            const Spacer(),
            if (onReboot != null || onLogs != null || onPowerOptions != null)
              PopupMenuButton<VoidCallback>(
                tooltip: 'More',
                icon: Icon(Icons.more_horiz_rounded, color: ks.mu),
                color: ks.sheet,
                onSelected: (f) => f(),
                itemBuilder: (_) => [
                  for (final (label, f) in [
                    if (onReboot != null)
                      ('Restart router', () => _confirmReboot(context)),
                    if (onPowerOptions != null)
                      ('Other firmware or power off', onPowerOptions!),
                    if (onLogs != null) ('Logs', onLogs!),
                  ])
                    PopupMenuItem(
                      value: f,
                      child: Text(label, style: KeystoneType.body(ks.tx)),
                    ),
                ],
              ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RouterDrawing(model: model, lights: lights, width: 64),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: KeystoneType.title(ks.tx)),
                  if (firmware != null)
                    Text(firmware!, style: KeystoneType.secondary(ks.mu)),
                  if (upLine != null)
                    Text(upLine!, style: KeystoneType.secondary(ks.mu)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: Text(
                'What the lights say',
                style: KeystoneType.bodyStrong(ks.tx),
              ),
            ),
            if (lights.anyLit) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: ks.ok, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('Live', style: KeystoneType.caption(ks.mu)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (!lights.anyLit)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              "Keystone can't read this router's lights.",
              style: KeystoneType.body(ks.mu),
            ),
          )
        else
          for (final r in rows)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ks.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _dot(r.color),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.name, style: KeystoneType.body(ks.tx)),
                        Text(r.meaning, style: KeystoneType.caption(ks.mu)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        if (health.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Health', style: KeystoneType.bodyStrong(ks.tx)),
          const SizedBox(height: 10),
          for (final g in health) _Bar(g),
          if (cpuSamples.length > 1) ...[
            SizedBox(
              height: 72,
              child: SpeedChart(down: cpuSamples, up: memSamples, max: 100),
            ),
            const SizedBox(height: 6),
            Text(
              'Processor, solid · memory, dotted · since you opened this',
              style: KeystoneType.caption(ks.mu),
            ),
            const SizedBox(height: 8),
          ],
          if (temps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text('Temperature', style: KeystoneType.caption(ks.mu)),
            ),
          for (final (name, value) in temps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(child: Text(name, style: KeystoneType.body(ks.tx))),
                  Text(value, style: KeystoneType.secondary(ks.mu)),
                ],
              ),
            ),
        ],
        if (storage.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('Storage', style: KeystoneType.bodyStrong(ks.tx)),
          const SizedBox(height: 10),
          for (final g in storage) _Bar(g),
        ],
        if (onNightLights != null)
          InkWell(
            onTap: onNightLights,
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.only(top: 14, bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lights at night',
                          style: KeystoneType.body(ks.tx),
                        ),
                        Text(
                          'Turn them off at night in Router Tools',
                          style: KeystoneType.caption(ks.mu),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: ks.mu),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class RouterGauge {
  const RouterGauge(this.label, this.value, this.fraction, {this.detail});
  final String label;
  final String value;
  final double fraction;

  final String? detail;
}

class _Bar extends StatelessWidget {
  const _Bar(this.g);
  final RouterGauge g;

  @override
  Widget build(BuildContext context) {
    final ks = context.ks;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(g.label, style: KeystoneType.body(ks.tx))),
              Text(g.value, style: KeystoneType.secondary(ks.mu)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: g.fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: ks.line,
              color: g.fraction >= 0.9
                  ? ks.bad
                  : g.fraction >= 0.75
                  ? ks.warn
                  : ks.ac,
            ),
          ),
          if (g.detail != null) ...[
            const SizedBox(height: 4),
            Text(g.detail!, style: KeystoneType.caption(ks.mu)),
          ],
        ],
      ),
    );
  }
}

List<(String, String)> temperatureGroups(List<(String, double)> sensors) {
  const order = ['Processor', 'Network engine', 'Wi-Fi', 'Modem', 'Other'];
  String group(String name) {
    final n = name.toLowerCase();
    bool has(List<String> w) => w.any(n.contains);
    if (has(['wcss', 'wi-fi', 'wifi', 'radio', 'phy', 'ath'])) return 'Wi-Fi';
    if (has(['nss'])) return 'Network engine';
    if (has(['modem', 'mdm', 'sdx', '5g', 'qmi'])) return 'Modem';
    if (has(['cpu', 'soc', 'cluster', 'apss', 'core', 'tsens'])) {
      return 'Processor';
    }
    return 'Other';
  }

  final hot = <String, double>{};
  for (final (name, c) in sensors) {
    final g = group(name);
    if (c > (hot[g] ?? double.negativeInfinity)) hot[g] = c;
  }
  return [
    for (final g in order)
      if (hot[g] case final c?) (g, '${c.round()}°C'),
  ];
}
