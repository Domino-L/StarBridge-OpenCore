import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/common/organization_governance_port.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_management.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_workspace.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_writer.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_rank_settings.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_audit_settings.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_role_settings.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_role_editor.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_role_dialog.dart';

import '../communities/bridge_communities_test.dart' show CommunityHarness;

const source = 'officialFleet:7';
final target = 'a' * 64;
GovernanceRow sample(String name) => jsonDecode(
  File('test/fixtures/official_fleet_governance/$name.json').readAsStringSync(),
) as GovernanceRow;
Object? _withoutNulls(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.value != null)
            entry.key as String: _withoutNulls(entry.value),
      }
    : value is List
    ? value.map(_withoutNulls).toList()
    : value;
GovernanceRow memberPage() => {
  ...sample('cxgov-member-relay')..remove('targetSubject'),
  'targetRef': target,
};
GovernanceRow templates({bool closed = false}) => {
  ..._withoutNulls(sample('cxgov-templates-legacy')) as GovernanceRow,
  'roles': [
    {
      'roleRef': '2' * 32,
      'roleKey': 'rally-lead',
      'permissionVersion': 1,
      'metadataRevision': 1,
      'enabled': true,
      'metadata': {
        'displayName': '召集员',
        'description': '',
        'color': '#123456',
        'sortOrder': 0,
      },
      'permissions': [
        {'capability': 'audit.view', 'canUse': true, 'canDelegate': false},
      ],
    },
  ],
  'creationCapabilities': [
    for (final key in governancePermissions)
      {
        'capability': key,
        'state': closed && key == 'rally.manage' ? 'unavailable' : 'allowed',
        'reason': closed && key == 'rally.manage'
            ? 'rankPolicyWritesDisabled'
            : 'explicitRootDelegation',
      },
  ],
};
GovernanceRow member({bool self = false, int? rank}) => {
  'memberRef': self ? 'b' * 64 : target,
  'callsign': self ? '本人' : '成员甲',
  if (self) 'isSelf': true,
  'officialRankValue': ?rank,
};

class ManagementFake implements OfficialFleetGovernanceManagementPort {
  final changes = StreamController<void>.broadcast(sync: true);
  Set<String>? commands;
  final reads = <(String, GovernanceRow)>[];
  final writes = <(String, GovernanceRow)>[];
  final outcomes = <String>[];
  Future<String> Function(String, GovernanceRow)? onWrite;
  final pages = <String, GovernanceRow>{
    'readRankPolicy': sample('cxgov-ranks'),
    'readMemberRoles': memberPage(),
    'readGovernanceAudit': sample('cxgov-audit'),
    'readRoleTemplates': templates(),
    'getMembers': {
      'schemaVersion': 1,
      'sourceRef': source,
      'members': [member(), member(self: true)],
      'totalPages': 1,
    },
  };
  Completer<GovernanceRow>? held;
  int inFlight = 0, maximum = 0;
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  bool supports(String command) => commands?.contains(command) ?? true;
  @override
  Future<GovernanceRow> read(
    String command,
    String source, [
    GovernanceRow args = const {},
  ]) async {
    reads.add((command, {...args}));
    if (readError case final error?) throw error;
    if (command == 'readMemberRoles' && held != null) {
      ++inFlight;
      if (inFlight > maximum) maximum = inFlight;
      try {
        return {...await held!.future, 'targetRef': args['targetRef']};
      } finally {
        --inFlight;
      }
    }
    return pages[command]!;
  }

  @override
  Future<String> write(
    String command,
    String source,
    GovernanceRow intent,
  ) async {
    writes.add((command, jsonDecode(jsonEncode(intent)) as GovernanceRow));
    if (onWrite != null) return onWrite!(command, intent);
    return outcomes.isEmpty ? 'accepted' : outcomes.removeAt(0);
  }

  final outcomeQueries = <String>[];
  String templateOutcome = 'accepted';
  Object? readError;
  @override
  Future<String> roleTemplateOutcome(String source, String requestId) async {
    outcomeQueries.add(requestId);
    return templateOutcome;
  }
}

class AuthorityFake
    implements
        OrganizationGovernancePort,
        OfficialFleetGovernanceManagementProvider {
  AuthorityFake(this.management, {this.delegate = false, this.audit = false});
  @override
  final ManagementFake management;
  bool delegate, audit;
  int reads = 0;
  @override
  bool get available => true;
  @override
  bool get canActivate => true;
  @override
  Stream<void> get invalidations => management.invalidations;
  @override
  Future<OrganizationGovernanceContext> read(String source) async {
    ++reads;
    final row = sample('context-never-activated.bridge');
    row['capabilities'] = [
      for (final key in OrganizationGovernanceContext.capabilityKeys)
        {
          'capability': key,
          'state': key == 'audit.view' && audit ? 'allowed' : 'denied',
          'reason': 'notGranted',
        },
    ];
    row['rootAuthority'] = {
      'providerState': 'observed',
      'controls': [
        for (final key in OrganizationGovernanceContext.rootKeys)
          {
            'action': key,
            'state': key == 'delegate' && delegate ? 'allowed' : 'denied',
            'reason': 'notGranted',
          },
      ],
    };
    return OrganizationGovernanceContext.parse(row, source);
  }

  @override
  Future<OrganizationActivationOutcome> setActivation(
    String sourceRef, {
    required bool active,
    required String operationId,
    required int expectedPolicyRevision,
  }) async => const OrganizationActivationOutcome('accepted');
  @override
  Future<void> close() async {}
}

Future<void> pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark),
        const Locale('zh', 'CN'),
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pumpDialog(WidgetTester tester, Widget dialog) async {
  await pump(
    tester,
    Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => dialog,
        ),
        child: const Text('打开'),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'port accepts documented bridge shapes with omitted null keys',
    () async {
      final responses = <String, GovernanceRow>{
        'officialFleet.readRankPolicy': sample('cxgov-ranks'),
        'officialFleet.readMemberRoles': memberPage(),
        'officialFleet.readRoleTemplates': templates(),
        'officialFleet.readGovernanceAudit':
            _withoutNulls(sample('cxgov-audit')) as GovernanceRow,
      };
      final host = CommunityHarness(
        capabilities: responses.keys.toList(),
        responses: responses,
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      for (final name in responses.keys) {
        final command = name.substring('officialFleet.'.length);
        await port.read(
          command,
          source,
          command == 'readMemberRoles'
              ? {'targetRef': target}
              : command == 'readRoleTemplates'
              ? {
                  'include': ['policyV2'],
                }
              : command == 'readGovernanceAudit'
              ? {'offset': 0}
              : {},
        );
      }
      expect(
        host.requests.where((r) => r.name == 'account.getCurrent'),
        hasLength(4),
      );
      expect(
        host.requests.where((r) => r.name.startsWith('officialFleet.')),
        hasLength(4),
      );
    },
  );
  test('old Host sends no request', () async {
    final host = CommunityHarness(capabilities: []);
    addTearDown(host.close);
    final port = BridgeOfficialFleetGovernanceManagement(
      host.adapter,
      const Stream.empty(),
    );
    await expectLater(
      port.read('readRankPolicy', source),
      throwsA(isA<CommunityFailure>()),
    );
    expect(host.requests, isEmpty);
  });
  test(
    'serialized write need not echo sourceRef or null revision fields',
    () async {
      final response = <String, Object?>{
        'schemaVersion': 1,
        'state': 'conflict',
        'operationId': 'op-1',
      };
      final host = CommunityHarness(
        capabilities: ['officialFleet.writeRankPolicy'],
        responses: {'officialFleet.writeRankPolicy': response},
      );
      addTearDown(host.close);
      final port = BridgeOfficialFleetGovernanceManagement(
        host.adapter,
        const Stream.empty(),
      );
      expect(
        await port.write('writeRankPolicy', source, {
          'operationId': 'op-1',
          'expectedPolicyRevision': 12,
          'rows': sample('cxgov-ranks')['rows'],
        }),
        'conflict',
      );
      expect(host.requests.last.payload.containsKey('rank'), isFalse);
      expect(host.requests.last.payload.containsKey('roles'), isFalse);
    },
  );
  test(
    'uncertain write retries identical id revision and nested intent',
    () async {
      final port = ManagementFake()
        ..outcomes.addAll([
          'operationOutcomeUnknown',
          'unavailable',
          'duplicate',
        ]);
      addTearDown(port.changes.close);
      var refreshed = 0;
      final writer = FleetGovernanceWriter(port, source, () async {
        ++refreshed;
      });
      addTearDown(writer.dispose);
      final rows = sample('cxgov-ranks')['rows'] as List;
      await writer.submit('writeRankPolicy', {
        'expectedPolicyRevision': 12,
        'rows': rows,
      });
      (rows.first as Map)['rally'] = true;
      await writer.submit('writeRankPolicy', {
        'expectedPolicyRevision': 99,
        'rows': [],
      });
      await writer.submit('writeRankPolicy', {
        'expectedPolicyRevision': 100,
        'rows': [],
      });
      expect(port.writes[0].$1, port.writes[1].$1);
      expect(port.writes[0].$2, port.writes[1].$2);
      expect(port.writes[1].$2, port.writes[2].$2);
      expect(writer.pending, isNull);
      expect(refreshed, 1);
    },
  );
  test(
    'conflict and notAllowed reread; invalidation retires pending intent',
    () async {
      final port = ManagementFake()
        ..outcomes.addAll([
          'conflict',
          'notAllowed',
          'operationOutcomeUnknown',
        ]);
      addTearDown(port.changes.close);
      var reads = 0;
      final writer = FleetGovernanceWriter(port, source, () async {
        ++reads;
      });
      addTearDown(writer.dispose);
      await writer.submit('writeRankPolicy', {});
      await writer.submit('writeRankPolicy', {});
      expect(reads, 2);
      expect(
        port.writes[0].$2['operationId'],
        isNot(port.writes[1].$2['operationId']),
      );
      await writer.submit('writeRankPolicy', {});
      port.changes.add(null);
      expect(writer.pending, isNull);
      expect(writer.retired, isTrue);
    },
  );
  for (final policy in ['allowed', 'denied', 'closed']) {
    for (final delegate in [true, false]) {
      testWidgets(
        'visibility rank=$policy delegate=$delegate audit=$delegate',
        (tester) async {
          final management = ManagementFake();
          addTearDown(management.changes.close);
          management.pages['readRankPolicy'] = {
            ...sample('cxgov-ranks'),
            'write': {
              'state': policy == 'allowed'
                  ? 'allowed'
                  : policy == 'closed'
                  ? 'unavailable'
                  : 'denied',
              'reason': policy == 'closed'
                  ? 'rankPolicyWritesDisabled'
                  : 'notGranted',
            },
          };
          final authority = AuthorityFake(
            management,
            delegate: delegate,
            audit: delegate,
          );
          await pump(
            tester,
            OfficialFleetGovernanceWorkspace(
              port: authority,
              source: source,
              onAuthorityRead: (_) {},
              builder: (panes, accept, unavailable) => Column(
                children: [
                  TextButton(
                    onPressed: () async => accept(await authority.read(source)),
                    child: const Text('读取'),
                  ),
                  for (final pane in panes) Text(pane.id),
                ],
              ),
            ),
          );
          await tester.tap(find.text('读取'));
          await tester.pumpAndSettle();
          expect(
            find.text('ranks'),
            policy == 'denied' ? findsNothing : findsOneWidget,
          );
          expect(find.text('roles'), delegate ? findsOneWidget : findsNothing);
          expect(find.text('audit'), delegate ? findsOneWidget : findsNothing);
          expect(management.reads.map((r) => r.$1), ['readRankPolicy']);
        },
      );
    }
  }
  testWidgets('old Host hides all three sections without speculative reads', (
    tester,
  ) async {
    final management = ManagementFake()..commands = {};
    addTearDown(management.changes.close);
    final authority = AuthorityFake(management, delegate: true, audit: true);
    await pump(
      tester,
      OfficialFleetGovernanceWorkspace(
        port: authority,
        source: source,
        onAuthorityRead: (_) {},
        builder: (panes, accept, unavailable) => Column(
          children: [
            TextButton(
              onPressed: () async => accept(await authority.read(source)),
              child: const Text('读取'),
            ),
            for (final pane in panes) Text(pane.id),
          ],
        ),
      ),
    );
    await tester.tap(find.text('读取'));
    await tester.pumpAndSettle();
    expect(find.text('ranks'), findsNothing);
    expect(find.text('roles'), findsNothing);
    expect(find.text('audit'), findsNothing);
    expect(management.reads, isEmpty);
  });
  testWidgets(
    'rank table maps stars, saves and discards, root has no checkbox',
    (tester) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      var authorityReads = 0;
      await pump(
        tester,
        OfficialFleetRankSettings(
          port: port,
          source: source,
          initial: sample('cxgov-ranks'),
          onAuthorityRead: () async {
            ++authorityReads;
          },
        ),
      );
      expect(find.text('5★'), findsOneWidget);
      expect(find.text('1★'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('governance-rank-1')),
          matching: find.byType(Checkbox),
        ),
        findsNothing,
      );
      final box = find.byKey(const ValueKey('rank-2-rally'));
      await tester.tap(box);
      await tester.pump();
      await tester.tap(find.byKey(const Key('rank-discard')));
      await tester.pump();
      expect(tester.widget<Checkbox>(box).value, isFalse);
      expect(port.writes, isEmpty);
      await tester.tap(box);
      await tester.pump();
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      expect(port.writes.single.$1, 'writeRankPolicy');
      expect(authorityReads, 1);
      expect(
        (port.writes.single.$2['rows'] as List).first,
        containsPair('rally', true),
      );
      expect(port.reads.single.$1, 'readRankPolicy');
    },
  );
  testWidgets('switch off keeps rank table visible and read-only', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    await pump(
      tester,
      OfficialFleetRankSettings(
        port: port,
        source: source,
        initial: {
          ...sample('cxgov-ranks'),
          'write': {
            'state': 'unavailable',
            'reason': 'rankPolicyWritesDisabled',
          },
        },
        onAuthorityRead: () async {},
      ),
    );
    expect(find.text('星级权限与召集授权尚未开放。'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const ValueKey('rank-2-rally')))
          .onChanged,
      isNull,
    );
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('rank-save'))).onPressed,
      isNull,
    );
  });
  testWidgets('audit unknown kind is neutral and never exposes raw code', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    port.pages['readGovernanceAudit'] = {
      ...sample('cxgov-audit'),
      'items': <Map<String, Object?>>[
        <String, Object?>{
          ...((sample('cxgov-audit')['items'] as List).first as Map)
              .cast<String, Object?>(),
          'kind': 'new.private.code',
        },
      ],
    };
    await pump(tester, OfficialFleetAuditSettings(port: port, source: source));
    expect(find.textContaining('其他管理操作'), findsOneWidget);
    expect(find.textContaining('new.private.code'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'roles cost two initial reads, lazy role reads and fixed self row',
    (tester) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      await pump(
        tester,
        OfficialFleetRoleSettings(
          port: port,
          source: source,
          viewerIsLeader: true,
          onAuthorityRead: () async {},
        ),
      );
      expect(port.reads.map((r) => r.$1), ['readRoleTemplates', 'getMembers']);
      expect(find.text('全部权限（固定）'), findsOneWidget);
      final self = find.ancestor(
        of: find.text('本人'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: self, matching: find.byType(TextButton)),
        findsNothing,
      );
      expect(find.textContaining('不会减少'), findsOneWidget);
      await tester.tap(find.text('查看角色'));
      await tester.pumpAndSettle();
      expect(port.reads.last.$1, 'readMemberRoles');
      expect(find.text('召集员'), findsWidgets);
    },
  );
  testWidgets('role editor disables rally and describes additive checkboxes', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    port.pages['readRoleTemplates'] = templates(closed: true);
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: templates(closed: true),
        onChanged: () async {},
      ),
    );
    expect(find.textContaining('未勾选表示不额外授予'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const ValueKey('role-rally.manage')),
          )
          .onChanged,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('role-organization.roles.manage')),
      findsNothing,
    );
    await tester.enterText(find.byKey(const Key('role-name')), '公告员');
    await tester.tap(find.byKey(const ValueKey('role-announcements.manage')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();
    expect(port.writes.single.$1, 'manageRoleTemplates');
    expect(port.writes.single.$2['action'], 'create');
    expect(port.writes.single.$2['requestId'], hasLength(32));
  });
  testWidgets(
    'assign reads binding on dialog open and revoke uses grant version',
    (tester) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      var changed = 0;
      await pumpDialog(
        tester,
        OfficialFleetMemberRoleDialog(
          port: port,
          source: source,
          onAuthorityRead: () async {},
          member: member(),
          roles: governanceRows(templates()['roles']),
          onChanged: (_) async {
            ++changed;
          },
        ),
      );
      expect(port.reads.single.$1, 'readMemberRoles');
      await tester.tap(find.byKey(const Key('member-role-choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('召集员').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-role-assign')));
      await tester.pumpAndSettle();
      final assign = port.writes.single.$2;
      expect(assign['targetRef'], target);
      expect(
        assign['expectedTargetMembershipEpoch'],
        'scm-observed-membership-row-v1:43',
      );
      expect(
        (assign['parts'] as List).single,
        containsPair('rootActivationId', 'activation-example'),
      );
      expect(assign.containsKey('rank'), isFalse);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(port.writes.last.$1, 'revokeRole');
      expect(port.writes.last.$2['expectedGrantVersion'], 1);
      expect(changed, 3);
    },
  );
  testWidgets('role permissions and name use separate refreshed CAS intents', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    var authorityReads = 0;
    port.onWrite = (command, fields) async {
      final page = port.pages['readRoleTemplates']!;
      final role = governanceRows(page['roles']).single;
      port.pages['readRoleTemplates'] = {
        ...page,
        'revision': (page['revision'] as int) + 1,
        'editRef': '3' * 32,
        'roles': [
          {
            ...role,
            if (command == 'updateRolePermissions') ...{
              'permissionVersion': 2,
              'permissions': fields['permissions'],
            },
            if (command == 'manageRoleTemplates')
              'metadata': fields['metadata'],
          },
        ],
      };
      return 'accepted';
    };
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: templates(),
        role: governanceRows(templates()['roles']).single,
        onChanged: () async {
          ++authorityReads;
        },
      ),
    );
    await tester.enterText(find.byKey(const Key('role-name')), '新名称');
    await tester.tap(find.byKey(const ValueKey('role-announcements.manage')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();
    expect(port.writes.map((w) => w.$1), [
      'updateRolePermissions',
      'manageRoleTemplates',
    ]);
    expect(port.writes.last.$2['editRef'], '3' * 32);
    expect(authorityReads, 2);
  });
  testWidgets('member role observations are on demand and bounded to three', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    port.pages['getMembers'] = {
      'members': [
        for (var i = 0; i < 5; i++)
          {'memberRef': '$i' * 64, 'callsign': '成员$i'},
      ],
      'totalPages': 1,
    };
    port.held = Completer<GovernanceRow>();
    await pump(
      tester,
      OfficialFleetRoleSettings(
        port: port,
        source: source,
        viewerIsLeader: true,
        onAuthorityRead: () async {},
      ),
    );
    expect(port.inFlight, 0);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('查看角色').at(i));
      await tester.pump();
    }
    expect(port.maximum, 3);
    final fourth = find.ancestor(
      of: find.text('查看角色').at(3),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(fourth).onPressed, isNull);
    port.held!.complete(memberPage());
    await tester.pumpAndSettle();
    expect(port.inFlight, 0);
  });
  testWidgets('audit continuation carries revision and known kind is Chinese', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    port.pages['readGovernanceAudit'] = {
      ...sample('cxgov-audit'),
      'nextOffset': 20,
    };
    await pump(tester, OfficialFleetAuditSettings(port: port, source: source));
    expect(find.text('撤销成员角色'), findsOneWidget);
    port.pages['readGovernanceAudit'] = {
      ...sample('cxgov-audit'),
      'offset': 20,
    };
    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();
    expect(port.reads.last.$2, {'offset': 20, 'expectedPolicyRevision': 16});
  });

  group('review CX-UI-R', () {
    GovernanceRow create() => {
      'editRef': 'e' * 32,
      'action': 'create',
      'metadata': {'displayName': '甲'},
      'permissions': const <Object?>[],
    };

    test('an unknown template write is resolved from its receipt', () async {
      final port = ManagementFake()..outcomes.add('operationOutcomeUnknown');
      addTearDown(port.changes.close);
      final writer = FleetGovernanceWriter(port, source, () async {});
      addTearDown(writer.dispose);
      expect(
        await writer.submit('manageRoleTemplates', create()),
        'operationOutcomeUnknown',
      );
      final id = port.writes.single.$2['requestId'];
      expect(await writer.submit('', {}), 'accepted');
      expect(port.outcomeQueries, [id]);
      expect(port.writes, hasLength(1));
      expect(writer.pending, isNull);
    });

    test('a request the Host never saw is sent again with its id', () async {
      final port = ManagementFake()
        ..outcomes.add('operationOutcomeUnknown')
        ..templateOutcome = governanceOutcomeNotFound;
      addTearDown(port.changes.close);
      final writer = FleetGovernanceWriter(port, source, () async {});
      addTearDown(writer.dispose);
      await writer.submit('manageRoleTemplates', create());
      expect(await writer.submit('', {}), 'accepted');
      expect(port.writes, hasLength(2));
      expect(port.writes[1].$2['requestId'], port.writes[0].$2['requestId']);
    });

    test('other commands retry the same write and never ask', () async {
      final port = ManagementFake()..outcomes.add('operationOutcomeUnknown');
      addTearDown(port.changes.close);
      final writer = FleetGovernanceWriter(port, source, () async {});
      addTearDown(writer.dispose);
      await writer.submit('revokeRole', {'grantId': 'g'});
      await writer.submit('', {});
      expect(port.outcomeQueries, isEmpty);
      expect(port.writes[1].$2['operationId'], port.writes[0].$2['operationId']);
    });

    for (final (name, row, expected) in <(String, GovernanceRow, String)>[
      (
        'accepted',
        {'status': 'accepted', 'revision': 9, 'sourceRef': source},
        'accepted',
      ),
      (
        'refused',
        {'status': 'rejected', 'error': 'notAllowed', 'sourceRef': source},
        'notAllowed',
      ),
      (
        'still unknown',
        {'status': 'unknown', 'error': 'outcomeUnknown', 'sourceRef': source},
        'operationOutcomeUnknown',
      ),
      (
        'another fleet',
        {'status': 'accepted', 'revision': 9, 'sourceRef': 'officialFleet:8'},
        'operationOutcomeUnknown',
      ),
      (
        'never recorded',
        {'status': 'unknown', 'error': 'notFound'},
        governanceOutcomeNotFound,
      ),
    ]) {
      test('the receipt query reads $name', () async {
        const name = 'officialFleet.readRoleTemplateOutcome';
        final id = 'c' * 32;
        final host = CommunityHarness(
          capabilities: const [name],
          responses: {
            name: {'schemaVersion': 1, 'kind': 'query', 'requestId': id, ...row},
          },
        );
        addTearDown(host.close);
        final port = BridgeOfficialFleetGovernanceManagement(
          host.adapter,
          const Stream.empty(),
        );
        expect(await port.roleTemplateOutcome(source, id), expected);
        final sent = host.requests.firstWhere((r) => r.name == name).payload;
        expect(sent, {'schemaVersion': 1, 'kind': 'query', 'requestId': id});
      });
    }

    testWidgets('a failed read keeps a star table holding an unknown write', (
      tester,
    ) async {
      final management = ManagementFake()
        ..outcomes.add('operationOutcomeUnknown');
      addTearDown(management.changes.close);
      management.pages['readRankPolicy'] = {
        ...sample('cxgov-ranks'),
        'write': {'state': 'allowed', 'reason': 'explicitRootControl'},
      };
      final authority = AuthorityFake(management, delegate: true, audit: true);
      await pump(
        tester,
        OfficialFleetGovernanceWorkspace(
          port: authority,
          source: source,
          onAuthorityRead: (_) {},
          builder: (panes, accept, unavailable) => Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () async => accept(await authority.read(source)),
                  child: const Text('读取'),
                ),
                TextButton(onPressed: () => unavailable('unavailable'), child: const Text('失败')),
                for (final pane in panes)
                  if (pane.id == 'ranks') pane.builder((_) async {}),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rank-2-announcements')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      final id = management.writes.single.$2['operationId'];

      management.readError = const CommunityFailure('unavailable');
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('失败'));
      await tester.pumpAndSettle();
      management.readError = null;

      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      expect(management.writes, hasLength(2));
      expect(management.writes.last.$2['operationId'], id);
    });

    testWidgets('closing the switch turns an edited star table read-only', (
      tester,
    ) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      GovernanceRow page(String state, String reason) => {
        ...sample('cxgov-ranks'),
        'write': {'state': state, 'reason': reason},
      };
      late StateSetter update;
      var current = page('allowed', 'explicitRootControl');
      await pump(
        tester,
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return OfficialFleetRankSettings(
              port: port,
              source: source,
              initial: current,
              onAuthorityRead: () async {},
            );
          },
        ),
      );
      const box = ValueKey('rank-2-announcements');
      final before = tester.widget<Checkbox>(find.byKey(box)).value;
      await tester.tap(find.byKey(box));
      await tester.pump();
      update(() => current = page('unavailable', 'rankPolicyWritesDisabled'));
      await tester.pumpAndSettle();
      final after = tester.widget<Checkbox>(find.byKey(box));
      expect(after.onChanged, isNull);
      expect(after.value, before);
      expect(find.text('星级权限与召集授权尚未开放。'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(const Key('rank-save'))).onPressed,
        isNull,
      );
    });

    testWidgets('an edit survives a new read while saving stays open', (
      tester,
    ) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      GovernanceRow page() => {
        ...sample('cxgov-ranks'),
        'write': {'state': 'allowed', 'reason': 'explicitRootControl'},
      };
      late StateSetter update;
      var current = page();
      await pump(
        tester,
        StatefulBuilder(
          builder: (_, set) {
            update = set;
            return OfficialFleetRankSettings(
              port: port,
              source: source,
              initial: current,
              onAuthorityRead: () async {},
            );
          },
        ),
      );
      const box = ValueKey('rank-2-announcements');
      final before = tester.widget<Checkbox>(find.byKey(box)).value;
      await tester.tap(find.byKey(box));
      await tester.pump();
      update(() => current = page());
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byKey(box)).value, isNot(before));
    });

    testWidgets('a refused audit read asks the section to decide again', (
      tester,
    ) async {
      final port = ManagementFake()
        ..readError = const CommunityFailure('notAllowed');
      addTearDown(port.changes.close);
      var asked = 0;
      await pump(
        tester,
        OfficialFleetAuditSettings(
          port: port,
          source: source,
          onAuthorityRead: () async => ++asked,
        ),
      );
      expect(asked, 1);
    });

    testWidgets('a refused role read asks the section to decide again', (
      tester,
    ) async {
      final port = ManagementFake()
        ..readError = const CommunityFailure('notAllowed');
      addTearDown(port.changes.close);
      var asked = 0;
      await pump(
        tester,
        OfficialFleetRoleSettings(
          port: port,
          source: source,
          viewerIsLeader: true,
          onAuthorityRead: () async => ++asked,
        ),
      );
      expect(asked, 1);
    });

    testWidgets('a conflict rereads the role so the next try can succeed', (
      tester,
    ) async {
      final port = ManagementFake()..outcomes.add('conflict');
      addTearDown(port.changes.close);
      final moved = templates();
      (moved['roles'] as List).first['permissionVersion'] = 2;
      port.pages['readRoleTemplates'] = moved;
      final read = <(Object?, GovernanceRow?)>[];
      await pumpDialog(
        tester,
        OfficialFleetMemberRoleDialog(
          port: port,
          source: source,
          onAuthorityRead: () async {},
          member: member(),
          roles: governanceRows(templates()['roles']),
          onChanged: (_) async {},
          onRoleRead: (key, role) => read.add((key, role)),
        ),
      );
      await tester.tap(find.byKey(const Key('member-role-choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('召集员').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-role-assign')));
      await tester.pumpAndSettle();
      expect(port.writes.single.$2['expectedRolePermissionVersion'], 1);
      expect(read.single.$2!['permissionVersion'], 2);
      await tester.tap(find.byKey(const Key('member-role-assign')));
      await tester.pumpAndSettle();
      expect(port.writes.last.$2['expectedRolePermissionVersion'], 2);
    });

    testWidgets('an unknown write does not lock the dialog', (tester) async {
      final port = ManagementFake()..outcomes.add('operationOutcomeUnknown');
      addTearDown(port.changes.close);
      await pumpDialog(
        tester,
        OfficialFleetMemberRoleDialog(
          port: port,
          source: source,
          onAuthorityRead: () async {},
          member: member(),
          roles: governanceRows(templates()['roles']),
          onChanged: (_) async {},
        ),
      );
      await tester.tap(find.byKey(const Key('member-role-choice')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('召集员').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('member-role-assign')));
      await tester.pumpAndSettle();
      expect(find.text('重试原操作'), findsOneWidget);
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('closing on an unknown create keeps the same operation', (
      tester,
    ) async {
      final port = ManagementFake()..outcomes.add('operationOutcomeUnknown');
      addTearDown(port.changes.close);
      await pump(
        tester,
        OfficialFleetRoleSettings(
          port: port,
          source: source,
          viewerIsLeader: true,
          onAuthorityRead: () async {},
        ),
      );
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('role-name')), '甲');
      await tester.pump();
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      final id = port.writes.single.$2['requestId'];
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      expect(find.text('重试原操作'), findsOneWidget);
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      expect(port.outcomeQueries, [id]);
      expect(port.writes, hasLength(1));
    });

    testWidgets('a failed refresh keeps a role section holding a write', (
      tester,
    ) async {
      final management = ManagementFake()
        ..outcomes.add('operationOutcomeUnknown');
      addTearDown(management.changes.close);
      final authority = AuthorityFake(management, delegate: true, audit: true);
      await pump(
        tester,
        OfficialFleetGovernanceWorkspace(
          port: authority,
          source: source,
          onAuthorityRead: (_) {},
          builder: (panes, accept, unavailable) => Column(
            children: [
              TextButton(
                onPressed: () async => accept(await authority.read(source)),
                child: const Text('读取'),
              ),
              TextButton(onPressed: () => unavailable('unavailable'), child: const Text('失败')),
              for (final pane in panes)
                if (pane.id == 'roles') pane.builder((_) async {}),
            ],
          ),
        ),
      );
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('role-name')), '甲');
      await tester.pump();
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      final id = management.writes.single.$2['requestId'];
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('失败'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      expect(management.outcomeQueries, [id]);
      expect(management.writes, hasLength(1));
    });

    testWidgets('failed reads keep an unsaved star table edit', (tester) async {
      final management = ManagementFake();
      addTearDown(management.changes.close);
      management.pages['readRankPolicy'] = {
        ...sample('cxgov-ranks'),
        'write': {'state': 'allowed', 'reason': 'explicitRootControl'},
      };
      final authority = AuthorityFake(management, delegate: true, audit: true);
      await pump(
        tester,
        OfficialFleetGovernanceWorkspace(
          port: authority,
          source: source,
          onAuthorityRead: (_) {},
          builder: (panes, accept, unavailable) => Column(
            children: [
              TextButton(
                onPressed: () async => accept(await authority.read(source)),
                child: const Text('读取'),
              ),
              TextButton(
                onPressed: () => unavailable('unavailable'),
                child: const Text('失败'),
              ),
              for (final pane in panes)
                if (pane.id == 'ranks') pane.builder((_) async {}),
            ],
          ),
        ),
      );
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      const box = ValueKey('rank-2-announcements');
      final before = tester.widget<Checkbox>(find.byKey(box)).value;
      await tester.tap(find.byKey(box));
      await tester.pump();
      await tester.tap(find.text('失败'));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(find.byKey(box)).value, isNot(before));
    });

    testWidgets('a held write settling reads authority once more, no loop', (
      tester,
    ) async {
      final management = ManagementFake()
        ..outcomes.add('operationOutcomeUnknown');
      addTearDown(management.changes.close);
      management.pages['readRankPolicy'] = {
        ...sample('cxgov-ranks'),
        'write': {'state': 'allowed', 'reason': 'explicitRootControl'},
      };
      final authority = AuthorityFake(management, delegate: true, audit: true);
      await pump(
        tester,
        OfficialFleetGovernanceWorkspace(
          port: authority,
          source: source,
          onAuthorityRead: (_) {},
          builder: (panes, accept, unavailable) => Column(
            children: [
              TextButton(
                onPressed: () async => accept(await authority.read(source)),
                child: const Text('读取'),
              ),
              TextButton(
                onPressed: () => unavailable('unavailable'),
                child: const Text('失败'),
              ),
              for (final pane in panes)
                if (pane.id == 'ranks') pane.builder((_) async {}),
            ],
          ),
        ),
      );
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rank-2-announcements')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('失败'));
      await tester.pumpAndSettle();
      final ranksBefore = management.reads
          .where((r) => r.$1 == 'readRankPolicy')
          .length;
      await tester.tap(find.byKey(const Key('rank-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rank-save')), findsOneWidget);
      final ranksAfter = management.reads
          .where((r) => r.$1 == 'readRankPolicy')
          .length;
      // The write's own reload, then the one read after it settled, then stop.
      expect(ranksAfter - ranksBefore, lessThanOrEqualTo(3));
    });

    testWidgets('a denied page read clears even with a write held', (
      tester,
    ) async {
      final management = ManagementFake()
        ..outcomes.add('operationOutcomeUnknown');
      addTearDown(management.changes.close);
      final authority = AuthorityFake(management, delegate: true, audit: true);
      await pump(
        tester,
        OfficialFleetGovernanceWorkspace(
          port: authority,
          source: source,
          onAuthorityRead: (_) {},
          builder: (panes, accept, unavailable) => Column(
            children: [
              TextButton(
                onPressed: () async => accept(await authority.read(source)),
                child: const Text('读取'),
              ),
              TextButton(
                onPressed: () => unavailable('notAllowed'),
                child: const Text('拒绝'),
              ),
              for (final pane in panes)
                if (pane.id == 'roles') pane.builder((_) async {}),
            ],
          ),
        ),
      );
      await tester.tap(find.text('读取'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('role-name')), '甲');
      await tester.pump();
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃修改'));
      await tester.pumpAndSettle();
      expect(find.text('新建角色'), findsOneWidget);
      await tester.tap(find.text('拒绝'));
      await tester.pumpAndSettle();
      expect(find.text('新建角色'), findsNothing);
    });

    testWidgets('a confirmed write leaves nothing behind to retry', (
      tester,
    ) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      await pump(
        tester,
        OfficialFleetRoleSettings(
          port: port,
          source: source,
          viewerIsLeader: true,
          onAuthorityRead: () async {},
        ),
      );
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('role-name')), '甲');
      await tester.pump();
      await tester.tap(find.byKey(const Key('role-save')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建角色'));
      await tester.pumpAndSettle();
      expect(find.text('重试原操作'), findsNothing);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('a failed read drops the member roles shown before', (
      tester,
    ) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      await pump(
        tester,
        OfficialFleetRoleSettings(
          port: port,
          source: source,
          viewerIsLeader: true,
          onAuthorityRead: () async {},
        ),
      );
      await tester.tap(find.text('查看角色').first);
      await tester.pumpAndSettle();
      expect(find.text('无额外角色'), findsNothing);
      expect(find.text('撤销'), findsWidgets);
      port.readError = const CommunityFailure('notAllowed');
      await tester.tap(find.text('查看角色').first);
      await tester.pumpAndSettle();
      expect(find.text('撤销'), findsNothing);
    });
  });
}
