import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/connection_mode_port.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_hangar_sharing.dart';
import 'package:starbridge_flutter/features/common/organization_communication.dart';
import 'package:starbridge_flutter/features/common/organization_communication_port.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_hangar_sharing_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_panel.dart';
import 'package:starbridge_flutter/features/official_fleet/bridge_official_fleet_hangar_sharing.dart';
import 'package:starbridge_flutter/features/official_fleet/unavailable_official_fleet_shared_ships.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_connection.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show loadFonts;

String ref(int i) => i.toRadixString(16).padLeft(32, '0');
Map<String, Object?> page({
  int offset = 0,
  int total = 150,
  bool missing = false,
}) => {
  'schemaVersion': 1,
  'editRef': ref(30000),
  'offset': offset,
  'totalOptions': total,
  'next': offset + 100 < total ? offset + 100 : null,
  'options': [
    for (var i = offset; i < total && i < offset + 100; i++)
      {
        'shipRef': ref(i + 1),
        'name': missing ? null : 'Ship ${i + 1}',
        'missing': missing,
        'grantable': !missing,
      },
  ],
};
Map<String, Object?> draft({
  int total = 150,
  bool partial = false,
  bool missing = false,
  bool old = false,
  String strategy = 'organizationPool',
}) => {
  'schemaVersion': 1,
  'editRef': ref(30000),
  'sourceRef': 'officialFleet:7',
  'state': old ? 'unavailable' : 'available',
  'strategy': strategy,
  'inventoryState': partial
      ? 'partial'
      : missing
      ? 'missing'
      : 'complete',
  'canGrant': !old,
  'canPublish': !old && !partial && !missing,
  'canReduce': true,
  'selectionKnown': !old,
  'selectedCount': strategy == 'organizationPool' ? total : 0,
  'maximumSelected': 10000,
  'selectedRefs': [
    if (!old && strategy == 'organizationPool')
      for (var i = 0; i < total; i++) ref(i + 1),
  ],
  'scopes': [
    {'scopeRef': ref(31000), 'name': 'ASTER', 'isCurrent': !old},
  ],
  'scopeRef': ref(31000),
  'page': page(total: old ? 0 : total, missing: missing),
};

class _Port implements OrganizationHangarSharingPort {
  Map<String, Object?> value = draft();
  final changes = StreamController<void>.broadcast(sync: true);
  int reads = 0, writes = 0;
  final pages = <int>[];
  List<String>? saved;
  String? strategy;
  String status = 'accepted';
  @override
  bool get available => true;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<OrganizationSharingDraft> read(
    String? sourceRef, {
    String? scopeRef,
  }) async {
    reads++;
    return OrganizationSharingDraft.parseOfficial(value);
  }

  @override
  Future<OrganizationSharingPage> page(
    String editRef,
    String sourceRef,
    int offset,
  ) async {
    pages.add(offset);
    return OrganizationSharingPage.parse((pageData(offset)));
  }

  Map<String, Object?> pageData(int offset) => _pageData(offset);
  Map<String, Object?> _pageData(int offset) {
    final count = (value['page'] as Map)['totalOptions'] as int;
    return <String, Object?>{
      'schemaVersion': 1,
      'editRef': ref(30000),
      'offset': offset,
      'totalOptions': count,
      'next': offset + 100 < count ? offset + 100 : null,
      'options': [
        for (var i = offset; i < count && i < offset + 100; i++)
          {
            'shipRef': ref(i + 1),
            'name': 'Ship ${i + 1}',
            'missing': false,
            'grantable': true,
          },
      ],
    };
  }

  @override
  Future<CommunityHangarSharingOutcome> save(
    String editRef,
    String? sourceRef,
    String? strategy,
    List<String> selectedRefs, {
    bool includeImages = false,
  }) async {
    writes++;
    saved = List.of(selectedRefs);
    this.strategy = strategy;
    return CommunityHangarSharingOutcome(status);
  }

  @override
  Future<void> close() => changes.close();
}

Widget host(
  Widget child, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: Scaffold(body: child),
);
Widget _open(
  _Port port, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) => host(
  Builder(
    builder: (context) => TextButton(
      onPressed: () => showDialog<bool>(
        context: context,
        builder: (_) => CommunityHangarSharingDialog.editor(
          editor: port,
          sourceRef: 'officialFleet:7',
        ),
      ),
      child: const Text('Open'),
    ),
  ),
  locale: locale,
  scale: scale,
);

class _Harness {
  _Harness({ConnectionModeControl? mode}) {
    final pair = InMemoryBridgeConnection.createPair();
    wire = pair.host;
    session = BridgeClientSession(
      connection: pair.client,
      sessionGeneration: 1,
      requestTimeout: const Duration(seconds: 1),
    );
    session.acceptHostCapabilities(const [
      'officialFleet.hangarSharing',
      'officialFleet.hangarSharingPage',
      'officialFleet.saveHangarSharing',
    ]);
    adapter = BridgeOfficialFleetHangarSharing(session, connectionMode: mode);
    sub = wire.incoming.listen((request) async {
      requests.add(request);
      final payload = request.name == 'account.getCurrent'
          ? <String, Object?>{'schemaVersion': 1, 'state': state}
          : request.name == 'officialFleet.hangarSharing'
          ? draft(total: 10000)
          : request.name == 'officialFleet.hangarSharingPage'
          ? page(offset: request.payload['offset'] as int, total: 10000)
          : <String, Object?>{'schemaVersion': 1, 'status': result};
      await wire.send(
        BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'response',
          name: request.name,
          correlationId: request.correlationId,
          sessionGeneration: request.sessionGeneration,
          accountContext: context,
          payload: payload,
          status: 'ok',
        ),
      );
    });
  }
  late final BridgeConnection wire;
  late final BridgeClientSession session;
  late final BridgeOfficialFleetHangarSharing adapter;
  late final StreamSubscription<BridgeEnvelope> sub;
  final requests = <BridgeEnvelope>[];
  BridgeAccountContext context = const BridgeAccountContext(
    environment: 'test',
    authority: 'scm-test',
    subject: 'synthetic-owner',
  );
  String state = 'signedIn', result = 'unknown';
  Future<void> close() async {
    await adapter.close();
    await session.close();
    await sub.cancel();
    await wire.close();
  }
}

void main() {
  setUpAll(loadFonts);
  test('strict instance projection retains10000 opaque selections and bounded pages', () {
    final value = draft(total: 10000);
    final parsed = OrganizationSharingDraft.parseOfficial(value);
    expect(parsed.selectedRefs.length, 10000);
    expect(parsed.page.options.length, 100);
    expect(utf8.encode(jsonEncode(value)).length, lessThan(768 * 1024));
    for (final patch in <Map<String, Object?>>[
      {'maximumSelected': 64},
      {
        'selectedRefs': [ref(1), ref(1)],
      },
      {'membershipEpoch': 'private'},
      {'selectionKnown': false},
      {'canPublish': true, 'inventoryState': 'partial'},
      {'strategy': 'operationOnly'},
    ]) {
      expect(
        () => OrganizationSharingDraft.parseOfficial({...value, ...patch}),
        throwsFormatException,
      );
    }
  });
  test('a draft through the real Bridge omits its null values and still parses', () {
    // BridgeProtocol.JsonOptions: WhenWritingNull. A fixture holding the null
    // key hid this from every earlier test (OS-8, real log draft-fields-invalid).
    Map<String, Object?> bridged(Map<String, Object?> value) => {
      for (final entry in value.entries)
        if (entry.value != null) entry.key: entry.value,
    };
    final open = draft(strategy: 'notShared');
    final noStrategy = bridged({...open, 'strategy': null});
    expect(noStrategy.containsKey('strategy'), isFalse);
    expect(OrganizationSharingDraft.parseOfficial(noStrategy).strategy, isNull);
    final noTarget = bridged({
      ...open,
      'strategy': null,
      'sourceRef': null,
      'scopeRef': null,
      'canGrant': false,
      'canPublish': false,
      'canReduce': false,
    });
    final parsed = OrganizationSharingDraft.parseOfficial(noTarget);
    expect(parsed.sourceRef, isNull);
    expect(parsed.canGrant, isFalse);
    // Absent means null, so a draft that can act still needs its target.
    final actsWithoutTarget = bridged({...open, 'sourceRef': null});
    expect(
      () => OrganizationSharingDraft.parseOfficial(actsWithoutTarget),
      throwsFormatException,
    );
    for (final required in ['editRef', 'state', 'inventoryState', 'page']) {
      expect(
        () => OrganizationSharingDraft.parseOfficial({...draft()}..remove(required)),
        throwsFormatException,
        reason: required,
      );
    }
  });
  test('strict page rejects duplicate, wrong missing metadata and unbounded options', () {
    final value = page();
    final rows = value['options'] as List;
    for (final patch in <Map<String, Object?>>[
      {
        'options': [rows.first, rows.first],
      },
      {'totalOptions': 20001},
      {'next': 101},
      {
        'options': [
          ...rows.take(99),
          {
            ...(rows.last as Map<String, Object?>),
            'missing': true,
            'grantable': true,
          },
        ],
      },
    ]) {
      expect(
        () => OrganizationSharingPage.parse({...value, ...patch}),
        throwsFormatException,
      );
    }
  });
  test('real Bridge frame carries10000 selections; unknown write consumes editor and never replays', () async {
    final h = _Harness();
    addTearDown(h.close);
    final value = await h.adapter.read('officialFleet:7');
    expect(value.selectedRefs.length, 10000);
    final result = await h.adapter.save(
      value.editRef,
      value.sourceRef,
      'organizationPool',
      value.selectedRefs,
    );
    expect(result.status, 'unknown');
    final repeat = await h.adapter.save(
      value.editRef,
      value.sourceRef,
      'notShared',
      [],
    );
    expect(repeat.status, 'rejected');
    expect(
      h.requests
          .where((r) => r.name == 'officialFleet.saveHangarSharing')
          .length,
      1,
    );
    expect(
      h.requests
          .singleWhere((r) => r.name == 'officialFleet.saveHangarSharing')
          .accountContext
          ?.subject,
      'synthetic-owner',
    );
  });
  test(
    'Bridge refuses old account, wrong source and legacy sign-in before write',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      var value = await h.adapter.read('officialFleet:7');
      expect(
        (await h.adapter.save(
          value.editRef,
          'officialFleet:8',
          'notShared',
          [],
        )).status,
        'rejected',
      );
      h.context = const BridgeAccountContext(
        environment: 'test',
        authority: 'scm-test',
        subject: 'other-owner',
      );
      expect(
        (await h.adapter.save(
          value.editRef,
          value.sourceRef,
          'notShared',
          [],
        )).status,
        'rejected',
      );
      expect(
        h.requests.where((r) => r.name == 'officialFleet.saveHangarSharing'),
        isEmpty,
      );
      h.state = 'legacySignedIn';
      await expectLater(h.adapter.read('officialFleet:7'), throwsA(anything));
    },
  );
  test(
    'account event retires cached editor and pending presentation',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final value = await h.adapter.read('officialFleet:7');
      final change = h.adapter.invalidations.first;
      await h.wire.send(
        const BridgeEnvelope(
          protocolVersion: 1,
          messageType: 'event',
          name: 'account.changed',
          sessionGeneration: 1,
          sequence: 1,
          payload: {'schemaVersion': 1},
        ),
      );
      await change;
      expect(
        (await h.adapter.save(
          value.editRef,
          value.sourceRef,
          'notShared',
          [],
        )).status,
        'rejected',
      );
    },
  );
  testWidgets(
    'same dialog virtualizes10000 refs and keeps changes across100-option pages',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port()..value = draft(total: 10000);
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        find.byType(StarBridgeCheckboxTile).evaluate().length,
        lessThan(20),
      );
      await tester.tap(find.text('Ship 1'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-next')));
      await tester.pumpAndSettle();
      expect(port.pages, [100]);
      expect(find.text('Ship 101'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-save')));
      await tester.pumpAndSettle();
      expect(port.saved!.length, 9999);
      expect(port.saved, isNot(contains(ref(1))));
      expect(port.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'partial inventory permits removing missing selection; never adding a grant',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port()
        ..value = draft(total: 2, partial: true, missing: true);
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is StarBridgeCheckboxTile &&
              w.controlKey == ValueKey('hangar-share-target-${ref(1)}'),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-save')));
      await tester.pumpAndSettle();
      expect(port.saved, [ref(2)]);
      expect(port.strategy, 'organizationPool');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'old scope unavailable selection has real count and allows whole withdrawal',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port()..value = draft(total: 7, old: true);
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Previously selected ships: 7'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-strategy')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not shared'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-save')));
      await tester.pumpAndSettle();
      expect(port.strategy, 'notShared');
      expect(port.saved, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown dialog write requires explicit fresh read and invalidation removes editor',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port()..status = 'unknown';
      addTearDown(port.close);
      await tester.pumpWidget(_open(port));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-save')));
      await tester.pumpAndSettle();
      expect(port.writes, 1);
      expect(find.byKey(const ValueKey('hangar-sharing-save')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('hangar-sharing-refresh')));
      await tester.pumpAndSettle();
      expect(port.reads, 2);
      port.changes.add(null);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('hangar-sharing-save')), findsNothing);
    },
  );
  testWidgets(
    'shared Panel keeps real unavailable pool distinct while own editor opens',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final port = _Port();
      addTearDown(port.close);
      await tester.pumpWidget(
        host(
          CommunityShipsPanel(
            port: const UnavailableOfficialFleetSharedShips(),
            targetRef: 'officialFleet:7',
            name: 'ASTER',
            onBack: () {},
            ownerTargetFactory: null,
            includeSocialActions: false,
            hangarSharingPort: port,
            hangarSharingSourceRef: 'officialFleet:7',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('community-ships-sharing')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('community-ships-sharing')));
      await tester.pumpAndSettle();
      expect(find.byType(CommunityHangarSharingDialog), findsOneWidget);
      expect(port.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  test('verified workspace ref is independent of chat and disappears on retained/reset context', () async {
    final model = OrganizationCommunication((_) => _ContextPort());
    addTearDown(model.dispose);
    expect(model.verifiedWorkspaceTargetRef, isNull);
    await model.open('officialFleet:7');
    expect(model.chatAvailable, isFalse);
    expect(model.verifiedWorkspaceTargetRef, ref(60000));
    model.retainReadOnly();
    expect(model.verifiedWorkspaceTargetRef, isNull);
    await model.refresh('officialFleet:7');
    expect(model.verifiedWorkspaceTargetRef, ref(60000));
    model.reset();
    expect(model.verifiedWorkspaceTargetRef, isNull);
  });
  test(
    'explicit offline mode blocks new reads and retires old editors',
    () async {
      final mode = _Mode();
      final h = _Harness(mode: mode);
      addTearDown(h.close);
      final value = await h.adapter.read('officialFleet:7');
      mode.online = false;
      mode.notifyListeners();
      final before = h.requests.length;
      await expectLater(h.adapter.read('officialFleet:7'), throwsA(anything));
      expect(h.requests.length, before);
      mode.online = true;
      mode.notifyListeners();
      expect(
        (await h.adapter.save(
          value.editRef,
          value.sourceRef,
          'notShared',
          [],
        )).status,
        'rejected',
      );
      expect(
        h.requests.where((r) => r.name == 'officialFleet.saveHangarSharing'),
        isEmpty,
      );
    },
  );
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    testWidgets(
      'official shared editor fits420 at200percent ${locale.toLanguageTag()}',
      (tester) async {
        tester.view.physicalSize = const Size(420, 840);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final port = _Port()..value = draft(total: 2, partial: true);
        addTearDown(port.close);
        await tester.pumpWidget(_open(port, locale: locale, scale: 2));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.byType(CommunityHangarSharingDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Mode extends ChangeNotifier implements ConnectionModeControl {
  bool online = true;
  @override
  ConnectionModeSnapshot get snapshot => ConnectionModeSnapshot(
    scope: 1,
    revision: online ? 1 : 2,
    state: online ? ConnectionModeState.online : ConnectionModeState.offline,
  );
  @override
  bool get busy => false;
  @override
  bool get failed => false;
  @override
  bool get allowsOnlineTraffic => online;
  @override
  bool get canEnterOffline => online;
  @override
  Future<bool> enterOffline() async {
    online = false;
    notifyListeners();
    return true;
  }
}

class _ContextPort extends Fake implements OrganizationCommunicationPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get chatAvailable => false;
  @override
  bool get announcementsAvailable => false;
  @override
  Future<OrganizationCommunicationContext> open() async =>
      OrganizationCommunicationContext(ref(60000), 'ASTER');
  @override
  Future<void> close() async {}
}
