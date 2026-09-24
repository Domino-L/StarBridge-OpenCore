import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import 'app_preferences.dart';
import 'app_preferences_port.dart';
import 'app_preferences_projection.dart';
import 'app_preferences_store.dart';

@Deprecated('Use one root AppPreferencesModule and detach its store instead.')
final class HostUnavailableAppPreferences implements AppPreferencesPort {
  HostUnavailableAppPreferences()
    : _projection = ValueNotifier(
        const AppPreferencesProjection(
          effective: AppPreferences.defaults,
          confirmed: null,
          revision: null,
          phase: AppPreferencesPhase.unavailable,
          operation: AppPreferencesOperation.idle,
          source: null,
          failure: AppPreferencesFailure.hostUnavailable,
        ),
      );

  final ValueNotifier<AppPreferencesProjection> _projection;

  @override
  ValueListenable<AppPreferencesProjection> get projection => _projection;

  @override
  Future<bool> retry() async => false;

  @override
  Future<bool> setAppearanceMode(AppearanceMode mode) async => false;

  @override
  Future<bool> setLocale(Locale locale) async => false;

  @override
  Future<bool> setMotionPreference(MotionPreference preference) async => false;

  @override
  Future<bool> setApplicationBehavior(
    ApplicationBehaviorPreferences behavior,
  ) async => false;

  @override
  void dispose() => _projection.dispose();
}
