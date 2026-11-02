import 'package:flutter/widgets.dart';

import '../../design_system/tokens/color_tokens.dart';
import 'app_preferences.dart';

enum AppPreferencesSource { defaults, stored, recoveredDefaults }

enum AppPreferencesFailure {
  hostUnavailable,
  timeout,
  invalidResponse,
  invalidValue,
  recoveredDefaults,
  readFailed,
  saveFailed,
  revisionConflict,
  outcomeUncertain,
  startupRegistrationFailed,
}

final class StoredAppPreferences {
  const StoredAppPreferences({
    required this.localeOverride,
    required this.appearanceMode,
    required this.motionPreference,
    this.interactionStyle = InteractionStyle.standard,
    this.applicationBehavior = ApplicationBehaviorPreferences.defaults,
    this.holidayAppearance = true,
  });

  final Locale? localeOverride;
  final AppearanceMode appearanceMode;
  final MotionPreference motionPreference;
  final InteractionStyle interactionStyle;
  final ApplicationBehaviorPreferences applicationBehavior;
  final bool holidayAppearance;

  StoredAppPreferences apply(AppPreferencesPatch patch) {
    return StoredAppPreferences(
      localeOverride: patch.includesLocaleOverride
          ? patch.localeOverride
          : localeOverride,
      appearanceMode: patch.appearanceMode ?? appearanceMode,
      motionPreference: patch.motionPreference ?? motionPreference,
      interactionStyle: patch.interactionStyle ?? interactionStyle,
      applicationBehavior: patch.applicationBehavior ?? applicationBehavior,
      holidayAppearance: patch.holidayAppearance ?? holidayAppearance,
    );
  }
}

final class AppPreferencesPatch {
  const AppPreferencesPatch({
    this.includesLocaleOverride = false,
    this.localeOverride,
    this.appearanceMode,
    this.motionPreference,
    this.interactionStyle,
    this.applicationBehavior,
    this.holidayAppearance,
  });

  const AppPreferencesPatch.locale(Locale? locale)
    : includesLocaleOverride = true,
      localeOverride = locale,
      appearanceMode = null,
      motionPreference = null,
      interactionStyle = null,
      applicationBehavior = null,
      holidayAppearance = null;

  const AppPreferencesPatch.appearance(AppearanceMode mode)
    : includesLocaleOverride = false,
      localeOverride = null,
      appearanceMode = mode,
      motionPreference = null,
      interactionStyle = null,
      applicationBehavior = null,
      holidayAppearance = null;

  const AppPreferencesPatch.motion(MotionPreference preference)
    : includesLocaleOverride = false,
      localeOverride = null,
      appearanceMode = null,
      motionPreference = preference,
      interactionStyle = null,
      applicationBehavior = null,
      holidayAppearance = null;

  const AppPreferencesPatch.applicationBehavior(
    ApplicationBehaviorPreferences behavior,
  ) : includesLocaleOverride = false,
      localeOverride = null,
      appearanceMode = null,
      motionPreference = null,
      interactionStyle = null,
      applicationBehavior = behavior,
      holidayAppearance = null;

  const AppPreferencesPatch.interaction(InteractionStyle style)
    : includesLocaleOverride = false,
      localeOverride = null,
      appearanceMode = null,
      motionPreference = null,
      interactionStyle = style,
      applicationBehavior = null,
      holidayAppearance = null;

  const AppPreferencesPatch.holidayAppearance(bool enabled)
    : includesLocaleOverride = false,
      localeOverride = null,
      appearanceMode = null,
      motionPreference = null,
      interactionStyle = null,
      applicationBehavior = null,
      holidayAppearance = enabled;

  final bool includesLocaleOverride;
  final Locale? localeOverride;
  final AppearanceMode? appearanceMode;
  final MotionPreference? motionPreference;
  final InteractionStyle? interactionStyle;
  final ApplicationBehaviorPreferences? applicationBehavior;
  final bool? holidayAppearance;

  bool get isEmpty =>
      !includesLocaleOverride &&
      appearanceMode == null &&
      motionPreference == null &&
      interactionStyle == null &&
      applicationBehavior == null &&
      holidayAppearance == null;
}

final class AppPreferencesReadResult {
  const AppPreferencesReadResult({
    required this.values,
    required this.revision,
    required this.source,
  });

  final StoredAppPreferences values;
  final int revision;
  final AppPreferencesSource source;
}

abstract interface class AppPreferencesStore {
  Future<AppPreferencesReadResult> read();

  Future<AppPreferencesReadResult> update(
    AppPreferencesPatch patch, {
    required int expectedRevision,
  });

  void dispose();
}

final class AppPreferencesStoreException implements Exception {
  const AppPreferencesStoreException(
    this.failure, {
    this.retryable = false,
    this.outcomeUncertain = false,
  });

  final AppPreferencesFailure failure;
  final bool retryable;
  final bool outcomeUncertain;
}
