import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_screen_switch.dart';

class _Counter extends StatefulWidget {
  const _Counter();
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;
  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('lower-counter'),
    onPressed: () => setState(() => taps++),
    child: Text('lower $taps'),
  );
}

Widget _app(bool lower, {bool reduceMotion = false}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  supportedLocales: const [Locale('zh', 'CN')],
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('zh', 'CN'),
  ),
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: OfficialFleetScreenSwitch(
        lower: lower,
        upper: (_) => const Center(child: Text('upper')),
        lowerBuilder: (_) => const Center(child: _Counter()),
        banner: null,
        bannerHeight: 300,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'switching is animated, never a hard cut, and keeps lower state',
    (tester) async {
      await tester.pumpWidget(_app(false));
      await tester.pump();
      expect(find.text('upper'), findsOneWidget);
      expect(find.byKey(const Key('lower-counter')), findsNothing);

      await tester.pumpWidget(_app(true));
      await tester.pump(OfficialFleetScreenSwitch.duration ~/ 2);
      // Halfway: both screens are on stage and neither takes input.
      expect(find.text('upper'), findsOneWidget);
      expect(find.byKey(const Key('lower-counter')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('upper'),
          matching: find.byWidgetPredicate(
            (w) => w is IgnorePointer && w.ignoring,
          ),
        ),
        findsWidgets,
      );

      await tester.pumpAndSettle();
      expect(find.text('upper'), findsNothing);
      await tester.tap(find.byKey(const Key('lower-counter')));
      await tester.pump();
      expect(find.text('lower 1'), findsOneWidget);

      // Back up and down again: the lower screen is rebuilt fresh only after
      // it fully left; while it stays, its state is kept.
      await tester.pumpWidget(_app(false));
      await tester.pump(OfficialFleetScreenSwitch.duration ~/ 4);
      expect(find.text('lower 1'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('lower-counter')), findsNothing);
      expect(find.text('upper'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion switches at once', (tester) async {
    await tester.pumpWidget(_app(false, reduceMotion: true));
    await tester.pump();
    await tester.pumpWidget(_app(true, reduceMotion: true));
    await tester.pump();
    expect(find.text('upper'), findsNothing);
    expect(find.byKey(const Key('lower-counter')), findsOneWidget);
  });

  Widget counted(bool lower, void Function() built) => MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(AppearanceMode.dark),
      const Locale('zh', 'CN'),
    ),
    home: Scaffold(
      body: OfficialFleetScreenSwitch(
        lower: lower,
        upper: (_) {
          built();
          return const Center(child: Text('upper'));
        },
        lowerBuilder: (_) => const Center(child: _Counter()),
        banner: null,
        bannerHeight: 300,
      ),
    ),
  );

  testWidgets('the upper screen stays hidden and is not built per frame', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(counted(false, () => builds++));
    await tester.pumpAndSettle();
    await tester.pumpWidget(counted(true, () => builds++));
    await tester.pumpAndSettle();
    expect(find.text('upper'), findsNothing);
    expect(find.text('upper', skipOffstage: false), findsOneWidget);
    final hidden = builds;
    await tester.pumpWidget(counted(false, () => builds++));
    await tester.pumpAndSettle();
    expect(find.text('upper'), findsOneWidget);
    // A few for the parent's own rebuilds, not one per animation frame.
    expect(builds - hidden, lessThan(5));
  });

  testWidgets('a screen never opened is not built while hidden', (tester) async {
    var builds = 0;
    await tester.pumpWidget(counted(true, () => builds++));
    await tester.pumpAndSettle();
    expect(builds, 0);
  });
}
