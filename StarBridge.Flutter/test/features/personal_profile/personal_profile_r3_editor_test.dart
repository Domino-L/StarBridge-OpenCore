import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profile_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_profiles_session.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_local_personal_profile.dart';
import 'package:starbridge_flutter/features/personal_profile/bridge_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/window/menu_profile_navigation.dart';

import '../friends/social_layout_test.dart' show app, size;
import 'local_personal_profile_test.dart' show SavedHangar, shipA, shipB;
import 'personal_profile_auto_import_bridge_fixture.dart';

void main() {
  for (final versioned in [false, true]) {
    testWidgets(
      'first wallpaper save cannot import inherited introduction ($versioned)',
      (tester) async {
        final h = _EditorHarness(versioned: versioned);
        h.connection
          ..revision = 0
          ..content = null
          ..sourceVersion = 'a' * 64
          ..groupOrigins.addAll({
            'introduction': 'linkedLegacy',
            'wallpaper': 'default',
          });
        await h.open(tester);
        expect(h.module.projection.value.about, 'Previous page');

        h.connection
          ..pageRevision += 1
          ..pageAbout = 'New inherited introduction';
        await _tap(tester, 'profile-background-picker-open');
        await _tap(tester, 'profile-wallpaper-choice-formation-flight');
        await _tap(tester, 'profile-save');
        expect(h.connection.localSaveCount, 1);
        expect(h.connection.content, {
          'callSign': 'Fixture',
          'wallpaperId': 'formation-flight',
        });
        if (!versioned) expect(h.connection.writes, isEmpty);

        h.connection.versioned = true;
        await h.module.refresh();
        await tester.pumpAndSettle();
        expect(h.connection.pageAbout, 'New inherited introduction');
        expect(h.connection.groupOrigins['introduction'], 'linkedLegacy');
        expect(h.connection.writtenGroups, [
          ['wallpaper'],
        ]);
        expect(
          h.connection.writes.single.payload['content'],
          containsPair('introduction', 'New inherited introduction'),
        );
      },
    );
  }

  for (final oldSave in [false, true]) {
    testWidgets(
      'explicit introduction clear imports only with matching operation ($oldSave)',
      (tester) async {
        final h = _EditorHarness(versioned: false);
        h.connection.content!['avatarStyle'] = 0;
        h.connection.useOperationBoundProfileFiles(_profileFolder());
        await h.open(tester);
        await _enterAbout(tester, '');
        await _tap(tester, 'profile-save');
        expect(h.connection.localSaveCount, 1);
        final save = h.connection.requests.singleWhere(
          (request) => request.name == 'personalProfile.localSave',
        );
        expect(save.payload['content'], containsPair('introduction', ''));
        expect(
          save.payload['content'],
          containsPair('fieldStates', {'introduction': true}),
        );
        expect(save.payload['content'], isNot(contains('preserveEmptyFields')));

        if (oldSave) h.connection.saveAsOldClient('');
        h.connection
          ..versioned = true
          ..style = 3
          ..wallpaper = 'levski-yard'
          ..groupOrigins.addAll({
            'introduction': 'linkedLegacy',
            'avatarStyle': 'linkedLegacy',
            'wallpaper': 'linkedLegacy',
          });
        await h.module.refresh();
        await tester.pumpAndSettle();
        if (oldSave) {
          expect(h.connection.operation, 'b' * 32);
          expect(h.connection.writes, isEmpty);
          expect(h.connection.pageAbout, 'Previous page');
        } else {
          expect(h.connection.writtenGroups, [
            ['introduction'],
          ]);
          expect(
            h.connection.writes.single.payload['content'],
            containsPair('introduction', ''),
          );
          expect(h.connection.pageAbout, isEmpty);
        }
        expect(h.connection.style, 3);
        expect(h.connection.wallpaper, 'levski-yard');
      },
    );
  }

  testWidgets(
    'old introduction-only save cannot import avatar and background',
    (tester) async {
      final h = _EditorHarness(versioned: false);
      h.connection
        ..content = {'callSign': 'Local fixture', 'introduction': 'Local bio'}
        ..useOperationBoundProfileFiles(_profileFolder());
      await h.open(tester);
      await _enterAbout(tester, 'Edited locally');
      await _tap(tester, 'profile-save');
      expect(h.connection.localSaveCount, 1);
      h.connection
        ..saveAsOldClient('Edited by old client')
        ..versioned = true
        ..style = 3
        ..wallpaper = 'levski-yard'
        ..groupOrigins.addAll({
          'introduction': 'linkedLegacy',
          'avatarStyle': 'linkedLegacy',
          'wallpaper': 'linkedLegacy',
        });
      await h.module.refresh();
      await tester.pumpAndSettle();
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);
      final payload = h.connection.writes.single.payload;
      // The page contract carries unchanged avatar and wallpaper in the full body.
      expect(payload['avatarStyle'], 3);
      expect(payload['wallpaperId'], 'levski-yard');
      expect(h.connection.pageAbout, 'Edited by old client');
      expect(h.connection.style, 3);
      expect(h.connection.wallpaper, 'levski-yard');
    },
  );

  testWidgets('added interest follows the latest remote tag order', (
    tester,
  ) async {
    final h = _EditorHarness();
    h.connection
      ..groupOrigins['playStyle'] = 'linkedLegacy'
      ..pageFields['participationInterests'] = ['pve', 'mining'];
    await h.open(tester);
    await _tap(tester, 'profile-interests-editor');
    await _tap(tester, 'profile-interests-salvage');
    h.connection
      ..pageRevision += 1
      ..pageFields['participationInterests'] = ['mining', 'pve'];
    await _tap(tester, 'profile-save');
    expect(h.connection.writtenGroups, [
      ['playStyle'],
    ]);
    expect(h.connection.writes.single.payload['expectedRevision'], 8);
    expect(
      h.connection.writes.single.payload['content'],
      containsPair('participationInterests', ['mining', 'pve', 'salvage']),
    );
  });

  testWidgets('reselecting an inherited interest only saves introduction', (
    tester,
  ) async {
    final h = _EditorHarness();
    h.connection
      ..groupOrigins['playStyle'] = 'linkedLegacy'
      ..pageFields['participationInterests'] = ['pve', 'mining'];
    await h.open(tester);
    await _tap(tester, 'profile-interests-editor');
    await _tap(tester, 'profile-interests-pve');
    await _tap(tester, 'profile-interests-pve');
    expect(_editor(tester).captureDraft().edit.playStyle?.interests, [
      'mining',
      'pve',
    ]);
    await _enterAbout(tester, 'Only introduction');
    await _tap(tester, 'profile-save');
    expect(h.connection.writtenGroups, [
      ['introduction'],
    ]);
    expect(
      h.connection.writes.single.payload['content'],
      containsPair('participationInterests', ['pve', 'mining']),
    );
    expect(h.connection.content, isNot(contains('playStyle')));
    expect(h.connection.groupOrigins['playStyle'], 'linkedLegacy');
  });

  for (final versioned in [false, true]) {
    testWidgets(
      'open draft rebases after unrelated local migration ($versioned)',
      (tester) async {
        final h = _EditorHarness(versioned: versioned);
        await h.open(tester);
        h.connection
          ..revision += 1
          ..content!['avatarStyle'] = 3
          ..notifyProfileChanged();
        await tester.pumpAndSettle();
        await _enterAbout(tester, 'Draft after migration');
        await _tap(tester, 'profile-save');

        expect(_localSaveRevisions(h), [1, 2]);
        expect(
          h.connection.content,
          containsPair('introduction', 'Draft after migration'),
        );
        expect(h.connection.content, containsPair('avatarStyle', 3));
        expect(find.byType(PersonalProfileEditorPanel), findsNothing);
        expect(
          h.connection.writtenGroups,
          versioned
              ? [
                  ['introduction'],
                ]
              : isEmpty,
        );
      },
    );
  }

  testWidgets('local same-group conflict preserves draft and remote receipt', (
    tester,
  ) async {
    final h = _EditorHarness();
    await h.open(tester);
    h.connection
      ..revision += 1
      ..content = {
        ...h.connection.content!,
        'introduction': 'Migration introduction',
      }
      ..notifyProfileChanged();
    await tester.pumpAndSettle();
    await _enterAbout(tester, 'Draft after migration');
    await _tap(tester, 'profile-save');

    expect(_localSaveRevisions(h), [1]);
    expect(h.connection.content?['introduction'], 'Migration introduction');
    expect(h.connection.pageAbout, 'Draft after migration');
    expect(
      h.module.projection.value.failureKey,
      'profile.error.confirmConflictingGroups',
    );
    expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
    expect(_editor(tester).captureDraft().edit.about, 'Draft after migration');

    await _tap(tester, 'profile-save');
    expect(_localSaveRevisions(h), [1, 2]);
    expect(h.connection.content?['introduction'], 'Draft after migration');
    expect(h.connection.writtenGroups, [
      ['introduction'],
    ]);
    expect(find.byType(PersonalProfileEditorPanel), findsNothing);
  });

  testWidgets(
    'unversioned introduction keeps both local same-model instances',
    (tester) async {
      final h = _EditorHarness(versioned: false, picks: [shipA, shipB]);
      await h.open(tester);
      final displayed = h.module.projection.value.moduleLayout.firstWhere(
        (item) => item.moduleId == 'favorite-ships',
      );
      expect(displayed.favoriteShipIds, [shipA]);

      await _enterAbout(tester, 'Edited introduction');
      await _tap(tester, 'profile-save');

      expect(h.connection.localSaveCount, 1);
      expect(h.connection.content?['introduction'], 'Edited introduction');
      expect(h.connection.content?['favoriteShipIds'], [shipA, shipB]);
      expect(
        (h.connection.content!['modules'] as List).single,
        _favorite([shipA, shipB]),
      );
      expect(h.connection.writes, isEmpty);
    },
  );

  for (final materialized in [false, true]) {
    testWidgets(
      'unversioned S2 shell cannot import over linked layout ($materialized)',
      (tester) async {
        final h = _EditorHarness(versioned: false);
        final local = h.connection.content!;
        if (materialized) {
          local['preserveEmptyFields'] = true;
          (local['modules'] as List<Map<String, Object?>>).addAll([
            {
              'id': 'hangar-summary',
              'span': 3,
              'isVisible': false,
              'position': -1,
            },
            {
              'id': 'skilled-roles',
              'span': 2,
              'isVisible': false,
              'position': -1,
            },
          ]);
          local['showcases'] = [
            {'id': 'favorite-ships', 'isVisible': true},
            {'id': 'trade-card', 'isVisible': true},
            {'id': 'achievements', 'isVisible': false},
          ];
        }
        final expected = {...local, 'introduction': 'Edited introduction'};
        await h.open(tester);
        await _enterAbout(tester, 'Edited introduction');
        await _tap(tester, 'profile-save');
        expect(h.connection.localSaveCount, 1);
        expect(h.connection.content, expected);

        h.connection
          ..versioned = true
          ..sourceVersion = 'a' * 64
          ..groupOrigins['layout'] = 'linkedLegacy'
          ..modules = [
            {
              'id': 'hangar-summary',
              'span': 2,
              'isVisible': true,
              'position': 0,
            },
          ];
        await h.module.refresh();
        await tester.pumpAndSettle();
        expect(h.connection.writes, isEmpty);
        expect(
          h.module.projection.value.moduleLayout
              .where((item) => item.isVisible)
              .map((item) => item.moduleId),
          contains('hangar-summary'),
        );
      },
    );
  }

  testWidgets(
    'reverted schedule and play style are omitted by the real editor',
    (tester) async {
      final h = _EditorHarness();
      h.connection.groupOrigins.addAll({
        'schedule': 'linkedLegacy',
        'playStyle': 'linkedLegacy',
      });
      h.connection.pageFields.addAll({
        'activityRhythm': '稳定活跃',
        'showOnlineTime': true,
        'availabilityTimeZoneId': 'UTC',
        'availabilityWindows': [
          {
            'days': [1, 2],
            'startTime': '19:00',
            'endTime': '22:00',
          },
        ],
        'participationInterests': ['pve'],
      });
      await h.open(tester);
      expect(
        h.module.projection.value.activityRhythm,
        PersonalProfileActivityRhythm.regular,
      );
      await _tap(tester, 'profile-schedule-editor');
      for (final rhythm in [
        PersonalProfileActivityRhythm.intensive,
        PersonalProfileActivityRhythm.regular,
      ]) {
        await _tap(tester, 'profile-schedule-rhythm-trigger');
        await _activate(
          tester,
          find.byKey(ValueKey<Object>(('profile-schedule-rhythm', rhythm))),
        );
      }
      await _tap(tester, 'profile-interests-editor');
      await _tap(tester, 'profile-interests-mining');
      await _tap(tester, 'profile-interests-mining');
      final captured = _editor(tester).captureDraft().edit;
      expect(captured.schedule?.rhythm, PersonalProfileActivityRhythm.regular);
      expect(captured.playStyle?.interests, ['pve']);

      await _enterAbout(tester, 'Only introduction');
      await _tap(tester, 'profile-save');
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);
      expect(h.connection.groupOrigins, {
        'schedule': 'linkedLegacy',
        'playStyle': 'linkedLegacy',
      });
      expect(h.connection.content!.keys, isNot(contains('schedule')));
      expect(h.connection.content!.keys, isNot(contains('playStyle')));
    },
  );

  testWidgets('unrelated remote revision advances without blocking the draft', (
    tester,
  ) async {
    final h = _EditorHarness();
    await h.open(tester);
    await _enterAbout(tester, 'My draft');
    h.connection
      ..pageRevision += 1
      ..style = 3;

    await _tap(tester, 'profile-save');

    expect(h.connection.writtenGroups, [
      ['introduction'],
    ]);
    expect(h.connection.writes.single.payload['expectedRevision'], 8);
    expect(h.connection.writes.single.payload['avatarStyle'], 3);
    expect(h.connection.style, 3);
    expect(h.connection.pageAbout, 'My draft');
    expect(h.connection.localSaveCount, 1);
  });

  for (final originOnly in [false, true]) {
    testWidgets(
      'same-group conflict retains the draft and allows confirmation ($originOnly)',
      (tester) async {
        final h = _EditorHarness();
        await h.open(tester);
        await _enterAbout(tester, 'My retained draft');
        h.connection.pageRevision++;
        if (originOnly) {
          h.connection.groupOrigins['introduction'] = 'linkedLegacy';
        } else {
          h.connection.pageAbout = 'Other device introduction';
        }

        await _tap(tester, 'profile-save');
        expect(h.connection.writes, isEmpty);
        expect(h.connection.localSaveCount, 0);
        expect(
          h.module.projection.value.failureKey,
          'profile.error.confirmConflictingGroups',
        );
        expect(find.byKey(const Key('profile-save-error')), findsOneWidget);
        expect(_editor(tester).captureDraft().edit.about, 'My retained draft');

        await _tap(tester, 'profile-save');
        expect(h.connection.writtenGroups, [
          ['introduction'],
        ]);
        expect(h.connection.writes.single.payload['expectedRevision'], 8);
        expect(h.connection.pageAbout, 'My retained draft');
        expect(h.connection.localSaveCount, 1);
      },
    );
  }

  testWidgets(
    'lost menu import receipt and stale read rebase the open editor',
    (tester) async {
      final h = _EditorHarness();
      h.connection.groupOrigins['introduction'] = 'default';
      await h.open(tester);
      _editor(tester).restoreAvatarStyle(2);
      await tester.pumpAndSettle();
      h.connection
        ..content!['introduction'] = 'Imported from disk'
        ..loseCommitReceipt = true;
      await h.menu.read();
      expect(h.connection.pageRevision, 8);
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);

      h.connection.staleReadsRemaining = 1;
      await h.menu.read();
      expect(h.connection.writtenGroups, [
        ['introduction'],
      ]);

      h.connection.staleReadsRemaining = 1;
      await _tap(tester, 'profile-save');
      expect(h.connection.writtenGroups, [
        ['introduction'],
        ['avatarStyle'],
        ['avatarStyle'],
      ]);
      expect(
        h.connection.writes.map((write) => write.payload['expectedRevision']),
        [7, 7, 8],
      );
      expect(h.connection.pageRevision, 9);
      expect(h.connection.pageAbout, 'Imported from disk');
      expect(h.connection.style, 2);
    },
  );

  for (final versioned in [false, true]) {
    testWidgets('migration change uses the normal owner read ($versioned)', (
      tester,
    ) async {
      final h = _EditorHarness(versioned: versioned);
      h.connection.groupOrigins['introduction'] = 'linkedLegacy';
      await h.module.initialize();
      expect(h.module.projection.value.about, 'Previous page');
      h.connection
        ..revision += 1
        ..content!['introduction'] = 'Selected migration introduction'
        ..notifyProfileChanged();
      await tester.pumpAndSettle();

      expect(
        h.module.projection.value.about,
        'Selected migration introduction',
      );
      expect(
        h.connection.writtenGroups,
        versioned
            ? [
                ['introduction'],
              ]
            : isEmpty,
      );
      expect(h.connection.localSaveCount, 0);
    });
  }

  testWidgets('main window import confirmation refreshes a pending menu', (
    tester,
  ) async {
    final h = _EditorHarness();
    h.connection
      ..groupOrigins['introduction'] = 'default'
      ..content!['introduction'] = 'Pending introduction';
    final gate = h.connection.blockNextWrite();
    final initializing = h.module.initialize();
    await gate.started.future;
    final views = <Map<String, Object?>>[];
    final menu = MenuProfilesSession(
      () => throw StateError('Self must use its own port'),
      views.add,
      createOwnPort: () => h.menu,
    );
    addTearDown(menu.dispose);
    try {
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
      await tester.pumpAndSettle();
      expect(MenuProfileView.parse(views.last).autoImportPending, isTrue);
    } finally {
      gate.finish.complete();
    }
    await initializing;
    await tester.pumpAndSettle();
    final settled = MenuProfileView.parse(views.last);
    expect(settled.autoImportPending, isFalse);
    expect(settled.snapshot?.about, 'Pending introduction');
    expect(h.connection.writtenGroups, [
      ['introduction'],
    ]);
    expect(h.connection.localSaveCount, 0);
    menu.dispose();
  });

  for (final versioned in [false, true]) {
    testWidgets(
      'avatar-only production-path guard preserves local file bytes ($versioned)',
      (tester) async {
        final h = _EditorHarness(versioned: versioned, picks: [shipA, shipB]);
        h.connection.content!.addAll({
          'introduction': '仅保存在本机的资料',
          'showcases': [
            {'id': 'favorite-ships', 'isVisible': true},
          ],
          'achievementShowcase': ['fixture-achievement'],
          'playStyle': {
            'interests': ['pve'],
          },
          'schedule': {'timeZoneId': 'UTC', 'rhythm': 'regular', 'windows': []},
        });
        final folder = Directory.current.createTempSync('profile-r4-fixture-');
        addTearDown(() => folder.deleteSync(recursive: true));
        final file = File(
          '${folder.path}${Platform.pathSeparator}profile.json',
        );
        h.connection.useLocalContentFile(file);
        final before = file.readAsBytesSync();
        await h.open(tester);
        // Guard: bypassing BridgeLocalPersonalProfile must fail the local write and byte assertions.
        // Use the editor's avatar-style draft restore path, then its normal Save control.
        _editor(tester).restoreAvatarStyle(2);
        await tester.pumpAndSettle();
        await _tap(tester, 'profile-save');

        expect(
          h.connection.writtenGroups,
          versioned
              ? [
                  ['avatarStyle'],
                ]
              : isEmpty,
        );
        expect(h.connection.localSaveCount, 1);
        expect(
          h.connection.requests.where(
            (request) => request.name == 'personalProfile.updateSelf',
          ),
          isEmpty,
        );
        final expected = utf8.encode(
          utf8
              .decode(before)
              .replaceFirst('"avatarStyle":1', '"avatarStyle":2'),
        );
        expect(file.readAsBytesSync(), orderedEquals(expected));
      },
    );
  }
}

class _EditorHarness {
  _EditorHarness({bool versioned = true, List<String> picks = const []}) {
    connection
      ..versioned = versioned
      ..eligibleGroup = null
      ..content = {
        'callSign': 'Local fixture',
        'introduction': 'Previous page',
        'avatarStyle': 1,
        'wallpaperId': 'none',
        'modules': [_favorite(picks)],
        'favoriteShipIds': picks,
      };
    session = BridgeClientSession(connection: connection, sessionGeneration: 7);
    session.acceptHostCapabilities(['personalProfile.presentation.write.v1']);
    main = _port();
    menu = _port();
    module = createPersonalProfileModule(main);
    addTearDown(() async {
      module.dispose();
      await Future.wait([main.close(), menu.close()]);
      await session.close();
    });
  }

  final connection = AutoImportPageConnection();
  final hangar = SavedHangar()
    ..snapshot = const LocalHangarSnapshot(
      revision: 1,
      ships: [
        LocalHangarShip(
          id: shipA,
          title: 'First instance',
          catalogId: 'MODEL_A',
        ),
        LocalHangarShip(
          id: shipB,
          title: 'Second instance',
          catalogId: 'MODEL_A',
        ),
      ],
    );
  late final BridgeClientSession session;
  late final BridgeLocalPersonalProfile main, menu;
  late final PersonalProfileModule module;

  BridgeLocalPersonalProfile _port() => BridgeLocalPersonalProfile(
    session,
    remote: BridgePersonalProfileAdapter(session),
    hangar: () => hangar,
  );

  Future<void> open(WidgetTester tester) async {
    size(tester, const Size(1600, 1400));
    await module.initialize();
    await tester.pumpWidget(app(PersonalProfilePage(module: module)));
    await tester.pumpAndSettle();
    await _tap(tester, 'profile-edit');
  }
}

Directory _profileFolder() {
  final folder = Directory.current.createTempSync('profile-r5-fixture-');
  addTearDown(() => folder.deleteSync(recursive: true));
  return folder;
}

Map<String, Object?> _favorite(List<String> picks) => {
  'id': 'favorite-ships',
  'span': 3,
  'isVisible': true,
  'position': 0,
  'favoriteShipIds': picks,
};

Iterable<Object?> _localSaveRevisions(_EditorHarness harness) => harness
    .connection
    .requests
    .where((request) => request.name == 'personalProfile.localSave')
    .map((request) => request.payload['expectedRevision']);

PersonalProfileEditorPanelState _editor(WidgetTester tester) =>
    tester.state<PersonalProfileEditorPanelState>(
      find.byType(PersonalProfileEditorPanel),
    );

Future<void> _enterAbout(WidgetTester tester, String value) async {
  final field = find.byKey(const Key('profile-about-field'));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) =>
    _activate(tester, find.byKey(Key(key)));

Future<void> _activate(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
}
