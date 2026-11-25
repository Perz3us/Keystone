import 'dart:convert';

enum SpeedPhase { starting, ping, download, upload, done, failed }

double _mbps(Object? bytesPerSecond) =>
    bytesPerSecond is num ? bytesPerSecond * 8 / 1e6 : 0;

double? _num(Object? v) => v is num ? v.toDouble() : null;

class SpeedTestProgress {
  const SpeedTestProgress({
    this.phase = SpeedPhase.starting,
    this.liveMbps = 0,
    this.progress = 0,
    this.pingMs,
    this.jitterMs,
    this.downMbps,
    this.upMbps,
    this.packetLoss,
    this.isp,
    this.server,
    this.resultUrl,
    this.error,
    this.externalIp,
    this.downSamples = const [],
    this.upSamples = const [],
    this.downLoadedPingMs,
    this.upLoadedPingMs,
  });

  final SpeedPhase phase;

  final double liveMbps;

  final double progress;
  final double? pingMs;
  final double? jitterMs;
  final double? downMbps;
  final double? upMbps;
  final double? packetLoss;
  final String? isp;
  final String? server;
  final String? resultUrl;
  final String? error;

  final String? externalIp;

  final List<double> downSamples;
  final List<double> upSamples;

  final double? downLoadedPingMs;
  final double? upLoadedPingMs;

  static const maxSamples = 60;

  bool get running => phase != SpeedPhase.done && phase != SpeedPhase.failed;

  static SpeedTestProgress parse(String output) {
    var phase = SpeedPhase.starting;
    var live = 0.0, progress = 0.0;
    double? ping, jitter, down, up, loss;
    String? isp, server, url, error, ip;
    double? downLoaded, upLoaded;
    final downs = <double>[], ups = <double>[];

    final lines = output.split('\n');
    final complete = output.endsWith('\n')
        ? lines
        : lines.take(lines.length - 1);
    for (final line
        in complete.map((l) => l.trim()).where((l) => l.isNotEmpty)) {
      Object? j;
      try {
        j = jsonDecode(line);
      } catch (_) {
        return SpeedTestProgress(phase: SpeedPhase.failed, error: line);
      }
      if (j is! Map) continue;
      String? where(Object? s) {
        if (s is! Map) return null;
        return [s['name'], s['location']].whereType<String>().join(' · ');
      }

      switch (j['type']) {
        case 'testStart':
          isp = j['isp']?.toString();
          server = where(j['server']);
          ip = j['interface']?['externalIp']?.toString();
        case 'ping':
          phase = SpeedPhase.ping;
          ping = _num(j['ping']?['latency']) ?? ping;
          jitter = _num(j['ping']?['jitter']) ?? jitter;
          progress = _num(j['ping']?['progress']) ?? 0;
        case 'download':
          phase = SpeedPhase.download;
          live = _mbps(j['download']?['bandwidth']);
          down = live;
          downs.add(live);
          downLoaded = _num(j['download']?['latency']?['iqm']) ?? downLoaded;
          progress = _num(j['download']?['progress']) ?? 0;
        case 'upload':
          phase = SpeedPhase.upload;
          live = _mbps(j['upload']?['bandwidth']);
          up = live;
          ups.add(live);
          upLoaded = _num(j['upload']?['latency']?['iqm']) ?? upLoaded;
          progress = _num(j['upload']?['progress']) ?? 0;
        case 'result':
          phase = SpeedPhase.done;
          ping = _num(j['ping']?['latency']) ?? ping;
          jitter = _num(j['ping']?['jitter']) ?? jitter;
          down = _mbps(j['download']?['bandwidth']);
          up = _mbps(j['upload']?['bandwidth']);
          loss = _num(j['packetLoss']);
          isp = j['isp']?.toString() ?? isp;
          server = where(j['server']) ?? server;
          url = j['result']?['url']?.toString();
          ip = j['interface']?['externalIp']?.toString() ?? ip;
          downLoaded = _num(j['download']?['latency']?['iqm']) ?? downLoaded;
          upLoaded = _num(j['upload']?['latency']?['iqm']) ?? upLoaded;
          progress = 1;
        case 'log' when j['level'] == 'error':
          phase = SpeedPhase.failed;
          error = j['message']?.toString();
      }
      if (phase == SpeedPhase.failed) break;
    }
    return SpeedTestProgress(
      phase: phase,
      liveMbps: live,
      progress: progress,
      pingMs: ping,
      jitterMs: jitter,
      downMbps: down,
      upMbps: up,
      packetLoss: loss,
      isp: isp,
      server: server,
      resultUrl: url,
      error: error,
      externalIp: ip,
      downSamples: _thin(downs),
      upSamples: _thin(ups),
      downLoadedPingMs: downLoaded,
      upLoadedPingMs: upLoaded,
    );
  }

  static List<double> _thin(List<double> v) {
    if (v.length <= maxSamples) return v;
    final step = v.length / maxSamples;
    return [for (var i = 0; i < maxSamples; i++) v[(i * step).floor()]];
  }
}

class SpeedResult {
  const SpeedResult({
    required this.at,
    required this.downMbps,
    required this.upMbps,
    this.pingMs,
    this.server,
  });

  final DateTime at;
  final double downMbps;
  final double upMbps;
  final double? pingMs;
  final String? server;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'down': downMbps,
    'up': upMbps,
    'ping': pingMs,
    'server': server,
  };

  factory SpeedResult.fromJson(Map<String, Object?> j) => SpeedResult(
    at: DateTime.parse(j['at']! as String),
    downMbps: (j['down']! as num).toDouble(),
    upMbps: (j['up']! as num).toDouble(),
    pingMs: (j['ping'] as num?)?.toDouble(),
    server: j['server'] as String?,
  );
}
