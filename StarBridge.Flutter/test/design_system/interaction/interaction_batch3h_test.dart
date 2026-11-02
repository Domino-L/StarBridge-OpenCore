import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_holo_choice.dart';
import 'package:starbridge_flutter/features/common/organization_communication_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_models.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_page.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_port.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_workspace_navigation.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch2_test.dart' show app, pixels;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/official_fleet/official_fleet_shared_ships_test.dart'
    as shared;

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

class FleetNavigationHarness extends StatefulWidget {
  const FleetNavigationHarness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<FleetNavigationHarness> createState() => NavigationState();
}

class NavigationState extends State<FleetNavigationHarness> {
  late var suite = widget.suite;
  var selected = OfficialFleetWorkspaceSection.members;
  var reduce = false, light = false, rtl = false;
  var width = 750.0, scale = 1.0;
  final calls = <OfficialFleetWorkspaceSection>[];
  Completer<bool>? guard;
  final frame = GlobalKey();
  void change(VoidCallback update) => setState(update);
  Future<void> request(OfficialFleetWorkspaceSection section) async {
    calls.add(section);
    final pending = guard;
    if (pending != null && !await pending.future) return;
    if (mounted) setState(() => selected = section);
  }

  @override
  Widget build(BuildContext context) => fleetApp(
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: RepaintBoundary(
            key: frame,
            child: SizedBox(
              width: width,
              child: OfficialFleetWorkspaceNavigation(
                selected: selected,
                availableSections: OfficialFleetWorkspaceNavigation.sections
                    .toSet(),
                onSelected: (section) => unawaited(request(section)),
              ),
            ),
          ),
        ),
      ),
    ),
    suite: suite,
    reduce: reduce,
    light: light,
  );
}

Finder tab(String id) => find.byKey(Key('official-fleet-tab-$id'));
SuiteSelectionTrackState track(WidgetTester t) =>
    t.state<SuiteSelectionTrackState>(find.byType(SuiteSelectionTrack));
OrganizationHoloChoice tabFace(WidgetTester t, String id) =>
    t.widget<OrganizationHoloChoice>(
      find.ancestor(of: tab(id), matching: find.byType(OrganizationHoloChoice)),
    );
FocusNode focus(WidgetTester t, String id) => tabFace(t, id).focusNode!;

bool animating(WidgetTester t) =>
    track(t).isStretching || track(t).isSweeping || track(t).isRinging;

Future<NavigationState> mount(WidgetTester t, InteractionSuite suite) async {
  size(t, const Size(1000, 800));
  final key = GlobalKey<NavigationState>();
  await t.pumpWidget(FleetNavigationHarness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

class MutableFleetPort implements OfficialFleetPort {
  MutableFleetPort(this.snapshot);
  OfficialFleetSnapshot snapshot;
  Completer<OfficialFleetSnapshot>? pending;
  final signals = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => signals.stream;
  @override
  Future<OfficialFleetSnapshot> read() =>
      pending?.future ?? Future.value(snapshot);
  void invalidate(OfficialFleetSnapshot value) {
    snapshot = value;
    signals.add(null);
  }

  @override
  Future<void> close() => signals.close();
}

// A verified workspace address is separate from chat/announcement capability.
// The ships port below still performs its own bridge admission and source check.
class _WorkspaceContextPort extends Fake
    implements OrganizationCommunicationPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get chatAvailable => false;
  @override
  bool get announcementsAvailable => false;
  @override
  Future<OrganizationCommunicationContext> open() async =>
      OrganizationCommunicationContext(shared.ref(60000), 'ASTER');
  @override
  Future<void> close() async {}
}

Future<
  ({
    OfficialFleetModule module,
    MutableFleetPort port,
    shared.Harness sharedShips,
  })
>
fleet(WidgetTester t, InteractionSuite suite, {GlobalKey? frame}) async {
  size(t, const Size(1280, 900));
  final snapshot = await InMemoryOfficialFleetAdapter.forReview(signedIn: true)
      .read();
  final port = MutableFleetPort(snapshot);
  final sharedShips = shared.Harness();
  sharedShips.source.value = snapshot.fleet!.sourceRef;
  sharedShips.mutate = (page) => {
    ...page,
    'ships': [
      shared.ship()
        ..['code'] = 'Kraken'
        ..['displayName'] = '克拉克',
    ],
  };
  final module = createOfficialFleetModule(
    port,
    UnavailableOfficialFleetOverviewAdapter(),
    InMemoryOfficialFleetMembersAdapter.forReview(),
    InMemoryOfficialFleetShipsAdapter.forReview(),
    communicationFactory: (sourceRef) {
      expectSync(sourceRef, snapshot.fleet!.sourceRef);
      return _WorkspaceContextPort();
    },
  );
  addTearDown(() async {
    module.dispose();
    await port.close();
    await sharedShips.close();
  });
  await module.initialize();
  // The existing read-only settings entry does not grant governance capability.
  expectSync(module.communication.governance.available, isFalse);
  await t.pumpWidget(
    fleetApp(
      RepaintBoundary(
        key: frame,
        child: OfficialFleetPage(
          module: module,
          sharedShipsPort: sharedShips.adapter,
        ),
      ),
      suite: suite,
    ),
  );
  await t.pumpAndSettle();
  return (module: module, port: port, sharedShips: sharedShips);
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3H'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3h');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite confirms host selection only; cancelled guard stays put',
      (t) async {
        final h = await mount(t, suite);
        h.guard = Completer<bool>();
        await t.tap(tab('ships'));
        await t.pump(const Duration(milliseconds: 200));
        expect(h.selected, OfficialFleetWorkspaceSection.members);
        expect(track(t).indicatorRect, track(t).itemRect(0));
        h.guard!.complete(false);
        await t.pumpAndSettle();
        expect(h.selected, OfficialFleetWorkspaceSection.members);
        h.guard = Completer<bool>();
        focus(t, 'ships').requestFocus();
        await t.pumpAndSettle();
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pump();
        h.guard!.complete(true);
        await t.pump();
        await t.pump();
        expect(h.selected, OfficialFleetWorkspaceSection.ships);
        expect(track(t).indicatorRect, track(t).itemRect(2));
        expect(animating(t), false);
        expect(h.calls, [
          OfficialFleetWorkspaceSection.ships,
          OfficialFleetWorkspaceSection.ships,
        ]);
      },
    );

    testWidgets(
      '$suite repeated active presses paint feedback and never queue',
      (t) async {
        final h = await mount(t, suite);
        for (var i = 0; i < 4; i++) {
          final idle = await pixels(t, h.frame);
          final press = await t.startGesture(t.getCenter(tab('members')));
          await t.pump(const Duration(milliseconds: 150));
          expect(await pixels(t, h.frame), isNot(idle));
          await press.up();
          await t.pumpAndSettle();
        }
        for (final id in ['ships', 'channel', 'broadcasts', 'members']) {
          await t.tap(tab(id));
          await t.pump(const Duration(milliseconds: 25));
        }
        await t.pumpAndSettle();
        expect(h.calls, hasLength(8));
        expect(track(t).indicatorRect, track(t).itemRect(0));
        expect(animating(t), false);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite keyboard Enter Space numpad and arrows land statically',
      (t) async {
        final h = await mount(t, suite);
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.numpadEnter,
        ]) {
          focus(t, 'ships').requestFocus();
          await t.pumpAndSettle();
          await t.sendKeyEvent(key);
          await t.pump();
          await t.pump();
          expect(h.selected, OfficialFleetWorkspaceSection.ships);
          expect(animating(t), false);
        }
        await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await t.pump();
        await t.pump();
        expect(h.selected, OfficialFleetWorkspaceSection.broadcasts);
        expect(focus(t, 'broadcasts').hasFocus, true);
        expect(track(t).indicatorRect, track(t).itemRect(3));
        expect(animating(t), false);
        expect(h.calls, hasLength(4));
      },
    );

    testWidgets(
      '$suite one reader action per tab activates without animation',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          final h = await mount(t, suite);
          final navigation = t.widget<OfficialFleetWorkspaceNavigation>(
            find.byType(OfficialFleetWorkspaceNavigation),
          );
          expect(navigation.selected, OfficialFleetWorkspaceSection.members);
          final metadata = t
              .widget<SuiteSelectionTrack>(find.byType(SuiteSelectionTrack))
              .items;
          for (final item in metadata) {
            final nodes = exposedNodes(t)
                .where((n) => n.getSemanticsData().label == item.label)
                .toList();
            expect(nodes, hasLength(1));
            expect(
              nodes.single.getSemanticsData().hasAction(SemanticsAction.tap),
              true,
            );
          }
          final node = exposedNodes(
            t,
          ).singleWhere((n) => n.getSemanticsData().label == metadata[2].label);
          t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
            node.id,
            SemanticsAction.tap,
          );
          await t.pump();
          await t.pump();
          expect(h.selected, OfficialFleetWorkspaceSection.ships);
          expect(animating(t), false);
          expect(h.calls, [OfficialFleetWorkspaceSection.ships]);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      '$suite live theme suite and reduced motion retain stable focus',
      (t) async {
        final h = await mount(t, suite);
        final node = focus(t, 'ships');
        await t.tap(tab('ships'));
        await t.pump(const Duration(milliseconds: 35));
        h.change(() {
          h.light = true;
          h.reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(track(t).indicatorRect, track(t).itemRect(2));
        expect(animating(t), false);
        expect(focus(t, 'ships'), same(node));
        h.change(() => h.suite = InteractionSuite.glow);
        await t.pumpAndSettle();
        expect(focus(t, 'ships'), same(node));
        expect(h.calls, hasLength(1));
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('$suite narrow RTL at 200 percent reveals keyboard target', (
      t,
    ) async {
      final h = await mount(t, suite);
      h.change(() {
        h.width = 240;
        h.rtl = true;
        h.scale = 2;
      });
      await t.pumpAndSettle();
      focus(t, 'members').requestFocus();
      await t.pumpAndSettle();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await t.pump();
      await t.pump();
      expect(h.selected, OfficialFleetWorkspaceSection.channel);
      expect(track(t).indicatorRect, track(t).itemRect(1));
      final viewport = t.getRect(find.byType(SingleChildScrollView));
      final target = t.getRect(tab('channel'));
      expect(target.left, greaterThanOrEqualTo(viewport.left - 1));
      expect(target.right, lessThanOrEqualTo(viewport.right + 1));
      expect(animating(t), false);
      expect(t.takeException(), isNull);
    });

    testWidgets(
      '$suite actual fleet page preserves sections and original owners',
      (t) async {
        final frame = GlobalKey();
        final f = await fleet(t, suite, frame: frame);
        await capture(t, frame, '${suite.name}-overview');
        await t.tap(tab('members'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 80));
        await capture(t, frame, '${suite.name}-members-enter');
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('official-fleet-members-rows')),
          findsOneWidget,
        );
        final directory = f.module.members.projection.value;
        expect(directory.query!.sourceRef, 'officialFleet:7');
        expect(directory.members, hasLength(5));
        for (final member in directory.members) {
          expect(
            find.byKey(ValueKey('member-row-${member.memberRef}')),
            findsOneWidget,
          );
          expect(find.text(member.callsign), findsOneWidget);
        }
        await t.tap(tab('ships'));
        await t.pumpAndSettle();
        expect(find.byType(CommunityShipsPanel), findsOneWidget);
        final shipsPanel = t.widget<CommunityShipsPanel>(
          find.byType(CommunityShipsPanel),
        );
        expect(shipsPanel.port, same(f.sharedShips.adapter));
        expect(shipsPanel.targetRef, shared.ref(60000));
        expect(f.sharedShips.requests.last.name, 'officialFleet.ships');
        expect(
          f.sharedShips.requests.last.payload['sourceRef'],
          'officialFleet:7',
        );
        expect(
          f.sharedShips.requests.last.payload['targetRef'],
          shipsPanel.targetRef,
        );
        expect(find.text('克拉克'), findsOneWidget);
        await capture(t, frame, '${suite.name}-ships');
        await t.tap(find.byKey(const Key('official-fleet-open-details')));
        await t.pumpAndSettle();
        expect(find.text("Aster's Wing"), findsWidgets);
        await t.tap(find.byKey(const Key('official-fleet-details-close')));
        await t.pumpAndSettle();
        final navigation = t.widget<OfficialFleetWorkspaceNavigation>(
          find.byType(OfficialFleetWorkspaceNavigation),
        );
        expect(navigation.availableSections, {
          OfficialFleetWorkspaceSection.members,
          OfficialFleetWorkspaceSection.ships,
          OfficialFleetWorkspaceSection.manage,
        });
        expect(navigation.selected, OfficialFleetWorkspaceSection.ships);
        expect(f.module.communication.chatAvailable, isFalse);
        expect(f.module.communication.announcementsAvailable, isFalse);
        for (final id in ['channel', 'broadcasts']) {
          final control = tabFace(t, id);
          expect(control.onActivate, isNull);
          expect(control.selected, isFalse);
          expect(f.module.projection.value.fleet!.sourceRef, 'officialFleet:7');
        }
        expect(f.module.projection.value.fleet!.sourceRef, 'officialFleet:7');
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite actual fleet invalidation ignores late reply and hides tabs',
      (t) async {
        final f = await fleet(t, suite);
        await t.tap(tab('ships'));
        await t.pump(const Duration(milliseconds: 30));
        await t.tap(find.byKey(const Key('official-fleet-open-details')));
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('official-fleet-details-dialog')),
          findsOneWidget,
        );
        final old = f.port.snapshot;
        final details = t.element(
          find.byKey(const Key('official-fleet-details-dialog')),
        );
        final delayed = Completer<OfficialFleetSnapshot>();
        f.port.pending = delayed;
        final refreshing = f.module.refresh();
        await t.pump();
        await t.pump();
        expect(
          find.byKey(const Key('official-fleet-details-dialog')),
          findsOneWidget,
        );
        expect(
          t.element(find.byKey(const Key('official-fleet-details-dialog'))),
          same(details),
        );
        expect(find.byType(OfficialFleetWorkspaceNavigation), findsOneWidget);
        expect(f.module.projection.value.isRefreshing, isTrue);
        f.port.invalidate(const OfficialFleetSnapshot.signedOut());
        f.port.pending = null;
        await t.pump();
        await t.pump();
        expect(
          find.byKey(const Key('official-fleet-details-dialog')),
          findsNothing,
        );
        expect(find.byType(OfficialFleetWorkspaceNavigation), findsNothing);
        delayed.complete(old);
        await refreshing;
        await t.pumpAndSettle();
        expect(
          f.module.projection.value.availability,
          OfficialFleetAvailability.signedOut,
        );
        expect(find.byType(SuiteSelectionTrack), findsNothing);
        expect(find.text('登录后查看官网舰队'), findsOneWidget);
        for (final snapshot in [
          OfficialFleetSnapshot.notMember(
            freshness: OfficialFleetFreshness.live,
            observedAtUtc: DateTime.utc(2026, 10, 12),
          ),
          const OfficialFleetSnapshot.unavailable(
            failureKey: 'officialFleet.error.unavailable',
          ),
          old,
        ]) {
          f.port.invalidate(snapshot);
          await t.pumpAndSettle();
          // A returning fleet starts again on the top screen.
          expect(
            find.byKey(const Key('official-fleet-section-rail')),
            snapshot.fleet == null ? findsNothing : findsOneWidget,
          );
          if (snapshot.fleet != null) {
            await t.tap(tab('members'));
            await t.pumpAndSettle();
          }
          expect(
            find.byType(OfficialFleetWorkspaceNavigation),
            snapshot.fleet == null ? findsNothing : findsOneWidget,
          );
          if (snapshot.fleet != null) {
            expect(
              t
                  .widget<OfficialFleetWorkspaceNavigation>(
                    find.byType(OfficialFleetWorkspaceNavigation),
                  )
                  .selected,
              OfficialFleetWorkspaceSection.members,
            );
          }
        }
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        expect(t.binding.hasScheduledFrame, false);
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('all suites use the community choice navigation geometry', (
    t,
  ) async {
    final sizes = <String, Size>{};
    for (final suite in InteractionSuite.values) {
      await mount(t, suite);
      for (final section in OfficialFleetWorkspaceNavigation.sections) {
        final value = t.getSize(tab(section.name));
        if (suite == InteractionSuite.standard) {
          sizes[section.name] = value;
        } else {
          expect(value, sizes[section.name]);
        }
      }
    }
    expect(t.takeException(), isNull);
  });
}
