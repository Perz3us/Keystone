// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HomeLayout { side, topDown }

enum HomePick { busiest, pinned }

enum SpeedUnit { mbps, mbs }

enum SignalItem { type, operatorName, rsrp, sinr, rsrq, bands, width }

const maxSignalItems = 4;

@immutable
class HomePrefs {
  const HomePrefs({
    this.layout = HomeLayout.side,
    this.deviceCount = 4,
    this.pick = HomePick.busiest,
    this.pinned = const [],
    this.flow = true,
    this.shortcuts = true,
    this.speed = true,
    this.chart = true,
    this.unit = SpeedUnit.mbps,
    this.usage = true,
    this.signalBars = true,
    this.beside = true,
    this.signal = false,
    this.signalNumbers = true,
    this.signalBar = true,
    this.signalList = false,
    this.idleCarriers = true,
    this.besideItems = const [
      SignalItem.type,
      SignalItem.rsrp,
      SignalItem.sinr,
      SignalItem.bands,
    ],
  });

  final HomeLayout layout;

  final int deviceCount;
  final HomePick pick;

  final List<String> pinned;

  final bool flow;
  final bool shortcuts;

  final bool speed;
  final bool chart;
  final SpeedUnit unit;

  final bool usage;

  final bool signalBars;
  final bool beside;
  final bool signal;
  final bool signalNumbers;
  final bool signalBar;
  final bool signalList;
  final bool idleCarriers;
  final List<SignalItem> besideItems;

  HomePrefs copyWith({
    HomeLayout? layout,
    int? deviceCount,
    HomePick? pick,
    List<String>? pinned,
    bool? flow,
    bool? shortcuts,
    bool? speed,
    bool? chart,
    SpeedUnit? unit,
    bool? usage,
    bool? signalBars,
    bool? beside,
    bool? signal,
    bool? signalNumbers,
    bool? signalBar,
    bool? signalList,
    bool? idleCarriers,
    List<SignalItem>? besideItems,
  }) => HomePrefs(
    layout: layout ?? this.layout,
    deviceCount: deviceCount ?? this.deviceCount,
    pick: pick ?? this.pick,
    pinned: pinned ?? this.pinned,
    flow: flow ?? this.flow,
    shortcuts: shortcuts ?? this.shortcuts,
    speed: speed ?? this.speed,
    chart: chart ?? this.chart,
    unit: unit ?? this.unit,
    usage: usage ?? this.usage,
    signalBars: signalBars ?? this.signalBars,
    beside: beside ?? this.beside,
    signal: signal ?? this.signal,
    signalNumbers: signalNumbers ?? this.signalNumbers,
    signalBar: signalBar ?? this.signalBar,
    signalList: signalList ?? this.signalList,
    idleCarriers: idleCarriers ?? this.idleCarriers,
    besideItems: besideItems ?? this.besideItems,
  );

  Map<String, dynamic> toJson() => {
    'layout': layout.name,
    'deviceCount': deviceCount,
    'pick': pick.name,
    'pinned': pinned,
    'flow': flow,
    'shortcuts': shortcuts,
    'speed': speed,
    'chart': chart,
    'unit': unit.name,
    'usage': usage,
    'signalBars': signalBars,
    'beside': beside,
    'signal': signal,
    'signalNumbers': signalNumbers,
    'signalBar': signalBar,
    'signalList': signalList,
    'idleCarriers': idleCarriers,
    'besideItems': [for (final i in besideItems) i.name],
  };

  factory HomePrefs.fromJson(Map<String, dynamic> j) {
    const d = HomePrefs();
    T pickEnum<T extends Enum>(List<T> all, Object? v, T fallback) =>
        all.where((e) => e.name == v).firstOrNull ?? fallback;
    return HomePrefs(
      layout: pickEnum(HomeLayout.values, j['layout'], d.layout),
      deviceCount: const [3, 4, 5].contains(j['deviceCount'])
          ? j['deviceCount'] as int
          : d.deviceCount,
      pick: pickEnum(HomePick.values, j['pick'], d.pick),
      pinned: [
        if (j['pinned'] is List)
          for (final m in j['pinned'] as List) m.toString().toLowerCase(),
      ],
      flow: j['flow'] is bool ? j['flow'] as bool : d.flow,
      shortcuts: j['shortcuts'] is bool ? j['shortcuts'] as bool : d.shortcuts,
      speed: j['speed'] is bool ? j['speed'] as bool : d.speed,
      chart: j['chart'] is bool ? j['chart'] as bool : d.chart,
      unit: pickEnum(SpeedUnit.values, j['unit'], d.unit),
      usage: j['usage'] is bool ? j['usage'] as bool : d.usage,
      signalBars: j['signalBars'] is bool
          ? j['signalBars'] as bool
          : d.signalBars,
      beside: j['beside'] is bool ? j['beside'] as bool : d.beside,
      signal: j['signal'] is bool ? j['signal'] as bool : d.signal,
      signalNumbers: j['signalNumbers'] is bool
          ? j['signalNumbers'] as bool
          : d.signalNumbers,
      signalBar: j['signalBar'] is bool ? j['signalBar'] as bool : d.signalBar,
      signalList: j['signalList'] is bool
          ? j['signalList'] as bool
          : d.signalList,
      idleCarriers: j['idleCarriers'] is bool
          ? j['idleCarriers'] as bool
          : d.idleCarriers,
      besideItems: j['besideItems'] is List
          ? [
              for (final i in SignalItem.values)
                if ((j['besideItems'] as List).contains(i.name)) i,
            ].take(maxSignalItems).toList()
          : d.besideItems,
    );
  }
}

class HomePrefsStore extends ValueNotifier<HomePrefs> {
  HomePrefsStore._() : super(const HomePrefs());
  static final instance = HomePrefsStore._();
  static const _key = 'home_prefs_v1';

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) value = HomePrefs.fromJson(j);
    } catch (_) {}
  }

  Future<void> save(HomePrefs p) async {
    value = p;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode(p.toJson()),
      );
    } catch (_) {}
  }
}
