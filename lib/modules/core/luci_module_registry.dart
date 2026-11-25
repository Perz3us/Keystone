// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import '../../models/router_capabilities.dart';
import 'luci_module.dart';
import '../built_in_modules.dart';

class LuciModuleRegistry extends ChangeNotifier {
  static final LuciModuleRegistry _instance = LuciModuleRegistry._internal();
  factory LuciModuleRegistry() => _instance;
  LuciModuleRegistry._internal();

  static LuciModuleRegistry get instance => _instance;

  final Map<String, LuciModule> _modules = {};
  bool _isAutoInitializing = false;

  void _ensureInitialized() {
    if (_modules.isEmpty && !_isAutoInitializing) {
      _isAutoInitializing = true;
      registerBuiltInModules();
      _isAutoInitializing = false;
    }
  }

  void registerModules(List<LuciModule> modules) {
    bool addedAny = false;
    for (final module in modules) {
      if (!_modules.containsKey(module.id)) {
        _modules[module.id] = module;
        module.initialize();
        addedAny = true;
      }
    }
    if (addedAny) {
      notifyListeners();
    }
  }

  void registerModule(LuciModule module) {
    if (_modules.containsKey(module.id)) {
      return;
    }
    _modules[module.id] = module;
    module.initialize();
    notifyListeners();
  }

  void unregisterModule(String id) {
    final module = _modules.remove(id);
    if (module != null) {
      module.dispose();
      notifyListeners();
    }
  }

  LuciModule? getModule(String id) {
    _ensureInitialized();
    return _modules[id];
  }

  List<LuciModule> get allModules {
    _ensureInitialized();
    final list = _modules.values.toList();
    list.sort((a, b) => a.priority.compareTo(b.priority));
    return list;
  }

  List<LuciModule> get enabledModules {
    return allModules.where((m) => m.isEnabled).toList();
  }

  List<LuciModule> enabledModulesFor(RouterCapabilities? caps) =>
      enabledModules.where((m) => m.isAvailableOn(caps)).toList();

  List<LuciModule> getModulesByCategory(LuciModuleCategory category) {
    return enabledModules.where((m) => m.category == category).toList();
  }

  List<LuciModule> get bottomNavModules {
    return enabledModules.where((m) => m.showInBottomNav).toList();
  }

  void clear() {
    for (final module in _modules.values) {
      module.dispose();
    }
    _modules.clear();
    notifyListeners();
  }
}
