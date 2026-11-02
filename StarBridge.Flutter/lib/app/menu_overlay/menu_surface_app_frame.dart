import 'menu_overlay_locale.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design_system/appearance/appearance_scope.dart';
import '../../design_system/scrolling/starbridge_scroll_behavior.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../platform/window/menu_interaction_presentation.dart';
import '../localization/app_strings.dart';
import 'menu_holiday.dart';
import 'menu_overlay_theme.dart';
import 'menu_overlay_frame.dart';
import 'menu_tool_page.dart';
export 'menu_tool_page.dart' show MenuToolPageOpener;

/// The original non-workspace chrome, without transport or lifecycle ownership.
class MenuSurfaceFallback extends StatelessWidget {
  const MenuSurfaceFallback({
    required this.contextLabel,
    required this.returnLabel,
    required this.settingsLabel,
    required this.onReturn,
    super.key,
  });
  final String contextLabel, returnLabel, settingsLabel;
  final VoidCallback onReturn;
  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {const SingleActivator(LogicalKeyboardKey.escape): onReturn},
    child: Focus(
      autofocus: true,
      child: MenuOverlayFrame(
        contextLabel: contextLabel,
        returnLabel: returnLabel,
        settingsLabel: settingsLabel,
        onReturn: onReturn,
        tools: const [],
      ),
    ),
  );
}

/// Auxiliary engine chrome only; no primary bootstrap or business ownership.
class MenuSurfaceAppFrame extends StatelessWidget {
  const MenuSurfaceAppFrame({
    required this.observer,
    required this.child,
    this.interaction = MenuInteractionPresentation.defaults,
    this.toolPages,
    super.key,
  });
  final NavigatorObserver observer;
  final Widget child;
  final MenuInteractionPresentation interaction;
  final MenuToolPageOpener? toolPages;

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorObservers: [observer],
    scrollBehavior: const StarBridgeScrollBehavior(),
    debugShowCheckedModeBanner: false,
    locale: menuOverlayLocale(interaction.language),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStringsDelegate(),
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: buildMenuOverlayTheme(
      menuOverlayLocale(interaction.language),
      reduceMotion: interaction.reduceMotion,
      interactionSuite: interactionSuiteFromName(interaction.style.name),
    ),
    builder: (context, child) => AppearanceScope(
      layers: menuAppearanceLayers(interaction.holiday),
      child: StarBridgeInteractionConfiguration(
        suite: interactionSuiteFromName(interaction.style.name),
        reduceMotion: interaction.reduceMotion,
        child: MenuToolPageScope(opener: toolPages, child: child!),
      ),
    ),
    home: child,
  );
}
