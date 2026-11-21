import 'package:flutter/widgets.dart';

import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/tokens/color_tokens.dart';

enum MotionPreference { followSystem, reduce }

enum InteractionStyle { standard, rail, scan, glow }

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
    this.interactionStyle = InteractionStyle.scan,
    this.applicationBehavior = ApplicationBehaviorPreferences.defaults,
    this.holidayAppearance = true,
    this.performanceMode = false,
    this.readOwnHealth = false,
    this.readOwnHealthInBackground = false,
  });

  final Locale locale;
  final AppearanceMode appearanceMode;
  final String designStyleId;
  final MotionPreference motionPreference;
  final InteractionStyle interactionStyle;
  final ApplicationBehaviorPreferences applicationBehavior;

  /// 节日期间自动换上特别外观；关掉就一直是平时的样子。默认开。
  final bool holidayAppearance;

  /// 性能模式：开着时，检测到游戏运行就自动减少特效；没有游戏时保持完整效果。
  /// 关掉就一直画完整效果。默认关（用户 11-10 原话"性能模式默认关"）。
  final bool performanceMode;

  /// 读取自己的血量（截画面左下角头盔 HUD，只在本机）。单独开关，默认关。
  final bool readOwnHealth;

  /// 游戏在后台时也读取（读血的子开关，只在读血打开时起作用）。默认关（用户 11-13“默认关”）。
  final bool readOwnHealthInBackground;

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
    InteractionStyle? interactionStyle,
    ApplicationBehaviorPreferences? applicationBehavior,
    bool? holidayAppearance,
    bool? performanceMode,
    bool? readOwnHealth,
    bool? readOwnHealthInBackground,
  }) {
    return AppPreferences(
      locale: locale ?? this.locale,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      designStyleId: designStyleId ?? this.designStyleId,
      motionPreference: motionPreference ?? this.motionPreference,
      interactionStyle: interactionStyle ?? this.interactionStyle,
      applicationBehavior: applicationBehavior ?? this.applicationBehavior,
      holidayAppearance: holidayAppearance ?? this.holidayAppearance,
      performanceMode: performanceMode ?? this.performanceMode,
      readOwnHealth: readOwnHealth ?? this.readOwnHealth,
      readOwnHealthInBackground:
          readOwnHealthInBackground ?? this.readOwnHealthInBackground,
    );
  }
}
