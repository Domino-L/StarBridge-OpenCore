import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_management.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_governance_writer.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_member_role_dialog.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_role_editor.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_role_settings.dart';

import 'official_fleet_governance_management_test.dart'
    show
        ManagementFake,
        member,
        memberPage,
        pump,
        pumpDialog,
        source,
        templates;

GovernanceRow _role(GovernanceRow page) =>
    (page['roles'] as List).cast<GovernanceRow>().single;

void main() {
  for (final omitted in [false, true]) {
    testWidgets(
      'unknown deletion stays listed and retries the exact original operation after reopening: omitted=$omitted',
      (tester) async {
        final port = ManagementFake();
        addTearDown(port.changes.close);
        var attempts = 0;
        port.onWrite = (command, intent) async {
          attempts++;
          final deleted = templates();
          _role(deleted)['enabled'] = false;
          if (omitted) deleted['roles'] = <GovernanceRow>[];
          port.pages['readRoleTemplates'] = deleted;
          return attempts == 1 ? 'operationOutcomeUnknown' : 'duplicate';
        };
        final pending = <bool>[];
        await pump(
          tester,
          OfficialFleetRoleSettings(
            port: port,
            source: source,
            viewerIsLeader: true,
            onAuthorityRead: () async {},
            onWritePending: pending.add,
          ),
        );
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('role-delete')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('role-delete-confirm')));
        await tester.pumpAndSettle();
        expect(port.writes, hasLength(1));
        expect(pending.last, isTrue);
        final original = port.writes.single;
        await tester.tap(find.text('放弃修改'));
        await tester.pumpAndSettle();
        expect(find.text('召集员'), findsOneWidget);
        expect(port.writes, hasLength(1), reason: 'No automatic retry');
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(
          tester.widget<TextField>(find.byKey(const Key('role-name'))).enabled,
          isFalse,
          reason: 'Only the original pending operation may be retried',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('role-save')))
              .onPressed,
          isNotNull,
        );
        expect(port.writes, hasLength(1), reason: 'Opening only reads');
        await tester.tap(find.byKey(const Key('role-save')));
        await tester.pumpAndSettle();
        expect(port.writes, hasLength(2));
        expect(port.writes.last.$1, original.$1);
        expect(port.writes.last.$2, original.$2);
        expect(pending.last, isFalse);
        expect(find.text('召集员'), findsNothing);
        expect(find.byKey(const Key('role-name')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('pending metadata queries its receipt with writes disabled', (
    tester,
  ) async {
    final port = ManagementFake()..outcomes.add('operationOutcomeUnknown');
    addTearDown(port.changes.close);
    final page = templates();
    final writer = FleetGovernanceWriter(port, source, () async {});
    addTearDown(writer.dispose);
    expect(
      await writer.submit('manageRoleTemplates', {
        'editRef': page['editRef'],
        'action': 'metadata',
        'roleRef': _role(page)['roleRef'],
        'metadata': {
          ..._role(page)['metadata'] as Map,
          'displayName': 'New name',
        },
      }),
      'operationOutcomeUnknown',
    );
    final requestId = writer.pending!.fields['requestId'];
    final fresh = templates();
    fresh['access'] = {
      'updateMetadata': {'state': 'unavailable', 'reason': 'writesDisabled'},
    };
    port.pages['readRoleTemplates'] = fresh;
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: page,
        role: _role(page),
        writer: writer,
        onChanged: () async {},
      ),
    );
    expect(find.byKey(const Key('role-delete')), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('role-save'))).onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('role-save')));
    await tester.pumpAndSettle();
    expect(port.outcomeQueries, [requestId]);
    expect(
      port.writes,
      hasLength(1),
      reason: 'Only the original write, no new write',
    );
    expect(writer.pending, isNull);
    expect(writer.result, 'accepted');
    expect(tester.takeException(), isNull);
  });

  for (final state in ['allowed', 'unavailable', 'denied', null]) {
    testWidgets('role deletion follows template write access: $state', (
      tester,
    ) async {
      final port = ManagementFake();
      addTearDown(port.changes.close);
      final initial = templates();
      final fresh = templates();
      fresh['access'] = {
        'create': {'state': 'allowed'},
        if (state != null)
          'updateMetadata': {'state': state, 'reason': 'writesDisabled'},
      };
      port.pages['readRoleTemplates'] = fresh;
      await pumpDialog(
        tester,
        OfficialFleetRoleEditor(
          port: port,
          source: source,
          page: initial,
          role: _role(initial),
          onChanged: () async {},
        ),
      );
      expect(
        find.byKey(const Key('role-delete')),
        state == 'allowed' ? findsOneWidget : findsNothing,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('role-save')))
            .onPressed,
        state == 'allowed' ? isNotNull : isNull,
      );
      expect(port.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('deleting a role disables it and keeps its other fields', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    final page = templates();
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: page,
        role: _role(page),
        onChanged: () async {},
      ),
    );
    await tester.tap(find.byKey(const Key('role-delete')));
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty, reason: 'Nothing goes out before confirming');
    expect(find.textContaining('不能恢复'), findsOneWidget);
    await tester.tap(find.byKey(const Key('role-delete-confirm')));
    await tester.pumpAndSettle();
    final (command, intent) = port.writes.single;
    expect(command, 'updateRolePermissions');
    expect(intent['enabled'], isFalse);
    expect(intent['roleKey'], 'rally-lead');
    expect(intent['permissions'], [
      {'capability': 'audit.view', 'canUse': true, 'canDelegate': false},
    ]);
    expect(find.byKey(const Key('role-name')), findsNothing, reason: 'Closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling writes nothing', (tester) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    final page = templates();
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: page,
        role: _role(page),
        onChanged: () async {},
      ),
    );
    await tester.tap(find.byKey(const Key('role-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留角色'));
    await tester.pumpAndSettle();
    expect(port.writes, isEmpty);
    expect(find.byKey(const Key('role-name')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new role cannot be deleted', (tester) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    await pumpDialog(
      tester,
      OfficialFleetRoleEditor(
        port: port,
        source: source,
        page: templates(),
        onChanged: () async {},
      ),
    );
    expect(find.byKey(const Key('role-delete')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deleted role leaves the list and the member dialog', (
    tester,
  ) async {
    final port = ManagementFake();
    addTearDown(port.changes.close);
    final page = templates();
    _role(page)['enabled'] = false;
    port.pages['readRoleTemplates'] = page;
    await pump(
      tester,
      OfficialFleetRoleSettings(
        port: port,
        source: source,
        viewerIsLeader: true,
        onAuthorityRead: () async {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('召集员'), findsNothing);

    final grants = memberPage();
    grants['grants'] = [
      {
        'grantId': 'g',
        'roleKey': 'rally-lead',
        'revoked': false,
        'version': 1,
        'permissionVersion': 1,
      },
    ];
    port.pages['readMemberRoles'] = grants;
    await pumpDialog(
      tester,
      OfficialFleetMemberRoleDialog(
        port: port,
        source: source,
        member: member(),
        roles: [_role(page)],
        onChanged: (_) async {},
        onAuthorityRead: () async {},
      ),
    );
    expect(find.text('召集员'), findsNothing);
    expect(find.text('撤销'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
