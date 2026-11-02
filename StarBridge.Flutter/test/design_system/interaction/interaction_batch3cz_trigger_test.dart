import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/app/presence/manual_presence_widgets.dart';
import 'package:starbridge_flutter/app/tray/tray_presence_menu.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cz_actions_test.dart' show exposed;

Widget nativeTrigger(BuildContext context, ManualPresenceController control) =>
    TextButton(
      key: const Key('native-presence'),
      onPressed: () {},
      child: Row(
        children: [
          Expanded(child: Text(manualPresenceText(context, 'presence.title'))),
          ManualPresenceBadge(controller: control),
          const SizedBox(width: 8),
          const StarBridgeIcon(StarBridgeIconSemantic.menuDown, size: 12),
        ],
      ),
    );
void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final mode in [
          PresenceVisibility.online,
          PresenceVisibility.invisible,
        ]) {
          testWidgets(
            '$suite light=$light scale=$scale $mode trigger keeps native bounds and live readable status',
            (t) async {
              final sem = t.ensureSemantics();
              var writes = 0;
              final source = ValueNotifier(
                ManualPresenceSnapshot(
                  scope: 1,
                  confirmedMode: mode,
                  automaticKey: 'presence.online',
                  canChange: true,
                ),
              );
              final control = ManualPresenceController(
                source: source,
                write: (_, _) async {
                  writes++;
                },
              );
              try {
                await t.pumpWidget(
                  scopedApp(
                    Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 304,
                              child: nativeTrigger(context, control),
                            ),
                            SizedBox(
                              width: 304,
                              child: TrayPresenceMenu(controller: control),
                            ),
                          ],
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                  ),
                );
                await t.pumpAndSettle();
                for (final next in [
                  mode,
                  mode == PresenceVisibility.online
                      ? PresenceVisibility.invisible
                      : PresenceVisibility.online,
                ]) {
                  source.value = ManualPresenceSnapshot(
                    scope: 1,
                    confirmedMode: next,
                    automaticKey: 'presence.online',
                    canChange: true,
                  );
                  await t.pump();
                  await t.pump();
                  expect(
                    t.getSize(find.byKey(const Key('tray-presence-menu'))),
                    t.getSize(find.byKey(const Key('native-presence'))),
                  );
                  final expected = t
                      .getSemantics(find.byKey(const Key('native-presence')))
                      .getSemanticsData()
                      .label;
                  expect(
                    exposed(t, 'tray-presence-menu').getSemanticsData().label,
                    expected,
                  );
                }
                expect(writes, 0);
                expect(t.takeException(), isNull);
              } finally {
                sem.dispose();
                await t.pumpWidget(const SizedBox());
                await t.pump();
                control.dispose();
                source.dispose();
              }
            },
          );
        }
      }
    }
  }
  for (final check in ['geometry', 'semantics']) {
    testWidgets('tray status trigger preserves native $check', (t) async {
      final sem = t.ensureSemantics();
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 1,
          confirmedMode: PresenceVisibility.online,
          automaticKey: 'presence.online',
          canChange: true,
        ),
      );
      final control = ManualPresenceController(
        source: source,
        write: (_, _) async {},
      );
      try {
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: 304, child: nativeTrigger(context, control)),
                  SizedBox(
                    width: 304,
                    child: TrayPresenceMenu(controller: control),
                  ),
                ],
              ),
            ),
            InteractionSuite.rail,
          ),
        );
        await t.pumpAndSettle();
        if (check == 'geometry') {
          expect(
            t.getSize(find.byKey(const Key('tray-presence-menu'))),
            t.getSize(find.byKey(const Key('native-presence'))),
          );
        } else {
          final expected = t
              .getSemantics(find.byKey(const Key('native-presence')))
              .getSemanticsData()
              .label;
          expect(expected, contains('在线'));
          expect(
            exposed(t, 'tray-presence-menu').getSemanticsData().label,
            expected,
          );
        }
      } finally {
        sem.dispose();
        await t.pumpWidget(const SizedBox());
        await t.pump();
        control.dispose();
        source.dispose();
      }
    });
  }
}
