import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import 'app_preferences.dart';
import 'app_preferences_port.dart';
import 'app_preferences_projection.dart';
import 'app_preferences_store.dart';

final class InMemoryAppPreferences implements AppPreferencesPort {
  InMemoryAppPreferences({AppPreferences initial = AppPreferences.defaults})
    : _projection = ValueNotifier(
        AppPreferencesProjection(
          effective: initial,
          confirmed: StoredAppPreferences(
            localeOverride: initial.locale,
            appearanceMode: initial.appearanceMode,
            motionPreference: initial.motionPreference,
            applicationBehavior: initial.applicationBehavior,
          ),
          revision: 0,
          phase: AppPreferencesPhase.ready,
          operation: AppPreferencesOperation.idle,
          source: AppPreferencesSource.stored,
          failure: null,
        ),
      );

  final ValueNotifier<AppPreferencesProjection> _projection;

  @override
  ValueListenable<AppPreferencesProjection> get projection => _projection;

  @override
  Future<bool> setAppearanceMode(AppearanceMode mode) async {
    _set(_projection.value.effective.copyWith(appearanceMode: mode));
    return true;
  }

  @override
  Future<bool> setLocale(Locale locale) async {
    _set(_projection.value.effective.copyWith(locale: locale));
    return true;
  }

  @override
  Future<bool> setMotionPreference(MotionPreference preference) async {
    _set(_projection.value.effective.copyWith(motionPreference: preference));
    return true;
  }

  @override
  Future<bool> setApplicationBehavior(
    ApplicationBehaviorPreferences behavior,
  ) async {
    _set(
      _projection.value.effective.copyWith(
        applicationBehavior: behavior.normalize(),
      ),
    );
    return true;
  }

  void _set(AppPreferences effective) {
    final current = _projection.value;
    _projection.value = AppPreferencesProjection(
      effective: effective,
      confirmed: StoredAppPreferences(
        localeOverride: effective.locale,
        appearanceMode: effective.appearanceMode,
        motionPreference: effective.motionPreference,
        applicationBehavior: effective.applicationBehavior,
      ),
      revision: (current.revision ?? 0) + 1,
      phase: AppPreferencesPhase.ready,
      operation: AppPreferencesOperation.idle,
      source: AppPreferencesSource.stored,
      failure: null,
    );
  }

  @override
  Future<bool> retry() async => true;

  @override
  void dispose() => _projection.dispose();
}
