import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_feature.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';

import 'hangar_reader_test.dart' as fixtures;

class _Inventory implements LocalHangarPort {
  int reads = 0;
  @override
  Future<LocalHangarSnapshot> read() async {
    ++reads;
    List<LocalHangarShip> ships(bool former) => List.generate(
      24,
      (i) => LocalHangarShip(
        id: '${former ? 'former' : 'current'}-$i',
        title: 'Ship ${former ? 'Former ' : ''}$i',
        category: 'logistics',
        sizeClass: 'small',
        deliveryStatus: 'flyable',
        isFavorite: true,
      ),
    );
    return LocalHangarSnapshot(
      revision: 1,
      ships: ships(false),
      formerShips: ships(true),
    );
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => Future.error(const LocalHangarFailure('not-used'));
}

class _Mode extends ChangeNotifier implements ConnectionModeControl {
  @override
  ConnectionModeSnapshot snapshot = const ConnectionModeSnapshot(
    scope: 7,
    revision: 4,
    state: ConnectionModeState.online,
  );
  @override
  bool failed = false;
  @override
  bool get busy => false;
  @override
  bool get allowsOnlineTraffic =>
      !failed && snapshot.state == ConnectionModeState.online;
  @override
  bool get canEnterOffline => false;
  @override
  Future<bool> enterOffline() async => false;
  void change() {
    snapshot = const ConnectionModeSnapshot(
      scope: 8,
      revision: 5,
      state: ConnectionModeState.online,
    );
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'a hard mode scope replacement retires the old cache and numeric view',
    (tester) async {
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final mode = _Mode(), inventory = _Inventory();
      final feature = createHangarFeature(
        account,
        () => throw StateError('No scanner'),
        localFactory: () => inventory,
        connectionMode: mode,
      );
      try {
        await tester.pumpWidget(
          fixtures.app(Builder(builder: feature.buildDestination)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('local-hangar-search')),
          'Ship',
        );
        final old =
            tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).port
                as CachedLocalHangar;
        mode.change();
        await tester.pumpAndSettle();
        expect(inventory.reads, 2);
        expect(
          tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).port,
          isNot(same(old)),
        );
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('local-hangar-search')))
              .controller!
              .text,
          isEmpty,
        );
        expect(old.snapshot, isNull);
        expect(old.view.query, isEmpty);
        expect(() => old.read(), throwsA(isA<LocalHangarFailure>()));
        mode.failed = true;
        mode.notifyListeners();
        await tester.pumpAndSettle();
        expect(
          inventory.reads,
          2,
          reason: 'Unconfirmed mode cannot dispatch a fresh private read.',
        );
        expect(
          tester.widget<LocalHangarPage>(find.byType(LocalHangarPage)).onRead,
          isNull,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        feature.onDispose?.call();
        mode.dispose();
        account.dispose();
      }
    },
  );
  testWidgets(
    'ordinary authenticated hangar retains filters sort layout and scroll without another read',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      await account.initialize();
      final inventory = _Inventory();
      final feature = createHangarFeature(
        account,
        () => throw StateError('No scanner'),
        localFactory: () => inventory,
      );
      var visible = true;
      late StateSetter navigate;
      try {
        await tester.pumpWidget(
          fixtures.app(
            StatefulBuilder(
              builder: (context, setState) {
                navigate = setState;
                return visible
                    ? feature.buildDestination(context)
                    : const SizedBox.shrink();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('local-hangar-search')),
          'Ship',
        );
        await tester.tap(find.byKey(const Key('hangar-list')));
        await tester.tap(find.byKey(const Key('hangar-former')));
        await tester.tap(find.byKey(const Key('hangar-favorites')));
        await tester.tap(find.byKey(const Key('hangar-sort')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('名称').last);
        await tester.pumpAndSettle();
        final viewport = find.byType(CustomScrollView);
        await tester.drag(viewport, const Offset(0, -700));
        await tester.pumpAndSettle();
        final offset = tester
            .widget<CustomScrollView>(viewport)
            .controller!
            .offset;
        expect(offset, greaterThan(100));
        expect(inventory.reads, 1);
        navigate(() => visible = false);
        await tester.pumpAndSettle();
        navigate(() => visible = true);
        await tester.pumpAndSettle();
        expect(inventory.reads, 1);
        expect(
          tester.widget<CustomScrollView>(viewport).controller!.offset,
          offset,
        );
        final page = tester.widget<LocalHangarPage>(
          find.byType(LocalHangarPage),
        );
        expect(page.port, isNotNull);
        // Reveal the toolbar without changing the retained state under test.
        tester.widget<CustomScrollView>(viewport).controller!.jumpTo(0);
        await tester.pump();
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('local-hangar-search')))
              .controller!
              .text,
          'Ship',
        );
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('hangar-former')))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<FilterChip>(find.byKey(const Key('hangar-favorites')))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('hangar-list')))
              .isSelected,
          isTrue,
        );
        expect(
          tester
              .widget<StarBridgeCompactSelect<String>>(
                find.byType(StarBridgeCompactSelect<String>),
              )
              .value,
          'name',
        );
        navigate(() => visible = false);
        await tester.pumpAndSettle();
        await account.logout();
        await tester.pumpAndSettle();
        expect(account.projection.value.canLogin, isTrue);
        await account.beginLogin();
        await tester.pumpAndSettle();
        expect(account.projection.value.isSignedIn, isTrue);
        navigate(() => visible = true);
        await tester.pumpAndSettle();
        expect(inventory.reads, 2);
        expect(
          tester
              .widget<TextField>(find.byKey(const Key('local-hangar-search')))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(const Key('hangar-current')))
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<IconButton>(find.byKey(const Key('hangar-grid')))
              .isSelected,
          isTrue,
        );
        expect(tester.widget<CustomScrollView>(viewport).controller!.offset, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        feature.onDispose?.call();
        account.dispose();
      }
    },
  );
}
