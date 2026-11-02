// Each organization's own privacy and notifications live on its page
// (user 2026-10-31), matched by code and never by name.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/bridge_notification_sources.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_models.dart';
import 'package:starbridge_flutter/features/settings/notification_settings_sources.dart';
import 'package:starbridge_flutter/features/settings/organization_notification_pane.dart';

import '../friends/social_layout_test.dart' show app, loadFonts;

NotificationSourceRule _rule(
  String ref,
  NotificationSourceKind kind,
  String name, {
  String? code,
}) => NotificationSourceRule(
  sourceRef: ref,
  kind: kind,
  displayName: name,
  contextLabel: '',
  mode: NotificationSourceMode.values.first,
  organizationCode: code,
);

final class _Port implements NotificationSourcesPort {
  _Port(this.value);
  NotificationSourcesValue value;
  final saved = <Map<String, NotificationSourceMode>>[];
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get invalidations => changes.stream;
  @override
  Future<NotificationSourcesValue> read() async => value;
  @override
  Future<NotificationSourcesValue> save(
    NotificationSourcesValue original,
    Map<String, NotificationSourceMode> modes,
  ) async {
    saved.add(modes);
    return value;
  }

  @override
  void dispose() {}
}

void main() {
  setUpAll(loadFonts);
  final sources = NotificationSourcesValue(1, [
    _rule('organization:a', NotificationSourceKind.community, 'Same', code: 'AAA'),
    _rule('organization:b', NotificationSourceKind.community, 'Same', code: 'bbb'),
    _rule('officialFleet:c', NotificationSourceKind.officialFleet, 'Fleet'),
  ]);

  test('a community is found by its code, and two can share a name', () {
    expect(organizationNotificationRule(sources, 'aaa')!.sourceRef, 'organization:a');
    expect(organizationNotificationRule(sources, 'BBB')!.sourceRef, 'organization:b');
    expect(organizationNotificationRule(sources, 'Same'), isNull);
    expect(organizationNotificationRule(sources, 'ccc'), isNull);
  });

  test('the main fleet is its own source, never a community', () {
    expect(organizationNotificationRule(sources, null)!.sourceRef, 'officialFleet:c');
    final none = NotificationSourcesValue(1, [
      _rule('organization:a', NotificationSourceKind.community, 'A', code: 'a'),
    ]);
    expect(organizationNotificationRule(none, null), isNull);
  });

  test('a Host without codes finds no community rather than guessing', () {
    final old = NotificationSourcesValue(1, [
      _rule('organization:a', NotificationSourceKind.community, 'A'),
    ]);
    expect(organizationNotificationRule(old, 'a'), isNull);
  });

  test('a saved rule keeps its code, so its page still finds it', () {
    final rule = _rule(
      'organization:a',
      NotificationSourceKind.community,
      'A',
      code: 'aaa',
    );
    expect(rule.copyWith(mode: NotificationSourceMode.values.last).organizationCode, 'aaa');
    expect(
      _rule('organization:a', NotificationSourceKind.community, 'A')
          .copyWith(organizationCode: 'aaa')
          .organizationCode,
      'aaa',
    );
  });

  testWidgets('changing one organization keeps every other choice', (
    tester,
  ) async {
    final port = _Port(sources);
    addTearDown(port.changes.close);
    await tester.pumpWidget(
      app(OrganizationNotificationPane(create: () => port, communityCode: 'aaa')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NotificationSourceRuleRow), findsOneWidget);
    final row = tester.widget<NotificationSourceRuleRow>(
      find.byType(NotificationSourceRuleRow),
    );
    expect(row.rule.sourceRef, 'organization:a');
    final next = NotificationSourceMode.values.last;
    row.onChanged(next);
    await tester.pumpAndSettle();
    expect(port.saved.single, {
      'organization:a': next,
      'organization:b': sources.modes['organization:b'],
      'officialFleet:c': sources.modes['officialFleet:c'],
    });
  });
}
