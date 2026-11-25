// SPDX-License-Identifier: GPL-3.0-or-later

enum CallDir { incoming, outgoing }

class PhoneCall {
  final int start;
  final String number;
  final CallDir dir;
  int? connected;
  int? end;
  String? status;

  PhoneCall(this.start, this.number, this.dir);

  Duration? get talked => (connected != null && end != null)
      ? Duration(seconds: end! - connected!)
      : null;
}

List<PhoneCall> parseCallLog(String text, {bool live = false}) {
  final calls = <PhoneCall>[];
  final open = <String, PhoneCall>{};
  final re = RegExp(r'^(\d+) (\S+) ?(.*)$');

  void close(PhoneCall c, int? t, [String? status]) {
    c.end = t;
    c.status =
        status ??
        (c.connected != null
            ? 'answered'
            : (c.dir == CallDir.incoming ? 'missed' : 'cancelled'));
    open.remove(c.number);
  }

  void closeAll(int? t) {
    for (final c in open.values.toList()) {
      close(c, t);
    }
  }

  PhoneCall start(int t, String num, CallDir dir) {
    final prev = open[num];
    if (prev != null) close(prev, null);
    final c = PhoneCall(t, num, dir);
    calls.add(c);
    open[num] = c;
    return c;
  }

  for (final line in text.split('\n')) {
    final m = re.firstMatch(line.trim());
    if (m == null) continue;
    final t = int.parse(m[1]!);
    final ev = m[2]!;
    final num = m[3]!.trim();
    var c = open[num];

    switch (ev) {
      case 'dial':
        closeAll(null);
        start(t, num, CallDir.outgoing);
      case 'incoming':
        closeAll(null);
        start(t, num, CallDir.incoming);
      case 'waiting':
        start(t, num, CallDir.incoming);
      case 'blocked':
        calls.add(
          PhoneCall(t, num, CallDir.incoming)
            ..end = t
            ..status = 'blocked',
        );
      case 'connected' || 'answered' || 'switched' || 'retrieved':
        c ??= start(
          t,
          num,
          ev == 'connected' ? CallDir.outgoing : CallDir.incoming,
        );
        c.connected ??= t;
      case 'failed' || 'missed' || 'elsewhere':
        if (c != null) close(c, t, ev);
      case 'hangup':
        if (c != null) close(c, t);
      case 'ended':
        if (c != null) close(c, t);
        closeAll(t);
    }
  }

  for (final c in open.values.toList()) {
    if (live) {
      c.status = 'active';
    } else {
      close(c, null);
    }
  }
  return calls.reversed.toList();
}
