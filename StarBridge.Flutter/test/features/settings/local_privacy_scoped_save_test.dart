import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/organization_privacy_pane.dart';
import 'package:starbridge_flutter/features/settings/community_sharing.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_scoped_save.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/official_runtime_privacy_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import 'official_runtime_privacy_test.dart' show OfficialPrivacyFixture;
import 'local_privacy_page_test.dart' show app, viewport;

const _joined = '2026-01-01T00:00:00Z';

CommunitySharingScope _scope(String code, {int fields = 0}) =>
    CommunitySharingScope(
      code: code,
      joinedAt: _joined,
      fields: fields,
      administratorsCanView: false,
      allMembersCanView: false,
    );

CommunitySharingScope _in(LocalPrivacySettings settings, String code) =>
    settings.communities!.singleWhere((s) => s.code == code);

class _StoredPrivacy
    implements LocalPrivacyPort, CommunitySharingPort, PrivacyPublicationPort {
  _StoredPrivacy(this.settings);
  LocalPrivacySettings? settings;
  int revision = 0;
  String publicationState = 'applied';
  bool firstUseRequired = false;
  final actions = <String>[];
  @override
  bool get publicationSupported => true;
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
    bool firstOfficialDefault = false,
  }) async {
    actions.add(action);
    return PrivacyPublicationView(
      publicationState,
      revision: revision,
      firstUseRequired: firstUseRequired,
    );
  }

  @override
  bool get communitySharingSupported => true;
  @override
  Future<CommunitySharingTargets> readCommunityTargets() async =>
      CommunitySharingTargets(
        primaryFleetCode: 'B',
        communities: [
          for (final code in ['A', 'B'])
            CommunitySharingTarget(code: code, name: code, joinedAt: _joined),
        ],
      );
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<LocalPrivacySnapshot> read() async =>
      LocalPrivacySnapshot(revision: revision, settings: settings);
  @override
  Future<LocalPrivacySnapshot> save(LocalPrivacySettings next) async {
    settings = LocalPrivacySettings.fromJson(next.toJson());
    revision++;
    return read();
  }

  @override
  Future<void> close() async {}
}

class _UnsavedOfficialPrivacy extends _StoredPrivacy
    implements OfficialRuntimePrivacyPort {
  _UnsavedOfficialPrivacy() : super(null);
  int officialSaves = 0;
  @override
  bool get officialRuntimePrivacySupported => true;
  @override
  Stream<void> get officialRuntimePrivacyInvalidations => const Stream.empty();
  @override
  Future<OfficialRuntimePrivacySnapshot> readOfficialRuntimePrivacy() async =>
      OfficialRuntimePrivacySnapshot(
        state: 'available',
        revision: revision,
        fields: 15,
        savedFields: 0,
        savedForCurrentSource: false,
        choiceRequired: true,
        canSave: true,
        canCancel: false,
        sourceRef: 'officialFleet:7',
        scopeRef: 'scope',
        contextRef: 'context',
      );
  @override
  Future<OfficialRuntimePrivacySaveReceipt> saveOfficialRuntimePrivacy({
    required OfficialRuntimePrivacySnapshot scope,
    required int expectedRevision,
    required int fields,
    required bool cancelSavedScope,
    OfficialFleetAudience? audience,
  }) async {
    officialSaves++;
    throw StateError('No official edit should be submitted');
  }
}

// Mirrors the Host's zero-grant baseline, never the editor's suggestions.
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

Future<(OfficialPrivacyFixture, LocalPrivacyController)> _open() async {
  final port = OfficialPrivacyFixture()
    ..settings = LocalPrivacySettings.editorDefaults.copyWith(
      publicationEnabled: true,
      roomFields: 0,
      communities: [_scope('A'), _scope('B')],
    );
  final controller = LocalPrivacyController(port);
  addTearDown(controller.dispose);
  await controller.refresh();
  return (port, controller);
}

void _editBoth(LocalPrivacyController c) {
  c.edit(
    c.draft!.copyWith(
      roomFields: 15,
      communities: [_scope('A', fields: 1), _scope('B', fields: 2)],
    ),
  );
}

void main() {
  for (final official in [false, true]) {
    testWidgets(
      'paused organization save shows existing local-only status: official=$official',
      (tester) async {
        viewport(tester, const Size(1280, 1000));
        final localPort = _StoredPrivacy(
          _unshared().copyWith(communities: [_scope('A')]),
        )..publicationState = 'withdrawn';
        final officialPort = OfficialPrivacyFixture()
          ..publicationState = 'withdrawn';
        final c = LocalPrivacyController(official ? officialPort : localPort);
        addTearDown(c.dispose);
        await c.refresh();
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OrganizationPrivacyPane(
                controller: c,
                communityCode: official ? null : 'A',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (official) {
          c.editOfficialFields(1);
        } else {
          c.editCommunity(_scope('A', fields: 1));
        }
        await tester.pumpAndSettle();
        final save = find.byKey(const Key('organization-privacy-save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('已保存到本机 · 尚未对外生效'), findsWidgets);
        expect(c.publicationView.state, 'withdrawn');
        expect(localPort.actions.where((a) => a != 'status'), isEmpty);
        expect(officialPort.applies, 0);
        expect(find.text('待确认'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final (enabled, state, firstUse) in [
    (false, 'inactive', true),
    (true, 'inactive', true),
    (true, 'withdrawn', false),
    (true, 'withdrawalPending', false),
    (true, 'applied', false),
  ]) {
    test(
      'main fleet save preserves consent and pause: $enabled/$state/$firstUse',
      () async {
        final port = OfficialPrivacyFixture()
          ..publicationState = state
          ..firstUseRequired = firstUse;
        port.settings = port.settings.copyWith(
          publicationEnabled: enabled,
          communities: [_scope('B', fields: 7)],
          roomFields: 5,
        );
        final initial = port.settings.toJson();
        final c = LocalPrivacyController(port);
        addTearDown(c.dispose);
        await c.refresh();
        port.calls.clear();
        c.editOfficialFields(3);
        expect(await c.saveOrganization(null), isTrue);
        expect(port.savedFields, 3);
        expect(port.settings.toJson(), initial);
        expect(
          port.calls.where((a) => a.startsWith('publication.')),
          enabled && state == 'applied' && !firstUse
              ? ['publication.applyPreservingPause']
              : isEmpty,
        );
        if (state != 'applied' || !enabled) {
          expect(c.officialSaveStage, OfficialPrivacySaveStage.localSaved);
        }
      },
    );
  }

  for (final firstSave in [true, false]) {
    test(
      firstSave
          ? 'first organization save grants only A and keeps other draft edits'
          : 'legacy settings without communities save only A and keep B edits',
      () async {
        final initial = firstSave
            ? null
            : LocalPrivacySettings.editorDefaults.copyWith(
                publicationEnabled: false,
                roomFields: 0,
                roomAllMembersCanView: false,
                hideLowConfidenceLocation: true,
              );
        final port = _StoredPrivacy(initial);
        final c = LocalPrivacyController(port);
        addTearDown(c.dispose);
        await c.refresh();
        expect(c.hasSaved, !firstSave);
        final effective = initial ?? _unshared();
        final choiceA = _scope(
          'A',
          fields: 1,
        ).copyWith(allMembersCanView: true);
        final edited = c.draft!.copyWith(
          publicationEnabled: !c.draft!.publicationEnabled,
          fleetFields: 63,
          fleetAdministratorsCanView: !effective.fleetAdministratorsCanView,
          fleetAllMembersCanView: !effective.fleetAllMembersCanView,
          roomFields: effective.roomFields == 0 ? 63 : 0,
          roomAllMembersCanView: !effective.roomAllMembersCanView,
          hideLowConfidenceLocation: false,
          communities: [choiceA, _scope('B', fields: 2)],
        );
        c.edit(edited);

        expect(await c.saveOrganization('A'), isTrue);
        expect(
          port.settings!.toJson(),
          effective
              .copyWith(
                communities: [
                  if (!firstSave)
                    _scope('B').copyWith(
                      administratorsCanView:
                          effective.fleetAdministratorsCanView,
                      allMembersCanView: effective.fleetAllMembersCanView,
                    ),
                  choiceA,
                ],
              )
              .toJson(),
          reason: 'Only A changes; all other values retain their effective baseline',
        );
        expect(port.settings!.roomFields, effective.roomFields);
        expect(
          port.settings!.roomAllMembersCanView,
          effective.roomAllMembersCanView,
        );
        expect(port.settings!.fleetFields, effective.fleetFields);
        expect(
          port.settings!.fleetAllMembersCanView,
          effective.fleetAllMembersCanView,
        );
        expect(
          port.settings!.communities!
              .where((scope) => scope.code != 'A')
              .map((scope) => scope.toJson()),
          (firstSave
                  ? <CommunitySharingScope>[]
                  : [
                      _scope('B').copyWith(
                        administratorsCanView:
                            effective.fleetAdministratorsCanView,
                        allMembersCanView: effective.fleetAllMembersCanView,
                      ),
                    ])
              .map((scope) => scope.toJson()),
          reason: 'Other organizations remain unshared, including draft B',
        );
        expect(c.savedSettings!.toJson(), port.settings!.toJson());
        expect(
          c.draft!.copyWith(communities: []).toJson(),
          (firstSave
                  ? edited.copyWith(
                      fleetAllMembersCanView: false,
                      roomAllMembersCanView: false,
                    )
                  : edited)
              .copyWith(communities: [])
              .toJson(),
          reason:
              'Unchanged first-use suggestions are replaced by saved values',
        );
        expect(
          c.draft!.communities!.map((scope) => scope.toJson()),
          unorderedEquals(edited.communities!.map((scope) => scope.toJson())),
        );
        expect(_in(c.draft!, 'B').fields, 2, reason: 'Still pending');
        expect(c.organizationDirty('A'), isFalse);
        expect(c.organizationDirty('B'), isTrue);
        expect(c.dirty, isTrue);
      },
    );
  }

  test(
    'legacy B keeps its nonzero fields and audience when A is saved',
    () async {
      final initial = LocalPrivacySettings(
        publicationEnabled: true,
        fleetFields: 13,
        fleetAdministratorsCanView: true,
        fleetAllMembersCanView: false,
        fleetVisibilityGroupIds: ['group-b'],
        roomFields: 5,
        roomAllMembersCanView: true,
      );
      final port = _StoredPrivacy(initial);
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await c.refresh();
      c.enableCommunityChoices();
      final choiceA = _scope('A', fields: 2).copyWith(allMembersCanView: true);
      c.editCommunity(choiceA);
      c.editCommunity(_scope('B', fields: 1));
      expect(await c.saveOrganization('A'), isTrue);
      final b = _in(port.settings!, 'B');
      expect(b.fields, 13);
      expect(b.joinedAt, _joined);
      expect(b.administratorsCanView, isTrue);
      expect(b.allMembersCanView, isFalse);
      expect(b.visibilityGroupIds, ['group-b']);
      expect(_in(port.settings!, 'A').toJson(), choiceA.toJson());
      expect(
        port.settings!.copyWith(communities: []).toJson(),
        initial.copyWith(communities: []).toJson(),
      );
      expect(
        _in(c.draft!, 'B').fields,
        1,
        reason: 'Unrelated draft stays pending',
      );
      expect(port.actions.where((a) => a != 'status'), [
        'applyPreservingPause',
      ]);
    },
  );

  for (final (enabled, state, firstUse) in [
    (false, 'inactive', true),
    (true, 'inactive', true),
    (true, 'withdrawn', false),
    (true, 'withdrawalPending', false),
    (false, 'applied', false),
    (true, 'applied', false),
  ]) {
    test(
      'community save preserves consent and pause: $enabled/$state/$firstUse',
      () async {
        final initial = _unshared().copyWith(
          publicationEnabled: enabled,
          roomFields: 5,
          roomAllMembersCanView: true,
          communities: [_scope('A'), _scope('B', fields: 7)],
        );
        final port = _StoredPrivacy(initial)
          ..publicationState = state
          ..firstUseRequired = firstUse;
        final c = LocalPrivacyController(port);
        addTearDown(c.dispose);
        await c.refresh();
        final a = _scope('A', fields: 3);
        c.edit(
          c.draft!.copyWith(
            publicationEnabled: !enabled,
            roomFields: 0,
            communities: [a, _scope('B', fields: 1)],
          ),
        );
        expect(await c.saveOrganization('A'), isTrue);
        expect(
          port.settings!.toJson(),
          initial.copyWith(communities: [_scope('B', fields: 7), a]).toJson(),
        );
        expect(
          port.actions.where((a) => a != 'status'),
          enabled && state == 'applied' && !firstUse
              ? ['applyPreservingPause']
              : isEmpty,
        );
        expect(port.publicationState, state);
        expect(port.firstUseRequired, firstUse);
      },
    );
  }

  test('saving one organization writes only that organization and keeps other edits', () async {
    final (port, c) = await _open();
    _editBoth(c);
    expect(await c.saveOrganization('A'), isTrue);
    expect(_in(port.settings, 'A').fields, 1);
    expect(_in(port.settings, 'B').fields, 0, reason: 'Not this page');
    expect(port.settings.roomFields, 0, reason: 'Not this page');
    expect(_in(c.draft!, 'A').fields, 1);
    expect(_in(c.draft!, 'B').fields, 2, reason: 'Still pending');
    expect(c.draft!.roomFields, 15, reason: 'Still pending');
    expect(c.organizationDirty('A'), isFalse);
    expect(c.organizationDirty('B'), isTrue);
    expect(c.dirty, isTrue);
  });

  test(
    'what was saved reaches publication despite other pending edits',
    () async {
      final (port, c) = await _open();
      _editBoth(c);
      final before = port.applies;
      await c.saveOrganization('A');
      expect(port.applies, before + 1);
    },
  );

  test('the whole page save still writes everything', () async {
    final (port, c) = await _open();
    _editBoth(c);
    expect(await c.save(), isTrue);
    expect(_in(port.settings, 'B').fields, 2);
    expect(port.settings.roomFields, 15);
    expect(c.dirty, isFalse);
  });

  test('discarding one organization leaves other edits', () async {
    final (_, c) = await _open();
    _editBoth(c);
    c.discardOrganization('A');
    expect(_in(c.draft!, 'A').fields, 0);
    expect(_in(c.draft!, 'B').fields, 2);
    expect(c.draft!.roomFields, 15);
  });

  test('another organization\'s edit does not enable this page', () async {
    final (_, c) = await _open();
    c.edit(
      c.draft!.copyWith(communities: [_scope('A'), _scope('B', fields: 2)]),
    );
    expect(c.organizationDirty('A'), isFalse);
    expect(c.canSaveOrganization('A'), isFalse);
    expect(c.canSaveOrganization('B'), isTrue);
  });

  test('an organization page leaves a pending main fleet edit alone', () async {
    final (port, c) = await _open();
    c.editOfficialFields(1);
    _editBoth(c);
    expect(await c.saveOrganization('A'), isTrue);
    expect(port.savedFields, 0, reason: 'Not this page');
    expect(c.officialDirty, isTrue);
  });

  test('the main fleet page saves only the main fleet', () async {
    final (port, c) = await _open();
    _editBoth(c);
    c.editOfficialFields(1);
    expect(await c.saveOrganization(null), isTrue);
    expect(port.savedFields, 1);
    expect(_in(port.settings, 'A').fields, 0, reason: 'Not this page');
    expect(port.settings.roomFields, 0, reason: 'Not this page');
    expect(c.draft!.roomFields, 15, reason: 'Still pending');
    expect(_in(c.draft!, 'B').fields, 2, reason: 'Still pending');
  });

  test(
    'unchanged main fleet cannot save an unsaved cross-scope draft',
    () async {
      final port = _UnsavedOfficialPrivacy();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await c.refresh();
      expect(c.hasSaved, isFalse);
      expect(c.officialScope, isNotNull);
      expect(c.officialScope!.choiceRequired, isTrue);
      expect(c.officialDraftFields, 15, reason: 'A suggestion is not an edit');
      c.edit(
        c.draft!.copyWith(
          publicationEnabled: false,
          fleetFields: 63,
          roomFields: 63,
          hideLowConfidenceLocation: false,
          communities: [_scope('A', fields: 1), _scope('B', fields: 2)],
        ),
      );
      final edited = c.draft!.toJson();
      expect(c.dirty, isTrue);
      expect(c.officialDirty, isFalse);
      expect(c.canSaveOrganization(null), isFalse);
      expect(await c.saveOrganization(null), isFalse);
      expect(port.revision, 0);
      expect(port.settings, isNull);
      expect(port.officialSaves, 0);
      expect(c.draft!.toJson(), edited);
      expect(c.hasSaved, isFalse);
    },
  );

  test('discarding the main fleet leaves other edits', () async {
    final (_, c) = await _open();
    _editBoth(c);
    c.editOfficialFields(1);
    c.discardOrganization(null);
    expect(c.officialDirty, isFalse);
    expect(c.draft!.roomFields, 15);
  });
}
