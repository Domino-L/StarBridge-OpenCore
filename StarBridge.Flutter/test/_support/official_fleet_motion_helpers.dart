// Exact test helper implementations extracted from the eight origins below.
// No controls, themes, gesture paths or expectations are replaced.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

// Origin: test/design_system/interaction/interaction_batch1_test.dart
ThemeData clientTheme(
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) {
  final tokens = FutureRestraintStyle.resolve(
    light ? AppearanceMode.light : AppearanceMode.dark,
  ).withReducedMotion(reduce);
  final theme = buildStarBridgeTheme(tokens, const Locale('en'));
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values,
      StarBridgeInteractionTheme(suite: suite),
    ],
  );
}

// Origin: test/design_system/interaction/interaction_batch2_test.dart
Widget app(
  Widget child, {
  required InteractionSuite suite,
  bool reduce = false,
  bool light = false,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  theme: clientTheme(suite, reduce: reduce, light: light),
  themeAnimationDuration: Duration.zero,
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: Center(child: child)),
);

// Origin: test/design_system/interaction/interaction_batch3h_test.dart
Widget fleetApp(
  Widget child, {
  required InteractionSuite suite,
  bool reduce = false,
  bool light = false,
}) {
  final base =
      app(child, suite: suite, locale: const Locale('zh', 'CN')) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    themeAnimationDuration: Duration.zero,
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(
        light ? AppearanceMode.light : AppearanceMode.dark,
      ).withReducedMotion(reduce),
      const Locale('zh', 'CN'),
      interactionSuite: suite,
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

// Origin: test/design_system/interaction/interaction_batch3i_test.dart
Widget scopedApp(
  Widget child,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) {
  final base = fleetApp(
    child,
    suite: suite,
    reduce: reduce,
    light: light,
  ) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: base.theme,
    themeAnimationDuration: Duration.zero,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    builder: (context, child) => StarBridgeInteractionConfiguration(
      suite: suite,
      reduceMotion: reduce,
      child: child!,
    ),
    home: base.home,
  );
}

// Origin: test/features/friends/social_layout_test.dart
void size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// Origin: test/features/friends/social_layout_test.dart
Future<void> loadFonts() async {
  for (final font in {
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
    'Saira': 'assets/fonts/Saira-VF.ttf',
    'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
    'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
  }.entries) {
    await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
  }
}

// Origin: test/design_system/interaction/interaction_batch3fv_directory_test.dart
Future<void> frames(WidgetTester t, [int count = 24]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

// Origin: test/design_system/interaction/interaction_batch3b_test.dart
List<SemanticsNode> exposedNodes(WidgetTester tester) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    // Merged descendants are internal data of their exposed ancestor, not
    // additional platform-accessible controls.
    if (node.isMergedIntoParent) return;
    nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(
    tester.binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!,
  );
  return nodes;
}
