import 'package:flutter/widgets.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/tokens/color_tokens.dart';

enum MotionPreference { followSystem, reduce }

@immutable
final class ApplicationBehaviorPreferences {
  const ApplicationBehaviorPreferences({
    required this.launchAtStartup,
    required this.keepRunningInBackground,
    required this.startMinimized,
    required this.startupChoiceMade,
    required this.closeBehaviorChoiceMade,
    required this.backgroundHintShown,
  });

  static const defaults = ApplicationBehaviorPreferences(
    launchAtStartup: false,
    keepRunningInBackground: true,
    startMinimized: false,
    startupChoiceMade: false,
    closeBehaviorChoiceMade: false,
    backgroundHintShown: false,
  );

  final bool launchAtStartup;
  final bool keepRunningInBackground;
  final bool startMinimized;
  final bool startupChoiceMade;
  final bool closeBehaviorChoiceMade;
  final bool backgroundHintShown;

  // Disabling startup suspends its effect, not the user's saved destination.
  ApplicationBehaviorPreferences normalize() => this;

  bool get shouldPromptForCloseBehavior => !closeBehaviorChoiceMade;

  ApplicationBehaviorPreferences copyWith({
    bool? launchAtStartup,
    bool? keepRunningInBackground,
    bool? startMinimized,
    bool? startupChoiceMade,
    bool? closeBehaviorChoiceMade,
    bool? backgroundHintShown,
  }) {
    return ApplicationBehaviorPreferences(
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      keepRunningInBackground:
          keepRunningInBackground ?? this.keepRunningInBackground,
      startMinimized: startMinimized ?? this.startMinimized,
      startupChoiceMade: startupChoiceMade ?? this.startupChoiceMade,
      closeBehaviorChoiceMade:
          closeBehaviorChoiceMade ?? this.closeBehaviorChoiceMade,
      backgroundHintShown: backgroundHintShown ?? this.backgroundHintShown,
    );
  }
}

@immutable
final class AppPreferences {
  const AppPreferences({
    required this.locale,
    required this.appearanceMode,
    required this.designStyleId,
    required this.motionPreference,
    this.applicationBehavior = ApplicationBehaviorPreferences.defaults,
  });

  final Locale locale;
  final AppearanceMode appearanceMode;
  final String designStyleId;
  final MotionPreference motionPreference;
  final ApplicationBehaviorPreferences applicationBehavior;

  static const defaults = AppPreferences(
    locale: Locale('zh', 'CN'),
    appearanceMode: AppearanceMode.dark,
    designStyleId: FutureRestraintStyle.id,
    motionPreference: MotionPreference.followSystem,
    applicationBehavior: ApplicationBehaviorPreferences.defaults,
  );

  AppPreferences copyWith({
    Locale? locale,
    AppearanceMode? appearanceMode,
    String? designStyleId,
    MotionPreference? motionPreference,
    ApplicationBehaviorPreferences? applicationBehavior,
  }) {
    return AppPreferences(
      locale: locale ?? this.locale,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      designStyleId: designStyleId ?? this.designStyleId,
      motionPreference: motionPreference ?? this.motionPreference,
      applicationBehavior: applicationBehavior ?? this.applicationBehavior,
    );
  }
}
