// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:shared_preferences/shared_preferences.dart';

const _key = 'experimental_features';

Future<bool> loadExperimental() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> saveExperimental(bool on) async =>
    (await SharedPreferences.getInstance()).setBool(_key, on);
