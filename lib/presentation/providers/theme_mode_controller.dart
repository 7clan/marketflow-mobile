import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'infrastructure_providers.dart';

/// The app's theme mode, persisted across launches.
///
/// This is a UI preference, not marketplace state: it lives as a small
/// presentation-local controller (still a provider — widgets stay stateless
/// with regard to it) and is stored in [SharedPreferences] best-effort.
final themeModeControllerProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  static const String _storageKey = 'marketflow.theme_mode';

  @override
  ThemeMode build() {
    // The preference must survive losing all listeners — leaving the profile
    // tab must not reset the theme.
    ref.keepAlive();

    final preferences = ref.watch(sharedPreferencesProvider);
    final index = preferences.getInt(_storageKey);
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  /// Applies [mode] and persists it (best effort — a failed write never
  /// changes the in-memory preference).
  void setMode(ThemeMode mode) {
    if (mode == state) return;
    state = mode;
    unawaited(
      ref.read(sharedPreferencesProvider).setInt(_storageKey, mode.index),
    );
  }
}
