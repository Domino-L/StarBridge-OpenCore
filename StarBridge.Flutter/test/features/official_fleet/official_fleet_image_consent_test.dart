import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/common/organization_hangar_sharing.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_hangar_sharing.dart';

import 'official_fleet_hangar_sharing_test.dart' as sharing;
import 'official_fleet_image_test_support.dart';
import '../friends/social_layout_test.dart' show loadFonts;

Map<String, Object?> ownerDraft({bool old = false}) => {
  ...sharing.draft(total: 2, old: old),
  'imageFeatures': imageFeatures,
  'imageCount': 2,
  'canClearImages': true,
};

void main() {
  setUpAll(loadFonts);
  test('retained terminal page permits omitted null next but incomplete pages cannot', () {
    final terminal = sharing.page(total: 2)..remove('next');
    final parsed = OrganizationSharingPage.parse(terminal);
    expect(parsed.next, isNull);
    expect(parsed.totalOptions, 2);
    expect(parsed.options.length, 2);
    final partial = sharing.page(total: 150)..remove('next');
    expect(() => OrganizationSharingPage.parse(partial), throwsFormatException);
    final malformed = sharing.page(total: 0)..remove('totalOptions');
    expect(
      () => OrganizationSharingPage.parse(malformed),
      throwsFormatException,
    );
  });
  test(
    'positive consent requires complete features and current callable set',
    () {
      for (var bits = 0; bits < 16; bits++) {
        final features = <String, Object?>{'protocolVersion': 1};
        for (var i = 0; i < 4; i++) {
          features[['read', 'upload', 'report', 'reduce'][i]] =
              bits & (1 << i) != 0;
        }
        final draft = OrganizationSharingDraft.parseOfficial({
          ...ownerDraft(),
          'imageFeatures': features,
          'canClearImages': features['reduce'],
        }, imageProtocolSupported: true);
        expect(draft.allowImages, bits == 15);
        expect(draft.canClearImages, features['reduce']);
      }
      final oldHost = OrganizationSharingDraft.parseOfficial(ownerDraft());
      expect(oldHost.allowImages, isFalse);
      expect(oldHost.canClearImages, isFalse);
      expect(
        () => OrganizationSharingDraft.parseOfficial({
          ...ownerDraft(),
          'imageCount': -1,
        }),
        throwsFormatException,
      );
      expect(
        () => OrganizationSharingDraft.parseOfficial({
          ...ownerDraft(),
          'imageCount': 0,
        }),
        throwsFormatException,
      );
    },
  );
  for (final missing in [null, ...imageNames]) {
    test(
      'actual adapter includes images only with all capabilities ($missing)',
      () async {
        final wire = ImageWire(
          capabilities: [
            'officialFleet.hangarSharing',
            'officialFleet.hangarSharingPage',
            'officialFleet.saveHangarSharing',
            ...imageNames.where((name) => name != missing),
          ],
        );
        final adapter = BridgeOfficialFleetHangarSharing(wire.session);
        addTearDown(() async {
          await adapter.close();
          await wire.close();
        });
        wire.respond = (r) => r.name == 'officialFleet.hangarSharing'
            ? ownerDraft()
            : {'schemaVersion': 1, 'status': 'accepted'};
        final draft = await adapter.read(source);
        expect(draft.allowImages, missing == null);
        final result = await adapter.save(
          draft.editRef,
          source,
          'organizationPool',
          draft.selectedRefs,
          includeImages: true,
        );
        expect(result.status, missing == null ? 'accepted' : 'rejected');
        final writes = wire.requests.where(
          (r) => r.name == 'officialFleet.saveHangarSharing',
        );
        if (missing == null) {
          expect(writes.single.payload['includeImages'], true);
        } else {
          expect(writes, isEmpty);
        }
      },
    );
  }
  test('clear old unavailable scope uses strict union without inventory or strategy', () async {
    final wire = ImageWire(
      capabilities: [
        'officialFleet.hangarSharing',
        'officialFleet.hangarSharingPage',
        'officialFleet.saveHangarSharing',
        ...imageNames,
      ],
    );
    final adapter = BridgeOfficialFleetHangarSharing(wire.session);
    addTearDown(() async {
      await adapter.close();
      await wire.close();
    });
    wire.respond = (r) => r.name == 'officialFleet.hangarSharing'
        ? ownerDraft(old: true)
        : {'schemaVersion': 1, 'status': 'unknown', 'error': 'outcomeUnknown'};
    final draft = await adapter.read(null);
    expect(draft.canPublish, isFalse);
    expect(draft.canClearImages, isTrue);
    expect(
      (await adapter.clearImages(draft.editRef, draft.sourceRef!)).status,
      'unknown',
    );
    expect(
      (await adapter.clearImages(draft.editRef, draft.sourceRef!)).status,
      'rejected',
    );
    final writes = wire.requests.where(
      (r) => r.name == 'officialFleet.saveHangarSharing',
    );
    expect(writes.single.payload, {
      'schemaVersion': 1,
      'sourceRef': source,
      'editRef': draft.editRef,
      'kind': 'clearImages',
    });
    expect(
      wire.requests.any((r) => r.name == 'officialFleet.hangarSharingPage'),
      isFalse,
    );
  });
  testWidgets(
    'shared editor defaults and resets image checkbox without clearing ship selection',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Editor();
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final checkbox = find.byKey(const Key('hangar-share-images'));
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(
        find.ancestor(of: checkbox, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      await tester.tap(find.byKey(const Key('hangar-sharing-strategy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not shared'));
      await tester.pumpAndSettle();
      expect(checkbox, findsNothing);
      await tester.tap(find.byKey(const Key('hangar-sharing-strategy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share selected ships with the fleet'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(find.byKey(const Key('hangar-sharing-save')));
      await tester.pumpAndSettle();
      expect(port.includeImages, isFalse);
      expect(port.selected, [ref(1), ref(2)]);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(checkbox, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'clear images remains available for old scope and never calls sharing save',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Editor()..old = true;
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('hangar-share-images')), findsNothing);
      await tester.tap(find.byKey(const Key('hangar-sharing-clear-images')));
      await tester.pumpAndSettle();
      expect(port.clears, 1);
      expect(port.saves, 0);
      expect(port.selected, isNull);
      expect(find.byType(CommunityHangarSharingDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in const [
    Locale('en'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
  ]) {
    testWidgets(
      'image controls fit420 at200percent ${locale.toLanguageTag()}',
      (tester) async {
        tester.view.physicalSize = const Size(420, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = _Editor();
        addTearDown(port.close);
        await tester.pumpWidget(_open(port, locale: locale, scale: 2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('hangar-share-images')), findsOneWidget);
        expect(
          find.byKey(const Key('hangar-sharing-clear-images')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Widget _open(
  _Editor port, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => sharing.host(
  Builder(
    builder: (context) => TextButton(
      onPressed: () => showStarBridgeDialog<bool>(
        context,
        builder: (_) => CommunityHangarSharingDialog.editor(
          editor: port,
          sourceRef: source,
        ),
      ),
      child: const Text('Open'),
    ),
  ),
  locale: locale,
  scale: scale,
);

class _Editor
    implements
        OrganizationHangarSharingPort,
        OrganizationHangarImageConsentPort {
  final changes = StreamController<void>.broadcast();
  bool old = false, includeImages = false;
  List<String>? selected;
  int saves = 0, clears = 0;
  @override
  bool get available => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OrganizationSharingDraft> read(
    String? sourceRef, {
    String? scopeRef,
  }) async => OrganizationSharingDraft.parseOfficial(
    ownerDraft(old: old),
    imageProtocolSupported: true,
  );
  @override
  Future<OrganizationSharingPage> page(
    String editRef,
    String sourceRef,
    int offset,
  ) async =>
      OrganizationSharingPage.parse(sharing.page(total: 2, offset: offset));
  @override
  Future<CommunityHangarSharingOutcome> save(
    String editRef,
    String? sourceRef,
    String? strategy,
    List<String> selectedRefs, {
    bool includeImages = false,
  }) async {
    saves++;
    selected = List.of(selectedRefs);
    this.includeImages = includeImages;
    return const CommunityHangarSharingOutcome('accepted');
  }

  @override
  Future<CommunityHangarSharingOutcome> clearImages(
    String editRef,
    String sourceRef,
  ) async {
    clears++;
    return const CommunityHangarSharingOutcome('accepted');
  }

  @override
  Future<void> close() => changes.close();
}
