import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_channel_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3ca_test.dart' show fire;
import 'interaction_batch3bw_test.dart' show frames;
import 'interaction_batch3cl_channel_test.dart' show state;

Map<String, Object?> messages(int count, {bool busy = false}) {
  final raw = state(outbox: true);
  raw['busy'] = busy;
  raw['rows'] = [
    for (var i = 0; i < count; i++)
      {'title': 'Pilot $i', 'detail': 'Message $i'},
  ];
  raw['chat'] = {
    ...raw['chat'] as Map,
    'receipts': <String, String>{},
    'messages': [
      for (var i = 0; i < count; i++)
        {
          'self': false,
          'time': DateTime.utc(2026, 1, 1, 0, i).toIso8601String(),
        },
    ],
  };
  return raw;
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source channel refresh keeps original action, gate and active repeated feedback',
        (t) async {
          size(t, const Size(900, 1000));
          final semantics = t.ensureSemantics();
          final raw = ValueNotifier(messages(2));
          final calls = <(String, String, InteractionSource)>[];
          await t.pumpWidget(
            scopedApp(
              ValueListenableBuilder(
                valueListenable: raw,
                builder: (_, view, _) => MenuChannelPanel(
                  view: MenuFeatureView.parse(view),
                  active: false,
                  onAction: (a, k) =>
                      calls.add((a, k, currentStarBridgeActivationSource)),
                ),
              ),
              suite,
            ),
          );
          try {
            await frames(t, 2);
            for (var i = 0; i < 3; i++) {
              await fire(
                t,
                source,
                find.byKey(const ValueKey('menu-channel-refresh')),
              );
            }
            expect(
              calls,
              List.filled(3, (
                'refresh',
                '',
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              )),
            );
            raw.value = messages(2, busy: true);
            await t.pump();
            final control = t.widget(
              find.byKey(const ValueKey('menu-channel-refresh')),
            );
            expect(
              control is TextButton
                  ? control.onPressed
                  : (control as SuitePressable).onActivate,
              isNull,
            );
            expect(calls, hasLength(3));
          } finally {
            semantics.dispose();
            await t.pumpWidget(const SizedBox());
            raw.dispose();
          }
        },
      );
      for (final embed in ['channel', 'room', 'org']) {
        testWidgets(
          '$suite $source $embed return to bottom is local, source aware and retains scroll owner',
          (t) async {
            size(t, const Size(900, 900));
            final semantics = t.ensureSemantics();
            final raw = ValueNotifier(messages(30));
            final calls = <String>[];
            await t.pumpWidget(
              scopedApp(
                ValueListenableBuilder(
                  valueListenable: raw,
                  builder: (_, view, _) => MenuChannelPanel(
                    view: MenuFeatureView.parse(view),
                    active: false,
                    embeddedRoom: embed == 'room',
                    embeddedOrganization: embed == 'org',
                    onAction: (a, _) => calls.add(a),
                  ),
                ),
                suite,
              ),
            );
            try {
              await frames(t, 2);
              final list = find.byKey(const ValueKey('menu-channel-history'));
              final scroll = t.widget<ListView>(list).controller!;
              expect(scroll.position.maxScrollExtent, greaterThan(300));
              scroll.jumpTo(250);
              await t.pump();
              raw.value = messages(31);
              await t.pump();
              await t.pump();
              final jump = find.byKey(
                const ValueKey('menu-channel-new-messages'),
              );
              expect(jump, findsOneWidget);
              expect(scroll.offset, greaterThan(0));
              await fire(t, source, jump);
              await frames(t, 2);
              expect(t.widget<ListView>(list).controller, same(scroll));
              expect(scroll.offset, 0);
              expect(jump, findsNothing);
              expect(
                calls,
                isEmpty,
                reason: 'local jump must not fetch, acknowledge or resend',
              );
            } finally {
              semantics.dispose();
              await t.pumpWidget(const SizedBox());
              raw.dispose();
            }
          },
        );
      }
    }
  }
}
