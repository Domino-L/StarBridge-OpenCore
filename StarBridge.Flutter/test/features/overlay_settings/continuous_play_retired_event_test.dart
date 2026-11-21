import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_models.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_schema.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_workspace_controls.dart';

import 'overlay_settings_ux_a_test.dart' show settings;
import '../friends/social_layout_test.dart' show app, size;

void main() {
  test(
    'retired bit and custom duration survive edits and serialized saves',
    () {
      for (final bit in [0, 1024]) {
        final base = settings();
        final initial = OverlayWorkspaceSettings.fromMap({
          ...base.toMap(),
          'eventNotificationTypes': bit | 8,
          'eventNotificationDurations': {
            ...Map<String, Object?>.from(
              base['eventNotificationDurations']! as Map,
            ),
            'localPlayReminder': 17.5,
          },
        });
        final edited = initial
            .withValue('eventNotificationTypes', 16)
            .withValue('eventNotificationDurations', {
              ...Map<String, Object?>.from(
                initial['eventNotificationDurations']! as Map,
              ),
              'shipChange': 5.0,
              'localPlayReminder': 0,
            });
        final saved = OverlayWorkspaceSettings.fromMap(
          Map<String, Object?>.from(
            jsonDecode(jsonEncode(edited.toMap())) as Map,
          ),
        );
        expect(saved['eventNotificationTypes'], bit | 16);
        expect(
          (saved['eventNotificationDurations']! as Map)['localPlayReminder'],
          17.5,
        );
        expect(
          (saved['eventNotificationDurations']! as Map)['shipChange'],
          5.0,
        );
      }
      expect(overlayEventTypes.map((e) => e.$1), isNot(contains(1024)));
      expect(
        overlayDurationFields.map((e) => e.$1),
        isNot(contains('localPlayReminder')),
      );
    },
  );

  testWidgets(
    'event controls omit reminder and preserve it when a visible chip changes',
    (tester) async {
      size(tester, const Size(1000, 1600));
      var draft = settings({
        'showEventNotifications': true,
        'eventNotificationTypes': 1024,
      });
      await tester.pumpWidget(
        app(
          StatefulBuilder(
            builder: (context, update) {
              return SingleChildScrollView(
                child: OverlayWorkspaceSettingsGroup(
                  group: 'events',
                  fields: overlayWorkspaceFieldSpecs
                      .where(
                        (f) =>
                            f.field == 'eventNotificationTypes' ||
                            f.field == 'eventNotificationDurations',
                      )
                      .toList(),
                  settings: draft,
                  onChanged: (field, value) =>
                      update(() => draft = draft.withValue(field, value)),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overlay-event-type-1024')), findsNothing);
      expect(
        find.byKey(const Key('overlay-duration-localPlayReminder')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('overlay-duration-localPlayReminder-input')),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('overlay-event-type-8')));
      await tester.pumpAndSettle();
      expect(draft['eventNotificationTypes'], 1024 | 8);
      expect(
        (draft.toMap()['eventNotificationDurations']!
            as Map)['localPlayReminder'],
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
