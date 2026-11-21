import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/direct_message_privacy_module.dart';
import 'package:starbridge_flutter/features/settings/host_unavailable_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/organization_privacy_pane.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import 'local_privacy_page_test.dart' show app, viewport;
import 'official_runtime_privacy_test.dart' show OfficialPrivacyFixture;
import 'privacy_settings_page_test.dart' show MemoryDirectMessagePrivacy;

CommunitySharingScope _scope(String code, int fields) => CommunitySharingScope(
  code: code,
  joinedAt: '2026-01-01T00:00:00Z',
  fields: fields,
  administratorsCanView: false,
  allMembersCanView: true,
);

LocalPrivacySettings _unshared() => LocalPrivacySettings(
  publicationEnabled: false,
  fleetFields: 0,
  fleetAdministratorsCanView: false,
  fleetAllMembersCanView: false,
  fleetVisibilityGroupIds: const [],
  roomFields: 0,
  roomAllMembersCanView: false,
  communities: const [],
);

class _Privacy
    implements LocalPrivacyPort, CommunitySharingPort, PrivacyPublicationPort {
  LocalPrivacySettings? settings;
  int writes = 0;
  // The Flutter publication contract represents paused sharing as withdrawn.
  String state = 'withdrawn';
  final actions = <String>[];
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get communitySharingSupported => true;
  @override
  bool get publicationSupported => true;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() async =>
      CommunitySharingTargets(
        communities: [
          for (final code in ['A', 'B'])
            CommunitySharingTarget(
              code: code,
              name: code,
              joinedAt: '2026-01-01T00:00:00Z',
            ),
        ],
      );
  @override
  Future<LocalPrivacySnapshot> read() async =>
      LocalPrivacySnapshot(revision: writes, settings: settings);
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings next) async {
    writes++;
    settings = LocalPrivacySettings.fromJson(next.toJson());
    return read();
  }

  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
    bool firstOfficialDefault = false,
  }) async {
    actions.add(action);
    if (action == 'apply') state = 'applied';
    if (action == 'stop') state = 'withdrawn';
    return PrivacyPublicationView(
      state,
      revision: revision,
      firstUseRequired: false,
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  for (final consent in <bool?>[null, false, true]) {
    testWidgets(
      'remote failure saves explicit fields and applies saved consent: consent=$consent',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final baseline = _unshared();
        final saved = consent == null
            ? null
            : baseline.copyWith(
                publicationEnabled: consent,
                fleetFields: LocalPrivacySettings.location,
                fleetAdministratorsCanView: true,
              );
        final port = _Privacy()..settings = saved;
        final local = LocalPrivacyController(port);
        final sync = createSyncPrivacyModule(
          HostUnavailableSyncPrivacyAdapter(),
        );
        final accountPort = _FailingAccountPrivacy();
        final account = DirectMessagePrivacyModule(accountPort);
        addTearDown(local.dispose);
        addTearDown(sync.dispose);
        addTearDown(account.dispose);
        await sync.initialize();
        await account.initialize();
        await tester.pumpWidget(
          app(
            PrivacySettingsPage(
              localPrivacy: local,
              syncPrivacy: sync,
              directMessagePrivacy: account,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(local.hasSaved, consent != null);
        local.edit(
          local.draft!.copyWith(fleetFields: LocalPrivacySettings.ship),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-section-account')));
        await tester.pumpAndSettle();
        final toggle = find.byKey(
          const Key('privacy-stranger-messages-authoritative'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-save')));
        await tester.pumpAndSettle();
        expect(accountPort.writes, 1);
        expect(accountPort.value, isFalse);
        expect(port.writes, 1);
        // Compare the entire serialized storage contract, including absent
        // optional defaults, rather than merely observing that a write happened.
        final expected = (saved ?? baseline).copyWith(
          fleetFields: LocalPrivacySettings.ship,
        );
        expect(port.settings!.toJson(), expected.toJson());
        expect(local.savedSettings!.toJson(), expected.toJson());
        expect(local.dirty, isFalse);
        final expectedState = consent == true ? 'applied' : 'withdrawn';
        expect(port.state, expectedState);
        expect(local.publicationView.state, expectedState);
        expect(port.actions.where((action) => action != 'status'), [
          consent == true ? 'apply' : 'stop',
        ]);
        expect(find.text('部分更改未能确认保存，草稿已保留。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final enabled in [true, false]) {
    for (final leaveSave in [false, true]) {
      testWidgets(
        'remote failure commits explicit consent and runs publication once: enabled=$enabled/leave=$leaveSave',
        (tester) async {
          viewport(tester, const Size(1280, 1000));
          final saved = _unshared().copyWith(publicationEnabled: !enabled);
          final port = _Privacy()
            ..settings = saved
            ..state = enabled ? 'withdrawn' : 'applied';
          final local = LocalPrivacyController(port);
          final sync = createSyncPrivacyModule(
            HostUnavailableSyncPrivacyAdapter(),
          );
          final accountPort = _FailingAccountPrivacy();
          final account = DirectMessagePrivacyModule(accountPort);
          addTearDown(local.dispose);
          addTearDown(sync.dispose);
          addTearDown(account.dispose);
          await sync.initialize();
          await account.initialize();
          await tester.pumpWidget(
            app(
              PrivacySettingsPage(
                localPrivacy: local,
                syncPrivacy: sync,
                directMessagePrivacy: account,
              ),
            ),
          );
          await tester.pumpAndSettle();
          // Use the page's actual consent control, then stage a remote edit.
          final consentToggle = find.byKey(const Key('privacy-publication'));
          await tester.ensureVisible(consentToggle);
          await tester.tap(consentToggle);
          await tester.pumpAndSettle();
          expect(local.draft!.publicationEnabled, enabled);
          await tester.tap(find.byKey(const Key('privacy-section-account')));
          await tester.pumpAndSettle();
          final toggle = find.byKey(
            const Key('privacy-stranger-messages-authoritative'),
          );
          await tester.ensureVisible(toggle);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          Future<bool>? leave;
          if (leaveSave) {
            leave = confirmLocalPrivacyLeave(
              tester.element(find.byType(PrivacySettingsPage)),
              local,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const Key('privacy-leave-save')));
          } else {
            await tester.tap(find.byKey(const Key('privacy-save')));
          }
          await tester.pumpAndSettle();
          if (leaveSave) expect(await leave, isFalse);
          expect(accountPort.writes, 1);
          expect(accountPort.value, isFalse);
          expect(port.writes, 1);
          final expected = saved.copyWith(publicationEnabled: enabled);
          expect(port.settings!.toJson(), expected.toJson());
          expect(local.savedSettings!.toJson(), expected.toJson());
          expect(local.dirty, isFalse);
          expect(port.actions.where((a) => a != 'status'), [
            enabled ? 'apply' : 'stop',
          ]);
          expect(
            local.publicationView.state,
            enabled ? 'applied' : 'withdrawn',
          );
          expect(find.text('部分更改未能确认保存，草稿已保留。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final consent in <bool?>[null, false, true]) {
    testWidgets(
      'remote-only failure never submits local settings: consent=$consent',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final saved = consent == null
            ? null
            : _unshared().copyWith(publicationEnabled: consent);
        final port = _Privacy()..settings = saved;
        final local = LocalPrivacyController(port);
        final sync = createSyncPrivacyModule(
          HostUnavailableSyncPrivacyAdapter(),
        );
        final accountPort = _FailingAccountPrivacy();
        final account = DirectMessagePrivacyModule(accountPort);
        addTearDown(local.dispose);
        addTearDown(sync.dispose);
        addTearDown(account.dispose);
        await sync.initialize();
        await account.initialize();
        await tester.pumpWidget(
          app(
            PrivacySettingsPage(
              localPrivacy: local,
              syncPrivacy: sync,
              directMessagePrivacy: account,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-section-account')));
        await tester.pumpAndSettle();
        final toggle = find.byKey(
          const Key('privacy-stranger-messages-authoritative'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-save')));
        await tester.pumpAndSettle();
        expect(accountPort.writes, 1);
        expect(accountPort.value, isFalse);
        expect(port.writes, 0);
        expect(port.settings?.toJson(), saved?.toJson());
        expect(local.hasSaved, consent != null);
        expect(local.dirty, isFalse);
        expect(port.state, 'withdrawn');
        expect(port.actions.where((a) => a != 'status'), isEmpty);
        expect(find.text('部分更改未能确认保存，草稿已保留。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('old leave dialog cannot save after the organization changes', (
    tester,
  ) async {
    viewport(tester, const Size(1280, 1000));
    final port = _Privacy()
      ..settings = _unshared().copyWith(
        communities: [_scope('A', 0), _scope('B', 0)],
      );
    final c = LocalPrivacyController(port);
    final selected = ValueNotifier('A');
    addTearDown(c.dispose);
    addTearDown(selected.dispose);
    await c.refresh();
    Future<bool>? leave;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => leave = confirmLocalPrivacyLeave(context, c),
                child: const Text('close'),
              ),
              ValueListenableBuilder<String>(
                valueListenable: selected,
                builder: (_, code, _) =>
                    OrganizationPrivacyPane(controller: c, communityCode: code),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    c.edit(c.draft!.copyWith(communities: [_scope('A', 1), _scope('B', 2)]));
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    selected.value = 'B';
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-leave-save')));
    await tester.pumpAndSettle();
    expect(await leave, isFalse);
    expect(port.writes, 0);
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy-leave-save')));
    await tester.pumpAndSettle();
    expect(await leave, isTrue);
    expect(
      port.settings!.communities!.singleWhere((s) => s.code == 'A').fields,
      0,
    );
    expect(
      port.settings!.communities!.singleWhere((s) => s.code == 'B').fields,
      2,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final official in [false, true]) {
    testWidgets(
      'close save uses organization button action: official=$official',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final initial = _unshared().copyWith(
          publicationEnabled: true,
          communities: [_scope('A', 0), _scope('B', 2)],
        );
        final port = _Privacy()..settings = initial;
        final officialPort = OfficialPrivacyFixture()
          ..settings = initial
          ..publicationState = 'withdrawn';
        final c = LocalPrivacyController(official ? officialPort : port);
        addTearDown(c.dispose);
        await c.refresh();
        Future<bool>? leave;
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () =>
                        leave = confirmLocalPrivacyLeave(context, c),
                    child: const Text('close'),
                  ),
                  OrganizationPrivacyPane(
                    controller: c,
                    communityCode: official ? null : 'A',
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.edit(
          c.draft!.copyWith(
            roomFields: 15,
            communities: [_scope('A', 1), _scope('B', 7)],
          ),
        );
        if (official) c.editOfficialFields(3);
        await tester.tap(find.text('close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-leave-save')));
        await tester.pumpAndSettle();
        expect(await leave, isTrue);
        final saved = official ? officialPort.settings : port.settings!;
        expect(saved.publicationEnabled, isTrue);
        expect(saved.roomFields, 0);
        expect(saved.communities!.singleWhere((s) => s.code == 'B').fields, 2);
        expect(
          saved.communities!.singleWhere((s) => s.code == 'A').fields,
          official ? 0 : 1,
        );
        if (official) {
          expect(officialPort.savedFields, 3);
          expect(officialPort.publicationState, 'withdrawn');
          expect(
            officialPort.calls.where((a) => a == 'publication.apply'),
            isEmpty,
          );
        } else {
          expect(port.state, 'withdrawn');
          expect(port.actions.where((a) => a != 'status'), isEmpty);
          expect(port.writes, 1);
        }
        expect(
          c.draft!.roomFields,
          15,
          reason: 'Other pending edits stay in the draft',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final editRoom in [false, true]) {
    testWidgets(
      'first community save then account-only save: editRoom=$editRoom',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final port = _Privacy();
        final c = LocalPrivacyController(port);
        final sync = createSyncPrivacyModule(
          HostUnavailableSyncPrivacyAdapter(),
        );
        final accountPort = MemoryDirectMessagePrivacy();
        final account = DirectMessagePrivacyModule(accountPort);
        addTearDown(c.dispose);
        addTearDown(sync.dispose);
        addTearDown(account.dispose);
        await sync.initialize();
        await account.initialize();
        await c.refresh();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OrganizationPrivacyPane(controller: c, communityCode: 'A'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        c.enableCommunityChoices();
        c.editCommunity(_scope('A', 1));
        if (editRoom) c.edit(c.draft!.copyWith(roomFields: 3));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('organization-privacy-save')));
        await tester.pumpAndSettle();
        expect(port.writes, 1);
        expect(c.dirty, editRoom);
        expect(c.draft!.publicationEnabled, isFalse);
        expect(c.draft!.roomFields, editRoom ? 3 : 0);
        expect(c.draft!.roomAllMembersCanView, isFalse);
        expect(c.draft!.fleetAllMembersCanView, isFalse);
        if (editRoom) c.discard();
        final saved = port.settings!.toJson();
        await tester.pumpWidget(
          app(
            PrivacySettingsPage(
              localPrivacy: c,
              syncPrivacy: sync,
              directMessagePrivacy: account,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-section-account')));
        await tester.pumpAndSettle();
        final toggle = find.byKey(
          const Key('privacy-stranger-messages-authoritative'),
        );
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('privacy-save')));
        await tester.pumpAndSettle();
        expect(accountPort.value, isTrue);
        expect(
          port.writes,
          1,
          reason: 'Account save must not resubmit local sharing',
        );
        expect(port.settings!.toJson(), saved);
        expect(port.settings!.publicationEnabled, isFalse);
        expect(port.settings!.roomFields, 0);
        expect(port.actions.where((a) => a != 'status'), isEmpty);
        expect(c.dirty, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _FailingAccountPrivacy implements DirectMessagePrivacyPort {
  int writes = 0;
  bool value = false;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<DirectMessagePrivacySnapshot> read() async =>
      DirectMessagePrivacySnapshot.available(
        allowStrangerDirectMessages: value,
        updatedAt: null,
      );
  @override
  Future<DirectMessagePrivacyWriteResult> save(bool next) async {
    writes++;
    return const DirectMessagePrivacyWriteResult.rejected(
      DirectMessagePrivacyFailure.writeFailed,
    );
  }

  @override
  Future<void> close() async {}
}
