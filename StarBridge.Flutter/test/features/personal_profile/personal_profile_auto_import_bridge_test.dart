import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/composition/menu_profile_page.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profiles_session.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_edit_groups.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_port.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';

import '../friends/social_layout_test.dart' show app, size;

import 'local_personal_profile_test.dart' show SavedHangar, shipA, shipB;
import 'personal_profile_auto_import_bridge_fixture.dart';

void main() {
  test(
    'a rejected import does not consume the next manual edit lease',
    () async {
      final h = _Harness();
      h.connection.rejectedGroup = 'introduction';
      final draft = await h.main.read();
      expect(draft.about, 'Saved locally');
      expect(draft.local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);

      final outcome = await h.main.save(_avatarEdit(draft));
      expect(outcome.outcome, PersonalProfileActionOutcome.completed);
      expect(h.connection.writtenGroups, [
        ['introduction'],
        ['avatarStyle'],
      ]);
      expect(h.connection.pageAbout, 'Previous page');
      expect(h.connection.content?['introduction'], 'Saved locally');
      final refreshed = await h.main.read();
      expect(refreshed.avatarStyle, 2);
      expect(refreshed.local?.autoImportPending, isTrue);
      expect((await h.main.read()).local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups, [
        ['introduction'],
        ['avatarStyle'],
        ['introduction'],
      ]);
    },
  );

  test('a menu read during a main save does not import', () async {
    final h = _Harness();
    h.connection.saveIntroductionLocally('Previous page');
    final initial = await h.main.read();
    h.connection.saveIntroductionLocally('Pending local change');
    final gate = h.connection.blockNextWrite();
    final saving = h.main.save(_avatarEdit(initial));
    await gate.started.future;
    final changed = h.menu.changes.first;
    try {
      final menu = await h.menu.read();
      expect(menu.about, 'Pending local change');
      expect(menu.local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups, [
        ['avatarStyle'],
      ]);
    } finally {
      gate.finish.complete();
    }
    expect((await saving).outcome, PersonalProfileActionOutcome.completed);
    await changed;
    expect((await h.menu.read()).avatarStyle, 2);
  });

  test('a manual save waits for an import in the other entry point', () async {
    final h = _Harness();
    h.connection.saveIntroductionLocally('Previous page');
    final initial = await h.main.read();
    h.connection.saveIntroductionLocally('Pending local change');
    final gate = h.connection.blockNextWrite();
    final importing = h.menu.read();
    await gate.started.future;
    final saving = h.main.save(_avatarEdit(initial));
    try {
      await Future<void>.delayed(Duration.zero);
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);
    } finally {
      gate.finish.complete();
    }
    expect((await importing).about, 'Pending local change');
    expect((await saving).outcome, PersonalProfileActionOutcome.completed);
    expect(h.connection.writtenGroups, [
      ['introduction'],
      ['avatarStyle'],
    ]);
    expect(h.connection.writes.last.payload['expectedRevision'], 8);
    expect(h.connection.pageAbout, 'Pending local change');
  });

  for (final readback in ['older revision', 'failed read']) {
    test('a confirmed import survives a $readback', () async {
      final h = _Harness();
      h.connection.readback = readback;
      final result = await h.main.read();
      expect(result.about, 'Saved locally');
      expect(result.presentation?.revision, 8);
      expect(result.presentation?.origins['introduction'], 'custom');
      expect(result.local?.autoImportPending, isFalse);
      expect(h.connection.pageReads, 2);
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);
      if (readback == 'older revision') {
        expect((await h.menu.read()).presentation?.revision, 8);
        expect(h.connection.writes, hasLength(1));
      }
    });
  }

  for (final close in [false, true]) {
    test(
      '${close ? 'closing' : 'switching accounts'} retires an import read',
      () async {
        final h = _Harness();
        PersonalProfileSnapshot? survivingDraft;
        final gate = h.connection.blockNextWrite();
        final importing = h.main.read();
        await gate.started.future;
        try {
          if (close) {
            survivingDraft = await h.menu.read();
            expect(survivingDraft.about, 'Saved locally');
            await h.main.close();
          } else {
            h.connection
              ..subject = 'second-fixture'
              ..generation = 8;
            h.session.advanceGeneration(8);
            h.connection.saveIntroductionLocally('New owner');
            final newOwner = await h.menu.read();
            expect(newOwner.about, 'New owner');
            expect(newOwner.presentation?.revision, 8);
          }
        } finally {
          gate.finish.complete();
        }
        expect(
          (await importing).availability,
          PersonalProfileAvailability.unavailable,
        );
        expect(h.connection.pageReads, close ? 2 : 3);
        if (close) {
          expect(
            (await h.menu.save(_avatarEdit(survivingDraft!))).outcome,
            PersonalProfileActionOutcome.completed,
          );
          expect(h.connection.writtenGroups, [
            ['introduction'],
            ['avatarStyle'],
          ]);
        }
      },
    );
  }

  for (final origin in ['default', 'linkedLegacy']) {
    test(
      'avatar-only save preserves a rejected $origin local favorite',
      () async {
        final h = _Harness();
        _setMixedFavorites(h);
        h.connection
          ..eligibleOrigin = origin
          ..rejectedGroup = 'favorites';
        final initial = await h.main.read();
        expect(initial.favoriteShips.single.identity.runtimeId, shipA);
        expect(initial.moduleLayout.first.favoriteShipIds, [shipB]);
        expect(
          (await h.main.save(_avatarEdit(initial))).outcome,
          PersonalProfileActionOutcome.completed,
        );
        expect(h.connection.content?['favoriteShipIds'], [shipA]);
        expect(h.connection.content?['modules'], isEmpty);
        expect(h.connection.writtenGroups, [
          ['favorites'],
          ['avatarStyle'],
        ]);

        h.connection.rejectedGroup = null;
        final restored = await h.main.read();
        expect(restored.presentation?.origins['favorites'], 'custom');
        expect(restored.local?.autoImportPending, isFalse);
        expect(h.connection.writtenGroups, [
          ['favorites'],
          ['avatarStyle'],
          ['favorites'],
        ]);
        expect(
          (h.connection.writes.last.payload['content']
              as Map)['favoriteShipCodes'],
          ['LOCAL_A'],
        );
        expect(h.connection.explicitFavorite, shipB);
        await h.main.read();
        expect(h.connection.writes, hasLength(3));
      },
    );
  }

  test(
    'a layout-only edit keeps the local favorite module assignments',
    () async {
      final h = _Harness();
      _setMixedFavorites(h);
      h.connection
        ..rejectedGroup = 'favorites'
        ..content!['modules'] = [
          {
            'id': 'favorite-ships',
            'span': 3,
            'isVisible': true,
            'position': 0,
            'favoriteShipIds': [shipA],
          },
        ];
      final initial = await h.main.read();
      final layout = PersonalProfileLayout.show(
        initial.moduleLayout,
        'hangar-summary',
      );
      final edit = PersonalProfileEdit(
        callSign: initial.callSign,
        about: initial.about,
        avatarStyle: initial.avatarStyle,
        wallpaperId: initial.wallpaperId,
        visibility: initial.visibility,
        moduleLayout: layout.layout,
      );
      expect(
        (await h.main.save(edit)).outcome,
        PersonalProfileActionOutcome.completed,
      );
      expect(h.connection.writtenGroups, [
        ['favorites'],
        ['layout'],
      ]);
      expect(h.connection.content?['favoriteShipIds'], [shipA]);
      final localModules = (h.connection.content?['modules'] as List)
          .cast<Map>();
      expect(
        localModules.firstWhere(
          (m) => m['id'] == 'favorite-ships',
        )['favoriteShipIds'],
        [shipA],
      );
      expect(
        localModules.firstWhere(
          (m) => m['id'] == 'hangar-summary',
        )['isVisible'],
        isTrue,
      );
      expect((h.connection.modules!.first as Map)['favoriteShipIds'], [shipB]);
    },
  );

  for (final oneShowcase in [false, true]) {
    testWidgets(
      'real editor ignores placeholders with one showcase=$oneShowcase',
      (tester) async {
        size(tester, const Size(1600, 1400));
        final h = _Harness();
        h.connection
          ..eligibleGroup = 'layout'
          ..explicitFavorite = oneShowcase ? shipB : null;
        // Keep the raw sparse page all the way to the editor's normalization.
        final port = _RawEditorPort(BridgePersonalProfileAdapter(h.session));
        final module = createPersonalProfileModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        expect(
          module.projection.value.moduleLayout,
          hasLength(oneShowcase ? 1 : 0),
        );

        Future<void> show() async {
          await tester.pumpWidget(app(PersonalProfilePage(module: module)));
          await tester.pumpAndSettle();
        }

        await show();
        await _tap(tester, 'profile-edit');
        final editor = find.byType(PersonalProfileEditorPanel);
        final opened = tester
            .state<PersonalProfileEditorPanelState>(editor)
            .captureDraft()
            .edit;
        expect(opened.moduleLayout.length, greaterThan(oneShowcase ? 1 : 0));
        // Avatar styles are retained in drafts from older editors. Restore one
        // through the actual editor, then submit with its normal Save control.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(
          (module as PersonalProfileDraftSession).keepEditorDraft(
            PersonalProfileEditorDraft(
              PersonalProfileEdit(
                callSign: opened.callSign,
                about: opened.about,
                avatarStyle: 2,
                wallpaperId: opened.wallpaperId,
                visibility: opened.visibility,
                moduleLayout: opened.moduleLayout,
              ),
            ),
          ),
          isTrue,
        );
        await show();
        await _tap(tester, 'profile-save');
        expect(h.connection.writtenGroups, [
          ['avatarStyle'],
        ]);
        expect(port.snapshot.presentation?.origins['layout'], 'default');

        await _tap(tester, 'profile-edit');
        await _tap(tester, 'profile-add-module-anchor');
        await tester.tap(
          find.byKey(
            const ValueKey<Object>(('profile-add-module', 'hangar-summary')),
          ),
        );
        await tester.pumpAndSettle();
        await _tap(tester, 'profile-save');
        expect(h.connection.writtenGroups, [
          ['avatarStyle'],
          ['layout'],
        ]);
        expect(port.snapshot.presentation?.origins['layout'], 'custom');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test(
    'a rejected batch isolates changed and successful groups on later reads',
    () async {
      final h = _Harness();
      h.connection
        ..rejectedGroup = 'introduction'
        ..additionalEligible.add('avatarStyle')
        ..content!['avatarStyle'] = 2;
      expect((await h.main.read()).local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups, [
        ['introduction', 'avatarStyle'],
      ]);

      h.connection.content!['introduction'] = 'Changed local introduction';
      expect((await h.main.read()).local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups.last, ['introduction']);
      expect(
        (h.connection.writes.last.payload['content'] as Map)['introduction'],
        'Changed local introduction',
      );

      final partial = await h.main.read();
      expect(h.connection.writtenGroups.last, ['avatarStyle']);
      expect(partial.avatarStyle, 2);
      expect(partial.about, 'Changed local introduction');
      expect(partial.local?.autoImportPending, isTrue);
      expect(partial.presentation?.origins['avatarStyle'], 'custom');

      final next = await h.main.read();
      expect(next.local?.autoImportPending, isTrue);
      expect(h.connection.writtenGroups, [
        ['introduction', 'avatarStyle'],
        ['introduction'],
        ['avatarStyle'],
        ['introduction'],
      ]);
      h.connection
        ..rejectedGroup = null
        ..content!['introduction'] = 'Recovered local introduction';
      final recovered = await h.main.read();
      expect(recovered.about, 'Recovered local introduction');
      expect(recovered.local?.autoImportPending, isFalse);
      expect(h.connection.writtenGroups.last, ['introduction']);
      expect(h.connection.writes, hasLength(5));
    },
  );

  for (final uncertain in [false, true]) {
    for (final sourceOnly in [false, true]) {
      test(
        'failed import retries after revision/source changes ($uncertain/$sourceOnly)',
        () async {
          final h = _Harness();
          h.connection
            ..unconfirmed = uncertain
            ..rejectedGroup = uncertain ? null : 'introduction';
          expect((await h.main.read()).local?.autoImportPending, isTrue);
          h.connection
            ..rejectedGroup = null
            ..unconfirmed = false;
          expect((await h.main.read()).local?.autoImportPending, isTrue);
          expect(h.connection.writes, hasLength(1));

          if (sourceOnly) {
            h.connection.sourceVersion = 'a' * 64;
          } else {
            h.connection.pageRevision++;
          }
          expect((await h.main.read()).local?.autoImportPending, isFalse);
          expect(h.connection.writtenGroups, [
            ['introduction'],
            ['introduction'],
          ]);
          await h.main.read();
          expect(h.connection.writes, hasLength(2));
        },
      );
    }
  }

  testWidgets(
    'menu shows pending favorites before timeout and refreshes on save',
    (tester) async {
      size(tester, const Size(1600, 1400));
      final h = _Harness();
      _setMixedFavorites(h);
      final gate = h.connection.blockNextWrite();
      final views = <Map<String, Object?>>[];
      final menu = MenuProfilesSession(
        () => throw StateError('Self must use its own port'),
        views.add,
        createOwnPort: () => h.menu,
      );
      addTearDown(menu.dispose);
      menu.open(
        'owner',
        MenuProfileTarget(
          source: 'self',
          reference: '',
          query: '',
          isCurrent: () => true,
          isAccountCurrent: () => true,
        ),
      );
      await tester.pump();
      expect(gate.started.isCompleted, isTrue);
      await tester.pump(const Duration(seconds: 16));
      expect(views.map((v) => v['state']), ['loading', 'ready']);
      final pending = MenuProfileView.parse(views.last);
      expect(pending.autoImportPending, isTrue);
      expect(pending.snapshot?.local, isNull);
      await tester.pumpWidget(
        app(MenuProfileWindowPage(view: pending, onRefresh: () {})),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('profile-auto-import-pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-favorite-ship-$shipA')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-favorite-ship-$shipB')),
        findsNothing,
      );

      final importing = h.menu.read();
      gate.finish.complete();
      expect((await importing).local?.autoImportPending, isFalse);
      await tester.pumpAndSettle();
      final settled = MenuProfileView.parse(views.last);
      expect(settled.state, 'ready');
      expect(settled.autoImportPending, isFalse);
      expect(h.connection.writtenGroups, [
        ['favorites'],
      ]);
      expect(h.connection.pageReads, 2);

      final before = await h.main.read();
      expect(
        (await h.main.save(_avatarEdit(before))).outcome,
        PersonalProfileActionOutcome.completed,
      );
      await tester.pump();
      expect(MenuProfileView.parse(views.last).snapshot?.avatarStyle, 2);
      expect(views.every((v) => v['state'] != 'unavailable'), isTrue);
      menu.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('visitor and offline views hide the owner sync hint', (
    tester,
  ) async {
    size(tester, const Size(1600, 1400));
    final h = _Harness();
    h.connection.rejectedGroup = 'introduction';
    final module = createPersonalProfileModule(h.main);
    addTearDown(module.dispose);
    await module.initialize();
    expect(module.projection.value.local?.autoImportPending, isTrue);
    final hint = find.byKey(const Key('profile-auto-import-pending'));
    await tester.pumpWidget(app(PersonalProfilePage(module: module)));
    await tester.pumpAndSettle();
    expect(hint, findsOneWidget);
    for (final (visitor, offline) in [(true, false), (false, true)]) {
      await tester.pumpWidget(
        app(
          PersonalProfilePage(
            module: module,
            isVisitor: visitor,
            offline: offline,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(hint, findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pending hint and local favorite card use mixed origins', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final h = _Harness();
    _setMixedFavorites(h);
    h.connection.rejectedGroup = 'favorites';
    await tester.pumpWidget(
      StarBridgeApp(
        composition: AppComposition.forTest(
          windowChrome: InMemoryWindowChrome(),
          accountPort: InMemoryAccountAdapter.forReview(
            AccountReviewState.signedIn,
          ),
          personalProfilePort: h.main,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-command')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-menu-personal-profile')));
    await tester.pumpAndSettle();
    final hint = find.text('有些内容还没同步到服务器，别人暂时看不到');
    final local = find.byKey(const Key('profile-favorite-ship-$shipA'));
    final remote = find.byKey(const Key('profile-favorite-ship-$shipB'));
    expect(hint, findsOneWidget);
    expect(local, findsOneWidget);
    expect(remote, findsNothing);

    // A local owner projection does not offer the remote-only visitor preview.
    expect(find.byKey(const Key('profile-preview')), findsNothing);

    h.connection.eligibleGroup = null;
    h.connection.pageRevision++;
    h.connection.notifyProfileChanged();
    await tester.pumpAndSettle();
    expect(hint, findsNothing);
    expect(local, findsNothing);
    expect(remote, findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _tap(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void _setMixedFavorites(_Harness h) {
  h.hangar.snapshot = const LocalHangarSnapshot(
    revision: 1,
    ships: [
      LocalHangarShip(id: shipA, title: 'Local favorite', catalogId: 'LOCAL_A'),
      LocalHangarShip(
        id: shipB,
        title: 'Remote favorite',
        catalogId: 'REMOTE_B',
      ),
    ],
  );
  h.connection
    ..eligibleGroup = 'favorites'
    ..content!['favoriteShipIds'] = [shipA]
    ..explicitFavorite = shipB;
}

class _RawEditorPort implements PersonalProfilePort {
  _RawEditorPort(this.remote);
  final BridgePersonalProfileAdapter remote;
  late PersonalProfileSnapshot snapshot;

  @override
  Stream<void> get invalidations => remote.invalidations;

  @override
  Future<PersonalProfileSnapshot> read() async =>
      snapshot = await remote.read();

  @override
  Future<PersonalProfileActionResult> save(PersonalProfileEdit edit) =>
      remote.savePresentation(
        snapshot.presentation!,
        personalProfileEditGroups(snapshot, edit),
      );

  @override
  Future<void> close() => remote.close();
}

PersonalProfileEdit _avatarEdit(PersonalProfileSnapshot initial) =>
    PersonalProfileEdit(
      callSign: initial.callSign,
      about: initial.about,
      avatarStyle: 2,
      wallpaperId: initial.wallpaperId,
      visibility: initial.visibility,
      moduleLayout: initial.moduleLayout,
    );

class _Harness {
  _Harness() {
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    session.acceptHostCapabilities(['personalProfile.presentation.write.v1']);
    main = _port();
    menu = _port();
    addTearDown(() async {
      await Future.wait([main.close(), menu.close()]);
      await session.close();
    });
  }

  final connection = AutoImportPageConnection();
  final hangar = SavedHangar();
  late final BridgeClientSession session;
  late final BridgeLocalPersonalProfile main, menu;

  BridgeLocalPersonalProfile _port() => BridgeLocalPersonalProfile(
    session,
    remote: BridgePersonalProfileAdapter(session),
    hangar: () => hangar,
  );
}
