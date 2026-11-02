import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_copy.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_panel.dart';
import 'package:starbridge_flutter/features/hangar/ship_specifications_port.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/hangar/ship_specifications_test.dart'
    as fixtures
    show Port, ship, specs;
import 'interaction_batch3fc_visibility_test.dart'
    show activateVisibility, visibilityFrames;
import 'interaction_batch3i_test.dart' show scopedApp;

class SpecificationsPort extends fixtures.Port {
  final ships = <LocalHangarShip>[];
  final sources = <InteractionSource>[];
  @override
  Future<ShipSpecifications> specificationsFor(
    LocalHangarShip ship, {
    bool refresh = false,
  }) {
    ships.add(ship);
    sources.add(currentStarBridgeActivationSource);
    return super.specificationsFor(ship, refresh: refresh);
  }
}

class SpecificationsProbe {
  SpecificationsProbe(this.suite);
  InteractionSuite suite;
  SpecificationsPort provider = SpecificationsPort();
  LocalHangarShip ship = fixtures.ship;
  bool reduce = false, light = false, away = false;
  double width = 560;
  ScrollController? scrollController;
  final bucket = PageStorageBucket();
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        away
            ? const Text('away')
            : Semantics(
                explicitChildNodes: true,
                child: SizedBox(
                  width: width,
                  child: PageStorage(
                    bucket: bucket,
                    child: SingleChildScrollView(
                      key: const PageStorageKey('spec-test-scroll'),
                      controller: scrollController,
                      child: ShipSpecificationsPanel(
                        ship: ship,
                        provider: provider,
                      ),
                    ),
                  ),
                ),
              ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<SpecificationsProbe> mountSpecifications(
  WidgetTester t,
  InteractionSuite suite,
) async {
  size(t, const Size(1100, 1200));
  final p = SpecificationsProbe(suite);
  await t.pumpWidget(p.app());
  await visibilityFrames(t);
  expect(p.provider.requests, hasLength(1));
  expect(p.provider.refreshes, [false]);
  return p;
}

Finder specificationsAction() => find.byKey(const Key('ship-spec-refresh'));
bool specificationsEnabled(WidgetTester t) =>
    t
        .widget<StarBridgeActionButton>(
          find.ancestor(
            of: specificationsAction(),
            matching: find.byType(StarBridgeActionButton),
          ),
        )
        .onActivate !=
    null;

Finder specificationsGroup(String id) => find.byKey(ValueKey('ship-spec-$id'));
Finder specificationsHeader(String id) => find
    .descendant(
      of: specificationsGroup(id),
      matching: find.byType(SuitePressable),
    )
    .first;
SuiteExpander specificationsExpander(WidgetTester t, String id) =>
    t.widget<SuiteExpander>(
      find.descendant(
        of: specificationsGroup(id),
        matching: find.byType(SuiteExpander),
      ),
    );
LocalHangarCopy specificationsCopy(WidgetTester t) =>
    LocalHangarCopy(t.element(find.byType(ShipSpecificationsPanel)));

Future<void> useSpecificationsHeader(
  WidgetTester t,
  String id,
  String input,
) async {
  var target = specificationsHeader(id);
  if (input == 'reader') {
    final label = t.widget<SuitePressable>(target).semanticLabel!;
    target = find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$'));
    expect(target, findsOneWidget);
  }
  await activateSpecifications(t, target, input);
}

Future<void> activateSpecifications(
  WidgetTester t,
  Finder target,
  String input,
) async {
  if (input != 'keyboard') {
    await activateVisibility(t, target, input);
    return;
  }
  await t.ensureVisible(target);
  await visibilityFrames(t);
  final control = t.widget(target);
  final node = switch (control) {
    ButtonStyleButton button => button.focusNode!,
    SuitePressable pressable => pressable.focusNode!,
    _ => throw StateError('Unsupported specifications target $control'),
  };
  // Reset the traversal origin after a pending refresh disables its old
  // focused button, then exercise real Tab/Enter rather than calling an action.
  expect(node.canRequestFocus, isTrue);
  FocusScope.of(t.element(target)).unfocus();
  await t.pump();
  await t.pump();
  for (var i = 0; !node.hasPrimaryFocus && i < 64; i++) {
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.pump();
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason:
        'target=$node hasFocus=${node.hasFocus} '
        'canRequestFocus=${node.canRequestFocus} '
        'skipTraversal=${node.skipTraversal}\n'
        '${FocusManager.instance.toStringDeep()}',
  );
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await visibilityFrames(t);
}

void expectSpecificationsWait(
  WidgetTester t,
  InteractionSuite suite,
  String input, {
  bool reduced = false,
}) {
  expect(find.text(specificationsCopy(t).specsLoading), findsOneWidget);
  if (suite == InteractionSuite.standard || input != 'pointer' || reduced) {
    expect(find.byType(SuiteProgressBar), findsNothing);
  } else {
    expect(find.byType(SuiteProgressBar), findsOneWidget);
  }
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(LinearProgressIndicator), findsNothing);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite specifications $input initial read follows actual opening route',
        (t) async {
          size(t, const Size(1100, 1200));
          final semantics = t.ensureSemantics();
          final provider = SpecificationsPort();
          StarBridgeDialogRoute<void>? route;
          try {
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => StarBridgeActionButton(
                    controlKey: const Key('specifications-open'),
                    onActivate: (source) => showStarBridgeDialog<void>(
                      context,
                      source: source,
                      onRouteCreated: (value) => route = value,
                      builder: (_) => Semantics(
                        scopesRoute: true,
                        explicitChildNodes: true,
                        child: Dialog(
                          child: SizedBox(
                            width: 560,
                            child: SingleChildScrollView(
                              child: ShipSpecificationsPanel(
                                ship: fixtures.ship,
                                provider: provider,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open specifications'),
                  ),
                ),
                suite,
                reduce: false,
              ),
            );
            await visibilityFrames(t);
            expect(
              find.byKey(const Key('specifications-open')),
              findsOneWidget,
            );
            await activateSpecifications(
              t,
              find.byKey(const Key('specifications-open')),
              input,
            );
            expect(provider.requests, hasLength(1));
            expect(provider.refreshes, [false]);
            expect(specificationsEnabled(t), isFalse);
            expectSpecificationsWait(t, suite, input);
            route!.navigator!.removeRoute(route!);
            await visibilityFrames(t);
            provider.requests.single.complete(fixtures.specs);
            await visibilityFrames(t);
            expect(find.byType(ShipSpecificationsPanel), findsNothing);
            expect(provider.requests, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite specifications $input refresh failure retains data and explicit retry recovers',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountSpecifications(t, suite);
            expect(specificationsEnabled(t), isFalse);
            expectSpecificationsWait(t, suite, 'pointer');
            p.provider.requests.single.complete(fixtures.specs);
            await visibilityFrames(t);
            expect(find.text('0 SCU'), findsOneWidget);
            expect(specificationsEnabled(t), isTrue);
            await activateSpecifications(t, specificationsAction(), input);
            expect(p.provider.refreshes, [false, true]);
            expect(p.provider.ships, [fixtures.ship, fixtures.ship]);
            expect(
              p.provider.sources.last,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(specificationsEnabled(t), isFalse);
            expect(find.text('0 SCU'), findsOneWidget);
            expectSpecificationsWait(t, suite, input);
            p.provider.requests.last.completeError(
              StateError('fixture refresh failure'),
            );
            await visibilityFrames(t);
            expect(
              find.text(specificationsCopy(t).specsFailure),
              findsOneWidget,
            );
            expect(find.text('0 SCU'), findsOneWidget);
            expect(specificationsEnabled(t), isTrue);
            expect(
              find.ancestor(
                of: find.text(specificationsCopy(t).specsFailure),
                matching: find.byWidgetPredicate(
                  (w) => w is Semantics && w.properties.liveRegion == true,
                ),
              ),
              findsOneWidget,
            );
            await activateSpecifications(t, specificationsAction(), input);
            expect(p.provider.refreshes, [false, true, true]);
            p.provider.requests.last.complete(fixtures.specs);
            await visibilityFrames(t);
            expect(find.text(specificationsCopy(t).specsFailure), findsNothing);
            expect(find.text('0 SCU'), findsOneWidget);
            expect(specificationsEnabled(t), isTrue);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      testWidgets(
        '$suite specifications $input disclosure keeps default state and never rereads',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountSpecifications(t, suite);
            p.provider.requests.single.complete(fixtures.specs);
            await visibilityFrames(t);
            expect(find.byType(StarBridgeExpansionTile), findsNWidgets(3));
            expect(specificationsExpander(t, 'overview').expanded, isTrue);
            expect(specificationsExpander(t, 'flight').expanded, isFalse);
            expect(specificationsExpander(t, 'components').expanded, isFalse);
            await useSpecificationsHeader(t, 'flight', input);
            expect(specificationsExpander(t, 'flight').expanded, isTrue);
            expect(find.text('220 m/s'), findsOneWidget);
            await useSpecificationsHeader(t, 'components', input);
            expect(find.text('Fixture cannon × 2'), findsOneWidget);
            await useSpecificationsHeader(t, 'overview', input);
            expect(specificationsExpander(t, 'overview').expanded, isFalse);
            p.update(() {
              p.light = true;
              p.reduce = true;
            });
            await visibilityFrames(t);
            expect(specificationsExpander(t, 'flight').expanded, isTrue);
            expect(specificationsExpander(t, 'components').expanded, isTrue);
            expect(specificationsExpander(t, 'overview').expanded, isFalse);
            expect(p.provider.requests, hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite specifications reads existing native bool page storage without rereading',
      (t) async {
        size(t, const Size(1100, 1200));
        final p = SpecificationsProbe(suite);
        // Preserve the original context-keyed bool while excluding an
        // unrelated ScrollPosition offset write to that same native slot.
        final seedScroll = ScrollController(keepScrollOffset: false);
        final panelScroll = ScrollController(keepScrollOffset: false);
        addTearDown(seedScroll.dispose);
        addTearDown(panelScroll.dispose);
        p.scrollController = panelScroll;
        await t.pumpWidget(
          scopedApp(
            SizedBox(
              width: p.width,
              child: PageStorage(
                bucket: p.bucket,
                child: SingleChildScrollView(
                  key: const PageStorageKey('spec-test-scroll'),
                  controller: seedScroll,
                  child: const ExpansionTile(
                    key: ValueKey('ship-spec-flight'),
                    title: Text('Native flight seed'),
                    children: [Text('Native body')],
                  ),
                ),
              ),
            ),
            suite,
            reduce: false,
          ),
        );
        await visibilityFrames(t);
        expect(find.text('Native flight seed'), findsOneWidget);
        await t.tap(find.text('Native flight seed'));
        await visibilityFrames(t);
        await t.pumpWidget(p.app());
        await visibilityFrames(t);
        expect(p.provider.requests, hasLength(1));
        p.provider.requests.single.complete(fixtures.specs);
        await visibilityFrames(t);
        expect(specificationsExpander(t, 'flight').expanded, isTrue);
        expect(find.text('220 m/s'), findsOneWidget);
        p.update(() => p.light = true);
        await visibilityFrames(t);
        expect(specificationsExpander(t, 'flight').expanded, isTrue);
        expect(p.provider.requests, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite specifications wait stops live reduce and model replacement starts a new phase',
      (t) async {
        final p = await mountSpecifications(t, suite);
        p.provider.requests.single.complete(fixtures.specs);
        await visibilityFrames(t);
        await activateSpecifications(t, specificationsAction(), 'keyboard');
        expectSpecificationsWait(t, suite, 'keyboard');
        final firstWait = find.byType(HelpSupportWaiting).evaluate().isEmpty
            ? null
            : t.state(find.byType(HelpSupportWaiting));
        const next = LocalHangarShip(id: 'next-instance', title: 'Gladius');
        p.update(() => p.ship = next);
        await visibilityFrames(t);
        expect(p.provider.requests, hasLength(3));
        expect(p.provider.refreshes, [false, true, false]);
        expect(p.provider.ships.last, same(next));
        expect(find.text('0 SCU'), findsNothing);
        expectSpecificationsWait(t, suite, 'pointer');
        if (firstWait != null) {
          expect(
            t.state(find.byType(HelpSupportWaiting)),
            isNot(same(firstWait)),
          );
        }
        p.update(() => p.reduce = true);
        await visibilityFrames(t);
        expectSpecificationsWait(t, suite, 'pointer', reduced: true);
        p.provider.requests[1].complete(fixtures.specs);
        await visibilityFrames(t);
        expect(find.text('0 SCU'), findsNothing);
        p.provider.requests[2].complete(
          const ShipSpecifications(
            state: 'ready',
            modelName: 'Gladius current',
          ),
        );
        await visibilityFrames(t);
        expect(
          find.text(specificationsCopy(t).specsMatched('Gladius current')),
          findsOneWidget,
        );
        expect(
          find.text(specificationsCopy(t).specsMatched('Carrack')),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite specifications provider replacement and disposal ignore old replies',
      (t) async {
        final p = await mountSpecifications(t, suite);
        final old = p.provider;
        final originalState = t.state(find.byType(ShipSpecificationsPanel));
        final replacement = SpecificationsPort();
        p.update(() => p.provider = replacement);
        await visibilityFrames(t);
        expect(
          t.state(find.byType(ShipSpecificationsPanel)),
          same(originalState),
        );
        expect(replacement.requests, hasLength(1));
        old.requests.single.complete(fixtures.specs);
        await visibilityFrames(t);
        expect(find.text('0 SCU'), findsNothing);
        p.update(() => p.away = true);
        await visibilityFrames(t);
        replacement.requests.single.complete(fixtures.specs);
        await visibilityFrames(t);
        expect(find.text('away'), findsOneWidget);
        expect(find.byType(ShipSpecificationsPanel), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite specifications offline and unavailable states preserve original no-read policy',
      (t) async {
        size(t, const Size(1100, 1200));
        final p = SpecificationsProbe(suite);
        p.provider.available = false;
        await t.pumpWidget(p.app());
        await visibilityFrames(t);
        expect(p.provider.requests, isEmpty);
        expect(specificationsAction(), findsNothing);
        expect(find.text(specificationsCopy(t).specsOffline), findsOneWidget);
        final available = SpecificationsPort();
        p.update(() => p.provider = available);
        await visibilityFrames(t);
        available.requests.single.complete(
          const ShipSpecifications(state: 'ambiguous', modelName: 'Ambiguous'),
        );
        await visibilityFrames(t);
        expect(find.text(specificationsCopy(t).specsAmbiguous), findsOneWidget);
        expect(find.byType(StarBridgeExpansionTile), findsNothing);
        expect(specificationsEnabled(t), isTrue);
        expect(t.takeException(), isNull);
      },
    );
  }
}
