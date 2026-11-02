import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_reconciliation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_module.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_panel.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';

const groups = [
  LocalHangarRemovalGroup(id: 'a', requiredCount: 1, shipIds: ['a', 'b']),
  LocalHangarRemovalGroup(id: 'c', requiredCount: 1, shipIds: ['c', 'd']),
];
final inventory = LocalHangarSnapshot(
  revision: 4,
  ships: [
    for (final id in ['a', 'b', 'c', 'd'])
      LocalHangarShip(
        id: id,
        title: id == 'a' || id == 'b' ? 'Carrack' : 'Vulture',
        cn: '测试舰船',
        addedAt: DateTime.utc(2026, 1, 1),
        isFavorite: id == 'b',
      ),
  ],
);

void main() {
  test('all groups must have exact choices before the save request', () async {
    final port = ReviewPort();
    final m = LocalHangarSaveModule(port, 'scan', 2);
    await m.refresh();
    expect(m.canSave, isFalse);
    await m.save();
    expect(port.writes, 0);
    m.replaceSelection({'a'});
    expect(m.selected, isEmpty);
    m.replaceSelection({'a', 'b', 'c'});
    expect(m.canSave, isFalse);
    m.replaceSelection({'a', 'c'});
    expect(m.canSave, isTrue);
    await m.save();
    expect(port.chosen, unorderedEquals(['a', 'c']));
    expect(m.phase, 'saved');
    expect(
      m.current!.formerShips.map((s) => s.id),
      unorderedEquals(['a', 'c']),
    );
    expect(m.current!.ships.map((s) => s.id), unorderedEquals(['b', 'd']));
    m.dispose();
  });

  test(
    'lost receipt is read back, without replaying changed choices',
    () async {
      final port = ReviewPort()..lostReply = true;
      final m = LocalHangarSaveModule(port, 'scan', 2);
      await m.refresh();
      m.replaceSelection({'b', 'd'});
      await m.save();
      expect(m.phase, 'uncertain');
      await m.refresh();
      expect(m.phase, 'saved');
      expect(port.writes, 1);
      expect(port.previews, 1);
      m.dispose();
    },
  );

  test('late preview cannot publish after the reader is disposed', () async {
    final pending = Completer<List<LocalHangarRemovalGroup>>();
    final port = ReviewPort()..pendingPreview = pending;
    final m = LocalHangarSaveModule(port, 'scan', 2);
    final refresh = m.refresh();
    await Future<void>.delayed(Duration.zero);
    var changes = 0;
    m.addListener(() => changes++);
    m.dispose();
    pending.complete(groups);
    await refresh;
    expect(changes, 0);
    expect(m.removals, isEmpty);
  });

  test('unknown local IDs in preview fail closed', () async {
    final port = ReviewPort()
      ..preview = [
        const LocalHangarRemovalGroup(
          id: 'a',
          requiredCount: 1,
          shipIds: ['a', 'unknown'],
        ),
      ];
    final m = LocalHangarSaveModule(port, 'scan', 2);
    await m.refresh();
    expect(m.error, 'hangar.invalid_inventory');
    expect(m.canSave, isFalse);
    expect(port.writes, 0);
    m.dispose();
  });

  test('partial or unchanged reads require no choices', () async {
    final port = ReviewPort()..preview = [];
    final m = LocalHangarSaveModule(port, 'scan', 4);
    await m.refresh();
    expect(m.canSave, isTrue);
    await m.save();
    expect(port.chosen, isEmpty);
    expect(m.phase, 'saved');
    m.dispose();
  });

  test(
    'cache forwards choices and rejects late preview after owner change',
    () async {
      var current = true;
      final port = ReviewPort();
      final cache = CachedLocalHangar(port, isCurrent: () => current);
      await cache.read();
      expect(await cache.previewRemovals('scan', 4), groups);
      final result = await cache.saveResolved(
        'scan',
        4,
        removedShipIds: ['a', 'c'],
      );
      expect(cache.snapshot, same(result));
      final pending = Completer<List<LocalHangarRemovalGroup>>();
      port.pendingPreview = pending;
      final late = cache.previewRemovals('other', 5);
      final assertion = expectLater(late, throwsA(isA<LocalHangarFailure>()));
      current = false;
      pending.complete(groups);
      await assertion;
      expect(cache.snapshot, isNull);
      expect(cache.reconciliationAvailable, isFalse);
    },
  );

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'one narrow review handles both groups, cancel and final consent $locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = ReviewPort();
        await tester.pumpWidget(shell(locale, port));
        await tester.pumpAndSettle();
        final review = find.byKey(const Key('local-hangar-review-removals'));
        Future<void> choose(String id) async {
          final row = find.byKey(ValueKey('hangar-remove-$id'));
          await tester.scrollUntilVisible(
            row,
            100,
            scrollable: find.descendant(
              of: find.byKey(const Key('hangar-removal-list')),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.ensureVisible(row);
          await tester.pumpAndSettle();
          await tester.tap(
            find.ancestor(
              of: row,
              matching: find.byType(StarBridgeCheckboxTile),
            ),
          );
          await tester.pump();
        }

        await tester.tap(review);
        await tester.pumpAndSettle();
        await choose('a');
        expect(port.imageReads['a'], greaterThanOrEqualTo(1));
        // Incomplete review cannot be accepted; cancel does not save or retain a choice.
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('hangar-removal-confirm')),
              )
              .onPressed,
          isNull,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(port.writes, 0);
        await tester.tap(review);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<Checkbox>(find.byKey(const ValueKey('hangar-remove-a')))
              .value,
          isFalse,
        );
        await choose('b');
        await choose('d');
        await tester.tap(find.byKey(const Key('hangar-removal-confirm')));
        await tester.pumpAndSettle();
        expect(port.writes, 0);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('local-hangar-save')))
              .onPressed,
          isNull,
        );
        await tester.tap(
          find.ancestor(
            of: find.byKey(const Key('local-hangar-confirm')),
            matching: find.byType(StarBridgeCheckboxTile),
          ),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('local-hangar-save')));
        await tester.pumpAndSettle();
        expect(port.chosen, unorderedEquals(['b', 'd']));
        expect(port.writes, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('tearing down the reader closes only its removal dialog', (
    tester,
  ) async {
    final port = ReviewPort();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(shell(const Locale('en'), port, visible: visible));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local-hangar-review-removals')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-removal-cancel')), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-removal-cancel')), findsNothing);
    expect(port.writes, 0);
    expect(tester.takeException(), isNull);
  });
}

Widget shell(Locale locale, ReviewPort port, {ValueNotifier<bool>? visible}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        locale,
      ),
      home: Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: visible ?? ValueNotifier(true),
          builder: (_, shown, _) => shown
              ? SingleChildScrollView(
                  child: LocalHangarSavePanel(
                    port: port,
                    view: const {
                      'operationId': 'scan',
                      'shipCount': 2,
                      'phase': 'complete',
                    },
                    onSaved: () {},
                  ),
                )
              : const Text('Other account'),
        ),
      ),
    );

class ReviewPort
    implements
        LocalHangarPort,
        LocalHangarReconciliationPort,
        LocalHangarImageProvider {
  LocalHangarSnapshot snapshot = inventory;
  List<LocalHangarRemovalGroup> preview = groups;
  Completer<List<LocalHangarRemovalGroup>>? pendingPreview;
  bool lostReply = false;
  int writes = 0, previews = 0;
  List<String>? chosen;
  final imageReads = <String, int>{};
  @override
  LocalHangarImagePort imageFor(String shipId, int revision) {
    expect(revision, 4);
    return ReviewImage(this, shipId);
  }

  @override
  bool get reconciliationAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() async => snapshot;
  @override
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  ) async {
    expect(expectedRevision, snapshot.revision);
    previews++;
    return pendingPreview?.future ?? preview;
  }

  @override
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  }) async {
    expect(expectedRevision, snapshot.revision);
    writes++;
    chosen = removedShipIds;
    snapshot = LocalHangarSnapshot(
      revision: expectedRevision + 1,
      operationId: operationId,
      ships: snapshot.ships
          .where((s) => !removedShipIds.contains(s.id))
          .toList(),
      formerShips: snapshot.ships
          .where((s) => removedShipIds.contains(s.id))
          .toList(),
    );
    if (lostReply) throw TimeoutException('Synthetic lost save receipt');
    return snapshot;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw StateError(
    'Resolved saves must use the Host reconciliation capability',
  );
}

class ReviewImage implements LocalHangarImagePort {
  ReviewImage(this.owner, this.id);
  final ReviewPort owner;
  final String id;
  @override
  Future<String?> readImage() async {
    owner.imageReads.update(id, (n) => n + 1, ifAbsent: () => 1);
    return 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
  }

  @override
  bool get canPickLogo => false;
  @override
  Future<CommunityLogoSource?> pickLogo() async => null;
  @override
  Future<String> cropLogo(String sourceRef, double x, double y, double size) =>
      throw StateError('Read-only review');
  @override
  Future<void> clearLogo() async => throw StateError('Read-only review');
  @override
  Future<void> saveImage() async => throw StateError('Read-only review');
  @override
  Future<void> restoreImage() async => throw StateError('Read-only review');
}
