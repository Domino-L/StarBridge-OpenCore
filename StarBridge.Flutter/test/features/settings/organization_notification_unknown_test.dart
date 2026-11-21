import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_organization_controls.dart';
import 'package:starbridge_flutter/features/settings/notification_organization_options.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_editor_frame.dart';
import 'package:starbridge_flutter/features/settings/organization_notification_leave_guard.dart';
import 'package:starbridge_flutter/features/settings/organization_notification_pane.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_envelope.dart';
import 'package:starbridge_flutter/platform/bridge/in_memory_bridge_connection.dart';

import '../friends/social_layout_test.dart' show app, loadFonts, size;

class _Port implements OrganizationNotificationSourcesPort {
  final initial = NotificationSourcesValue(0, [
    for (final code in ['A', 'B'])
      NotificationSourceRule(
        sourceRef: code,
        kind: NotificationSourceKind.community,
        displayName: code,
        organizationCode: code,
        contextLabel: '',
        mode: NotificationSourceMode.normal,
      ),
  ], supportsOrganizationOptions: true);
  final writes =
      <
        (
          NotificationSourcesValue,
          Map<String, NotificationSourceMode>,
          Map<String, NotificationOrganizationOptions>,
        )
      >[];
  Object? failure = const BridgeRemoteException(
    'notificationPolicies.unconfirmed',
  );
  int reads = 0;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<NotificationSourcesValue> read() async {
    reads++;
    return initial;
  }

  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) => saveOrganizationOptions(original, modes, const {});
  @override
  Future<NotificationSourcesValue> saveOrganizationOptions(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
    Map<String, NotificationOrganizationOptions> options,
  ) async {
    writes.add((original, Map.of(modes), Map.of(options)));
    if (failure case final error?) throw error;
    return NotificationSourcesValue(original.revision + 1, [
      for (final source in original.sources)
        source.copyWith(
          mode: modes[source.sourceRef],
          organizationOptions: options[source.sourceRef],
        ),
    ], supportsOrganizationOptions: true);
  }

  @override
  void dispose() {}
}

void main() {
  setUpAll(loadFonts);
  for (final modeSave in [false, true]) {
    testWidgets('organization unknown freezes both controls mode=$modeSave', (
      tester,
    ) async {
      size(tester, const Size(1100, 1500));
      final port = _Port();
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: OrganizationNotificationPane(
              create: () => port,
              communityCode: 'A',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      NotificationOrganizationControls controls() =>
          tester.widget(find.byType(NotificationOrganizationControls));
      NotificationSourceRuleRow row() =>
          tester.widget(find.byType(NotificationSourceRuleRow));
      const draft = NotificationOrganizationOptions(
        chat: NotificationChatMode.enabled,
      );
      final staleEdit = controls().onChanged;
      final staleMode = row().onChanged;
      staleEdit(draft);
      await tester.pumpAndSettle();
      if (modeSave) {
        await staleMode(NotificationSourceMode.importantOnly);
      } else {
        await tester.tap(
          find.byKey(const Key('organization-notification-save-options')),
        );
      }
      await tester.pumpAndSettle();
      expect(controls().enabled, isFalse);
      expect(row().enabled, isFalse);
      expect(port.writes, hasLength(1));
      staleEdit(draft.copyWith(endMinute: 456));
      await staleMode(NotificationSourceMode.doNotDisturb);
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(1));
      expect(controls().value, draft);
      port.failure = null;
      await tester.tap(
        find.byKey(const Key('organization-notification-retry-write')),
      );
      await tester.pumpAndSettle();
      expect(port.writes, hasLength(2));
      expect(identical(port.writes.first.$1, port.writes.last.$1), isTrue);
      expect(port.writes.last.$2, port.writes.first.$2);
      expect(port.writes.last.$3, port.writes.first.$3);
      expect(port.writes.last.$2['B'], NotificationSourceMode.normal);
      expect(port.writes.last.$3.keys, modeSave ? isEmpty : ['A']);
      expect(port.reads, 1);
      expect(controls().enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  for (final closing in [false, true]) {
    for (final discard in [false, true]) {
      testWidgets(
        'unknown guards leave/exit closing=$closing discard=$discard',
        (tester) async {
          size(tester, const Size(1100, 1500));
          final port = _Port();
          await tester.pumpWidget(
            app(
              SingleChildScrollView(
                child: OrganizationNotificationPane(
                  create: () => port,
                  communityCode: 'A',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester
              .widget<NotificationSourceRuleRow>(
                find.byType(NotificationSourceRuleRow),
              )
              .onChanged(NotificationSourceMode.importantOnly);
          await tester.pumpAndSettle();
          Future<bool> leave() => closing
              ? confirmNotificationLeave(Object())
              : confirmOrganizationNotificationLeave();
          final stay = leave();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('organization-notification-leave-dialog')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('organization-notification-leave-stay')),
          );
          await tester.pumpAndSettle();
          expect(await stay, isFalse);
          expect(port.writes, hasLength(1));
          final resolution = leave();
          await tester.pumpAndSettle();
          port.failure = null;
          await tester.tap(
            find.byKey(
              Key(
                discard
                    ? 'organization-notification-leave-discard'
                    : 'organization-notification-leave-retry',
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(await resolution, isTrue);
          expect(port.writes, hasLength(discard ? 1 : 2));
          if (!discard) expect(port.writes.last.$2, port.writes.first.$2);
          expect(await leave(), isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  for (final modeSave in [false, true]) {
    testWidgets(
      'organization retry preserves bridge operationId mode=$modeSave',
      (tester) async {
        size(tester, const Size(1100, 1500));
        final pair = InMemoryBridgeConnection.createPair();
        final session = BridgeClientSession(
          connection: pair.client,
          sessionGeneration: 1,
        );
        session.acceptHostCapabilities([
          'account.getCurrent',
          'notificationPolicies.readV3',
          'notificationPolicies.saveV3',
        ]);
        const owner = BridgeAccountContext(
          environment: 'fixture',
          authority: 'fixture',
          subject: 'fixture',
        );
        final requests = <BridgeEnvelope>[];
        final sourceRef = 'organization:${'a' * 64}';
        final sub = pair.host.incoming.listen((request) {
          final saving = request.name == 'notificationPolicies.saveV3';
          if (saving) requests.add(request);
          final fail = saving && requests.length == 1;
          final rules = (request.payload['rules'] as List?)?.cast<Map>();
          final rule = rules?.firstWhere((r) => r['sourceRef'] == sourceRef);
          pair.host.send(
            BridgeEnvelope(
              protocolVersion: 1,
              messageType: 'response',
              name: request.name,
              correlationId: request.correlationId,
              sessionGeneration: 1,
              accountContext: owner,
              status: fail ? 'error' : 'ok',
              error: fail
                  ? const BridgeErrorBody(
                      code: 'unconfirmed',
                      message: 'unconfirmed',
                      retryable: true,
                    )
                  : null,
              payload: request.name == 'account.getCurrent'
                  ? {'schemaVersion': 1, 'state': 'signedIn'}
                  : {
                      'schemaVersion': 3,
                      'revision': saving ? 1 : 0,
                      if (saving) 'operationId': request.payload['operationId'],
                      'roomMode': 'normal',
                      'friendMode': 'normal',
                      'directMessageMode': 'normal',
                      'sources': [
                        {
                          'sourceRef': sourceRef,
                          'kind': 'community',
                          'displayName': 'Synthetic',
                          'organizationCode': 'A',
                          'mode': rule?['mode'] ?? 'normal',
                          ...const NotificationOrganizationOptions().toWire(),
                          if (rule != null) ...rule.cast<String, Object?>(),
                        },
                      ],
                    },
            ),
          );
        });
        final port = BridgeNotificationSources(session);
        addTearDown(() async {
          await sub.cancel();
          await session.close();
          await pair.host.close();
        });
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: OrganizationNotificationPane(
                create: () => port,
                communityCode: 'A',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (modeSave) {
          await tester
              .widget<NotificationSourceRuleRow>(
                find.byType(NotificationSourceRuleRow),
              )
              .onChanged(NotificationSourceMode.importantOnly);
        } else {
          tester
              .widget<NotificationOrganizationControls>(
                find.byType(NotificationOrganizationControls),
              )
              .onChanged(
                const NotificationOrganizationOptions(
                  chat: NotificationChatMode.enabled,
                ),
              );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const Key('organization-notification-save-options')),
          );
        }
        await tester.pumpAndSettle();
        expect(requests, hasLength(1));
        await tester.tap(
          find.byKey(const Key('organization-notification-retry-write')),
        );
        await tester.pumpAndSettle();
        expect(requests, hasLength(2));
        expect(requests.first.payload, requests.last.payload);
        expect(requests.first.payload['operationId'], isNotEmpty);
        expect(
          tester
              .widget<NotificationSourceRuleRow>(
                find.byType(NotificationSourceRuleRow),
              )
              .enabled,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
