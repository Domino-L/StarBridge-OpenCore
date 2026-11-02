import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';
import 'package:starbridge_flutter/features/hangar/hangar_sharing_action.dart';

import '../../features/communities/community_ships_test.dart' show shipRow;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3ae_test.dart' show mount, choose;
import 'interaction_batch3am_test.dart' show action;

final target = 'a' * 32;
final revision = 'b' * 64;
String ref(int id) => id.toRadixString(16).padLeft(32, '0');
const firstDetail = Key(
  'community-ship-details-00000000000000000000000000000064',
);

class Fleet
    implements
        CommunityShipsPort,
        CommunityHangarSharingPort,
        CommunityShipImagePort,
        CommunityShipReportPort {
  final changes = StreamController<void>.broadcast(sync: true);
  final reads =
      <
        ({
          String target,
          CommunityShipQuery query,
          int offset,
          String? revision,
          InteractionSource source,
        })
      >[];
  final writes =
      <
        ({
          String editRef,
          List<String> selected,
          bool images,
          InteractionSource source,
        })
      >[];
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool shipsAvailable = true;
  @override
  bool hangarSharingAvailable = true;
  @override
  bool shipImageAvailable = true;
  @override
  bool shipReportAvailable = true;
  int count = 25,
      options = 2,
      sharingReads = 0,
      customImageReads = 0,
      reports = 0;
  String? shipError, sharingError;
  String editRef = ref(2000);
  bool explicit = true;
  List<String> saved = [ref(1)];
  CommunityHangarSharingOutcome outcome = const CommunityHangarSharingOutcome(
    'accepted',
  );
  Completer<void>? selectedRead;
  Completer<CommunityHangarSharingOutcome>? pendingWrite;

  @override
  Future<CommunityShipsPage> readShips(
    String id, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    final q = query ?? CommunityShipQuery();
    reads.add((
      target: id,
      query: q,
      offset: offset,
      revision: revision,
      source: currentStarBridgeActivationSource,
    ));
    if (shipError != null) throw CommunityFailure(shipError!);
    if (selectedRead != null && revision != null) await selectedRead!.future;
    final matched = q.text == 'missing' ? 0 : count;
    return CommunityShipsPage.parse({
      'schemaVersion': 1,
      'queryVersion': 2,
      'query': q.toPayload(),
      'targetRef': id,
      'revision': 'b' * 64,
      'offset': offset,
      'totalCount': count,
      'matchedCount': matched,
      'next': offset + 20 < matched ? offset + 20 : null,
      'ships': [
        for (var i = offset; i < (offset + 20).clamp(0, matched); i++)
          shipRow()
            ..['shipRef'] = ref(100 + i)
            ..['code'] = 'fixture-$i'
            ..['displayName'] = 'Shared ship ${i + 1}'
            ..['ownerHasAvatar'] = false
            ..['roleCategory'] = 'combat'
            ..['catalogSpec'] = 'large'
            ..['catalogRole'] = 'Combat'
            ..['catalogPriceUsd'] = i.isEven ? '10' : null,
      ],
    });
  }

  @override
  Future<CommunityHangarSharing> readHangarSharing() async {
    sharingReads++;
    if (sharingError != null) throw CommunityFailure(sharingError!);
    editRef = ref(2000 + sharingReads);
    return CommunityHangarSharing.parse({
      'schemaVersion': 1,
      'editRef': editRef,
      'maximumTargets': 64,
      'usesExplicitTargets': explicit,
      'options': [
        for (var i = 1; i <= options; i++)
          {
            'targetRef': ref(i),
            'name': 'Org $i',
            'selected': saved.contains(ref(i)),
          },
      ],
    });
  }

  @override
  Future<CommunityHangarSharingOutcome> saveHangarSharing(
    String edit,
    List<String> selectedRefs, {
    bool includeImages = false,
  }) async {
    writes.add((
      editRef: edit,
      selected: List.of(selectedRefs),
      images: includeImages,
      source: currentStarBridgeActivationSource,
    ));
    final result = pendingWrite == null ? outcome : await pendingWrite!.future;
    if (result.status == 'accepted') {
      saved = List.of(selectedRefs);
      explicit = true;
    }
    return result;
  }

  @override
  Future<Map<String, Object?>> readShipImage(
    String id,
    String ship, {
    required int offset,
    String? version,
  }) async {
    customImageReads++;
    throw StateError('Current detail is catalog-only');
  }

  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    reports++;
    throw StateError('Current detail has no report entry');
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    reports++;
    throw StateError('Current detail has no report entry');
  }
}

Widget panel(
  Fleet port, {
  CommunityShipsController? owner,
  VoidCallback? back,
}) => CommunityShipsPanel(
  port: port,
  targetRef: target,
  name: 'Original organization',
  controller: owner,
  onBack: back ?? () {},
);
Finder checkbox(Key key) => find.byWidgetPredicate(
  (w) => w is StarBridgeCheckboxTile && w.controlKey == key,
);
Future<void> check(WidgetTester t, Key key, String source) async {
  final outer = checkbox(key);
  await t.ensureVisible(outer);
  await settleCommunityImages(t);
  if (source == 'pointer') {
    await t.tap(outer);
  } else if (source == 'keyboard') {
    final native = find.descendant(of: outer, matching: find.byType(Checkbox));
    final expressive = find.descendant(
      of: outer,
      matching: find.byType(SuiteCheckbox),
    );
    final focus = native.evaluate().isNotEmpty
        ? t.widget<Checkbox>(native).focusNode!
        : t.widget<SuiteCheckbox>(expressive).focusNode!;
    focus.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.space);
  } else {
    final semantics = find.descendant(
      of: outer,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.onTap != null,
      ),
    );
    final node = t.getSemantics(semantics.first);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await settleCommunityImages(t);
}

Future<void> expand(WidgetTester t, Finder outer, String source) async {
  final header = find
      .descendant(of: outer, matching: find.byType(SuitePressable))
      .first;
  await t.ensureVisible(header);
  await settleCommunityImages(t);
  if (source == 'pointer') {
    await t.tap(header);
  } else if (source == 'keyboard') {
    t.widget<SuitePressable>(header).focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(header);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await settleCommunityImages(t);
}

void routeOrigin(WidgetTester t, Finder child, String source) => expect(
  (ModalRoute.of(t.element(child))! as StarBridgeDialogRoute).instant,
  source != 'pointer',
);
StarBridgeActionButton button(WidgetTester t, Key key) => t.widget(
  find.byWidgetPredicate(
    (w) => w is StarBridgeActionButton && w.controlKey == key,
  ),
);
Future<void> openSharing(
  WidgetTester t,
  Fleet port,
  InteractionSuite suite,
  String source, {
  bool local = false,
}) async {
  await mount(
    t,
    local ? HangarSharingAction(port: port) : panel(port),
    suite,
    width: 1000,
  );
  await action(
    t,
    Key(local ? 'local-hangar-sharing' : 'community-ships-sharing'),
    source,
  );
  routeOrigin(t, find.byType(CommunityHangarSharingDialog), source);
}

Future<void> screenshot(WidgetTester t, GlobalKey capture, String name) async {
  await t.runAsync(() async {
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    Directory('build/reviews/interaction-batch3ao').createSync(recursive: true);
    File('build/reviews/interaction-batch3ao/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'real fleet query sort paging detail close retains scoped reads $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Fleet();
          final owner = CommunityShipsController(port, target);
          var back = 0;
          addTearDown(owner.dispose);
          addTearDown(port.changes.close);
          try {
            await mount(
              t,
              panel(port, owner: owner, back: () => back++),
              suite,
            );
            await t.enterText(
              find.byKey(const Key('community-ships-search-field')),
              ' retained query ',
            );
            await t.pump();
            await action(t, const Key('community-ships-search'), source);
            expect(owner.query.text, 'retained query');
            expect(
              port.reads
                  .lastWhere(
                    (r) => r.query.text == 'retained query' && r.offset == 0,
                  )
                  .source,
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            await action(t, const Key('community-ship-filter-large'), source);
            expect(owner.query.filter, 'large');
            await choose(t, 'community-ships-sort', 'name', source);
            expect(owner.query.sort, 'name');
            expect(owner.query.descending, false);
            await action(t, const Key('community-ships-direction'), source);
            expect(owner.query.descending, true);
            await t.pumpAndSettle();
            expect(owner.page!.offset, 20);
            expect(
              port.reads
                  .lastWhere(
                    (r) => r.query.text == 'retained query' && r.offset == 20,
                  )
                  .revision,
              revision,
            );
            // Pages accumulate (option D, 2026-10-29): page 1 is still shown
            // and the first ship's details reauthorize its own page.
            expect(find.text('Shared ship 1'), findsOneWidget);
            final originalQuery = owner.query;
            await action(t, firstDetail, source);
            routeOrigin(t, find.byType(CommunityShipDetailDialog), source);
            final selected = port.reads.lastWhere(
              (r) =>
                  r.revision != null &&
                  r.query.text == 'retained query' &&
                  r.offset == 0,
            );
            expect(selected.query, originalQuery);
            expect(selected.target, target);
            expect(
              find.descendant(
                of: find.byType(CommunityShipDetailDialog),
                matching: find.text('Shared ship 1'),
              ),
              findsOneWidget,
            );
            await action(t, const Key('community-ship-detail-retry'), source);
            await action(
              t,
              const Key('community-ship-detail-close-icon'),
              source,
            );
            expect(find.byType(CommunityShipDetailDialog), findsNothing);
            expect(owner.query, originalQuery);
            expect(port.customImageReads, 0);
            expect(port.reports, 0);
            expect(port.writes, isEmpty);
            await action(t, const Key('community-ships-back'), source);
            expect(back, 1);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
      for (final local in [false, true]) {
        testWidgets(
          'both audience entry paths require explicit save and image opt in $suite $source local=$local',
          (t) async {
            final semantics = t.ensureSemantics(), port = Fleet();
            addTearDown(port.changes.close);
            try {
              await openSharing(t, port, suite, source, local: local);
              final edit = port.editRef;
              await check(t, Key('hangar-share-target-${ref(2)}'), source);
              expect(port.writes, isEmpty);
              expect(port.saved, [ref(1)]);
              await check(t, const Key('hangar-share-images'), source);
              expect(port.writes, isEmpty);
              await action(t, const Key('hangar-sharing-save'), source);
              final written = port.writes.single;
              expect(
                (written.editRef, written.images, written.source),
                (
                  edit,
                  true,
                  source == 'pointer'
                      ? InteractionSource.pointer
                      : InteractionSource.keyboard,
                ),
              );
              expect(written.selected, [ref(1), ref(2)]);
              expect(find.byType(CommunityHangarSharingDialog), findsNothing);
              expect(port.sharingReads, 1);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
            } finally {
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        'statistics chart activation disclosure and dispatch are readonly $suite $source',
        (t) async {
          final semantics = t.ensureSemantics(), port = Fleet();
          addTearDown(port.changes.close);
          try {
            await mount(t, panel(port), suite);
            await action(
              t,
              const Key('community-ship-statistics-expand'),
              source,
            );
            routeOrigin(
              t,
              find.byKey(const Key('community-statistics-dialog')),
              source,
            );
            if (source == 'pointer') {
              final mouse = await t.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              addTearDown(mouse.removePointer);
              final cell = find.byKey(
                const Key('ship-distribution-large-combat'),
              );
              await t.ensureVisible(cell);
              await mouse.moveTo(t.getCenter(cell));
              await settleCommunityImages(t);
              expect(
                t
                    .widget<Text>(
                      find.byKey(const Key('ship-distribution-selection')),
                    )
                    .data,
                contains('25'),
              );
            }
            await action(
              t,
              const Key('ship-distribution-large-combat'),
              source,
            );
            expect(
              t
                  .widget<Text>(
                    find.byKey(const Key('ship-distribution-selection')),
                  )
                  .data,
              contains('25'),
            );
            final table = find.byKey(
              const Key('ship-distribution-table-toggle'),
            );
            await expand(t, table, source);
            expect(
              find.byKey(const Key('ship-distribution-table')),
              findsOneWidget,
            );
            await action(t, const Key('community-statistics-close'), source);
            // The client-computed dispatch view is gone (user 2026-10-29).
            expect(find.textContaining('待确认'), findsNothing);
            expect(port.writes, isEmpty);
            expect(port.reports, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    for (final kind in ['detail', 'sharing', 'statistics']) {
      testWidgets('borrowed fleet departure retires owned $kind route $suite', (
        t,
      ) async {
        final port = Fleet();
        final owner = CommunityShipsController(port, target);
        // This explicitly borrowed owner must outlive presentation removal.
        addTearDown(owner.dispose);
        addTearDown(port.changes.close);
        final live = await mount(t, panel(port, owner: owner), suite);
        await action(
          t,
          kind == 'detail'
              ? firstDetail
              : Key(
                  kind == 'sharing'
                      ? 'community-ships-sharing'
                      : 'community-ship-statistics-expand',
                ),
          'keyboard',
        );
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityShipDetailDialog), findsNothing);
        expect(find.byType(CommunityHangarSharingDialog), findsNothing);
        expect(
          find.byKey(const Key('community-statistics-dialog')),
          findsNothing,
        );
        expect(owner.invalidated, false);
        expect(owner.page, isNotNull);
        expect(port.writes, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
    testWidgets(
      'local audience entry departure and port replacement remove only own route $suite',
      (t) async {
        final first = Fleet(), next = Fleet();
        addTearDown(first.changes.close);
        addTearDown(next.changes.close);
        var port = first;
        late StateSetter rebuild;
        final live = await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return HangarSharingAction(port: port);
            },
          ),
          suite,
        );
        await action(t, const Key('local-hangar-sharing'), 'keyboard');
        rebuild(() => port = next);
        await settleCommunityImages(t);
        expect(find.byType(CommunityHangarSharingDialog), findsNothing);
        await action(t, const Key('local-hangar-sharing'), 'keyboard');
        expect(next.sharingReads, 1);
        live.change(() => live.visible = false);
        await settleCommunityImages(t);
        expect(find.byType(CommunityHangarSharingDialog), findsNothing);
        expect(first.writes, isEmpty);
        expect(next.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'fleet owner replacement keeps borrowed controllers and dismisses old details $suite',
      (t) async {
        final first = Fleet(), next = Fleet();
        final oldOwner = CommunityShipsController(first, target),
            nextOwner = CommunityShipsController(next, target);
        addTearDown(first.changes.close);
        addTearDown(next.changes.close);
        addTearDown(oldOwner.dispose);
        addTearDown(nextOwner.dispose);
        var owner = oldOwner;
        late StateSetter rebuild;
        await mount(
          t,
          StatefulBuilder(
            builder: (_, set) {
              rebuild = set;
              return panel(owner == oldOwner ? first : next, owner: owner);
            },
          ),
          suite,
        );
        await action(t, firstDetail, 'keyboard');
        rebuild(() => owner = nextOwner);
        await settleCommunityImages(t);
        expect(find.byType(CommunityShipDetailDialog), findsNothing);
        expect(oldOwner.page, isNotNull);
        expect(oldOwner.invalidated, false);
        await action(t, firstDetail, 'keyboard');
        first.changes.add(null);
        await settleCommunityImages(t);
        expect(find.byType(CommunityShipDetailDialog), findsOneWidget);
        expect(nextOwner.invalidated, false);
        expect(next.writes, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('audience withdrawal suppresses retained image opt in $suite', (
      t,
    ) async {
      final port = Fleet();
      addTearDown(port.changes.close);
      await openSharing(t, port, suite, 'keyboard', local: true);
      await check(t, const Key('hangar-share-images'), 'keyboard');
      await check(t, Key('hangar-share-target-${ref(1)}'), 'keyboard');
      expect(checkbox(const Key('hangar-share-images')), findsNothing);
      expect(port.writes, isEmpty);
      await action(t, const Key('hangar-sharing-save'), 'keyboard');
      expect(port.writes.single.selected, isEmpty);
      expect(port.writes.single.images, false);
      expect(port.writes.single.source, InteractionSource.keyboard);
      await t.pumpWidget(const SizedBox());
    });
    testWidgets(
      'native keyboard query no match reset and transport retry preserve domain $suite',
      (t) async {
        final port = Fleet();
        final owner = CommunityShipsController(port, target);
        addTearDown(port.changes.close);
        addTearDown(owner.dispose);
        await mount(t, panel(port, owner: owner), suite);
        await t.enterText(
          find.byKey(const Key('community-ships-search-field')),
          'missing',
        );
        await t.testTextInput.receiveAction(TextInputAction.done);
        await settleCommunityImages(t);
        expect(owner.query.text, 'missing');
        expect(owner.page!.matchedCount, 0);
        expect(
          port.reads.lastWhere((r) => r.query.text == 'missing').source,
          InteractionSource.keyboard,
        );
        await action(t, const Key('community-ships-clear'), 'keyboard');
        expect(owner.query.text, isEmpty);
        expect(owner.query.filter, 'all');
        expect(owner.query.sort, 'spec');
        expect(owner.query.descending, true);
        port.shipError = 'unavailable';
        await action(t, const Key('community-ships-refresh'), 'keyboard');
        // A later page may be current; the rows on screen are what must stay.
        expect(find.text('Shared ship 1'), findsOneWidget);
        expect(owner.error, 'unavailable');
        port.shipError = null;
        await action(
          t,
          const Key('community-ships-refresh-failed'),
          'keyboard',
        );
        expect(owner.error, isNull);
        expect(owner.page!.totalCount, 25);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final kind in ['sharing', 'statistics']) {
      testWidgets(
        'server permission loss without broadcast retires owned $kind $suite',
        (t) async {
          final port = Fleet();
          final owner = CommunityShipsController(port, target);
          addTearDown(owner.dispose);
          addTearDown(port.changes.close);
          await mount(t, panel(port, owner: owner), suite);
          await action(
            t,
            Key(
              kind == 'sharing'
                  ? 'community-ships-sharing'
                  : 'community-ship-statistics-expand',
            ),
            'keyboard',
          );
          port.shipError = 'notAllowed';
          await owner.refreshVisible();
          await settleCommunityImages(t);
          expect(find.byType(CommunityHangarSharingDialog), findsNothing);
          expect(
            find.byKey(const Key('community-statistics-dialog')),
            findsNothing,
          );
          expect(
            button(t, const Key('community-ships-sharing')).onActivate,
            isNull,
          );
          expect(owner.page, isNull);
          expect(port.writes, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'pending detail read cannot restore after identity invalidation $suite',
      (t) async {
        final port = Fleet();
        addTearDown(port.changes.close);
        await mount(t, panel(port), suite);
        port.selectedRead = Completer();
        await action(t, firstDetail, 'keyboard', settle: false);
        expect(find.byType(CommunityShipDetailDialog), findsOneWidget);
        port.changes.add(null);
        await t.pump();
        await t.pump();
        port.selectedRead!.complete();
        await settleCommunityImages(t);
        expect(find.byType(CommunityShipDetailDialog), findsNothing);
        expect(find.text('Shared ship 1'), findsNothing);
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'live reduce theme preserves native query and unsaved sharing choices $suite',
      (t) async {
        final port = Fleet();
        addTearDown(port.changes.close);
        final live = await mount(t, panel(port), suite);
        final search = find.byKey(const Key('community-ships-search-field'));
        await t.enterText(search, 'Unsubmitted native query');
        await t.pump();
        final editor = t.widget<TextField>(search).controller;
        await action(t, const Key('community-ships-sharing'), 'pointer');
        await check(t, Key('hangar-share-target-${ref(2)}'), 'pointer');
        await check(t, const Key('hangar-share-images'), 'pointer');
        live.change(() {
          live.light = true;
          live.reduce = true;
        });
        await t.pump();
        await t.pump();
        expect(
          t
              .widget<StarBridgeCheckboxTile>(
                checkbox(Key('hangar-share-target-${ref(2)}')),
              )
              .value,
          true,
        );
        expect(
          t
              .widget<StarBridgeCheckboxTile>(
                checkbox(const Key('hangar-share-images')),
              )
              .value,
          true,
        );
        expect(editor!.text, 'Unsubmitted native query');
        expect(port.writes, isEmpty);
        await action(t, const Key('hangar-sharing-close'), 'keyboard');
        expect(t.widget<TextField>(search).controller, same(editor));
        expect(editor.text, 'Unsubmitted native query');
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'unknown sharing requires new authorized read and explicit retry $suite',
      (t) async {
        final port = Fleet()
          ..outcome = const CommunityHangarSharingOutcome('unknown');
        addTearDown(port.changes.close);
        await openSharing(t, port, suite, 'keyboard', local: true);
        await check(t, const Key('hangar-share-images'), 'keyboard');
        final old = port.editRef;
        await action(t, const Key('hangar-sharing-save'), 'keyboard');
        expect(port.writes.length, 1);
        expect(find.byKey(const Key('hangar-sharing-save')), findsNothing);
        expect(port.sharingReads, 1);
        await action(t, const Key('hangar-sharing-refresh'), 'keyboard');
        expect(port.sharingReads, 2);
        expect(port.editRef, isNot(old));
        expect(port.writes.length, 1);
        expect(
          t
              .widget<StarBridgeCheckboxTile>(
                checkbox(const Key('hangar-share-images')),
              )
              .value,
          false,
        );
        port.outcome = const CommunityHangarSharingOutcome('accepted');
        await action(t, const Key('hangar-sharing-save'), 'keyboard');
        expect(port.writes.length, 2);
        expect(port.writes.last.editRef, port.editRef);
        expect(port.writes.last.images, false);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'rejected image sharing explains scan requirement without reusing token $suite',
      (t) async {
        final port = Fleet()
          ..outcome = const CommunityHangarSharingOutcome(
            'rejected',
            error: 'localHangarRequired',
          );
        addTearDown(port.changes.close);
        await openSharing(t, port, suite, 'keyboard', local: true);
        await action(t, const Key('hangar-sharing-save'), 'keyboard');
        expect(port.writes.length, 1);
        expect(find.byKey(const Key('hangar-sharing-save')), findsNothing);
        expect(find.textContaining('扫描'), findsOneWidget);
        await action(t, const Key('hangar-sharing-close'), 'keyboard');
        expect(port.writes.length, 1);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'missing sharing capability or upgrade offers no retry loop $suite',
      (t) async {
        final port = Fleet()..sharingError = 'upgradeRequired';
        addTearDown(port.changes.close);
        await openSharing(t, port, suite, 'keyboard', local: true);
        expect(find.byKey(const Key('hangar-sharing-refresh')), findsNothing);
        expect(find.byKey(const Key('hangar-sharing-save')), findsNothing);
        expect(port.writes, isEmpty);
        await action(t, const Key('hangar-sharing-close'), 'keyboard');
        port.hangarSharingAvailable = false;
        await mount(t, panel(port), suite);
        expect(find.byKey(const Key('community-ships-sharing')), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
    for (final legacy in [false, true]) {
      testWidgets(
        'empty audience distinguishes confirmed unshared from legacy $suite legacy=$legacy',
        (t) async {
          final port = Fleet()
            ..saved = []
            ..options = 0
            ..explicit = !legacy;
          addTearDown(port.changes.close);
          await openSharing(t, port, suite, 'keyboard', local: true);
          expect(
            button(t, const Key('hangar-sharing-save')).onActivate != null,
            legacy,
          );
          expect(port.writes, isEmpty);
          if (legacy) {
            await action(t, const Key('hangar-sharing-save'), 'keyboard');
            expect(port.writes.single.selected, isEmpty);
            expect(port.writes.single.images, false);
          } else {
            await action(t, const Key('hangar-sharing-close'), 'keyboard');
          }
          await t.pumpWidget(const SizedBox());
        },
      );
    }
    testWidgets(
      'pending audience save blocks repeats and departure ignores late acceptance $suite',
      (t) async {
        final port = Fleet()..pendingWrite = Completer();
        addTearDown(port.changes.close);
        final live = await mount(t, panel(port), suite);
        await action(t, const Key('community-ships-sharing'), 'keyboard');
        await action(
          t,
          const Key('hangar-sharing-save'),
          'keyboard',
          settle: false,
        );
        expect(port.writes.length, 1);
        expect(button(t, const Key('hangar-sharing-save')).onActivate, isNull);
        expect(button(t, const Key('hangar-sharing-close')).onActivate, isNull);
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(CommunityHangarSharingDialog), findsOneWidget);
        final reads = port.reads.length;
        live.change(() => live.visible = false);
        await t.pump();
        await t.pump();
        port.pendingWrite!.complete(
          const CommunityHangarSharingOutcome('accepted'),
        );
        await settleCommunityImages(t);
        expect(find.byType(CommunityHangarSharingDialog), findsNothing);
        expect(port.writes.length, 1);
        expect(port.reads.length, reads);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'sharing maximum keeps selected rows removable and blocks 65th $suite',
      (t) async {
        final port = Fleet()
          ..options = 65
          ..saved = [for (var i = 1; i <= 64; i++) ref(i)];
        addTearDown(port.changes.close);
        await openSharing(t, port, suite, 'keyboard', local: true);
        final last = Key('hangar-share-target-${ref(65)}');
        await t.scrollUntilVisible(
          checkbox(last),
          500,
          scrollable: find
              .descendant(
                of: find.byType(CommunityHangarSharingDialog),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          t.widget<StarBridgeCheckboxTile>(checkbox(last)).onChanged,
          isNull,
        );
        await check(t, Key('hangar-share-target-${ref(64)}'), 'keyboard');
        expect(
          t.widget<StarBridgeCheckboxTile>(checkbox(last)).onChanged,
          isNotNull,
        );
        await check(t, last, 'keyboard');
        await action(t, const Key('hangar-sharing-save'), 'keyboard');
        expect(port.writes.single.selected.length, 64);
        expect(port.writes.single.selected, isNot(contains(ref(64))));
        expect(port.writes.single.selected, contains(ref(65)));
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'active repeated filters retain callbacks and horizontal geometry $suite',
      (t) async {
        final port = Fleet();
        addTearDown(port.changes.close);
        final owner = CommunityShipsController(port, target);
        addTearDown(owner.dispose);
        await mount(t, panel(port, owner: owner), suite);
        await t.enterText(
          find.byKey(const Key('community-ships-search-field')),
          'clicked query',
        );
        await t.pump();
        await action(t, const Key('community-ships-search'), 'keyboard');
        final keys = [
          const Key('community-ship-filter-large'),
          const Key('community-ship-filter-all'),
        ];
        final geometry = keys.map((key) => t.getRect(find.byKey(key))).toList();
        final before = port.reads
            .where((r) => r.query.text == 'clicked query')
            .length;
        for (final key in [keys.first, keys.last, keys.first, keys.last]) {
          await action(t, key, 'pointer', settle: false);
        }
        await settleCommunityImages(t);
        final activeReads = port.reads
            .where((r) => r.query.text == 'clicked query')
            .skip(before)
            .where((r) => r.offset == 0)
            .toList();
        expect(activeReads.length, 4);
        expect(
          activeReads.every((r) => r.source == InteractionSource.pointer),
          true,
        );
        expect(owner.query.filter, 'all');
        expect(
          keys.map((key) => t.getRect(find.byKey(key))).toList(),
          geometry,
        );
        expect(port.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets(
      'render sharing and detail controls with visible original labels $suite',
      (t) async {
        final port = Fleet(), capture = GlobalKey();
        addTearDown(port.changes.close);
        await mount(t, panel(port), suite, capture: capture);
        await action(t, firstDetail, 'pointer');
        expect(
          find.descendant(
            of: find.byType(CommunityShipDetailDialog),
            matching: find.text('Shared ship 1'),
          ),
          findsOneWidget,
        );
        final close = t.getRect(
          find.byKey(const Key('community-ship-detail-close')),
        );
        expect(close.height, inInclusiveRange(32, 48));
        expect(close.width, lessThan(180));
        await screenshot(t, capture, '${suite.name}-detail');
        await action(t, const Key('community-ship-detail-close'), 'keyboard');
        await action(t, const Key('community-ships-sharing'), 'pointer');
        expect(find.text('Org 1'), findsOneWidget);
        expect(find.text('Org 2'), findsOneWidget);
        await screenshot(t, capture, '${suite.name}-sharing');
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
