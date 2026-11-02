import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_comms_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';

import '../../app/menu_overlay/menu_comms_maturity_test.dart' show fixture;
import '../../app/menu_overlay/menu_comms_list_layout_test.dart'
    show organization;
import '../../features/friends/social_layout_test.dart' show size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bw_test.dart' show frames;

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  late var suite = widget.suite;
  MenuCommsView view = fixture(history: false, count: 4);
  MenuFeatureView? org;
  bool light = false,
      reduce = false,
      active = false,
      embedded = true,
      orgSelected = false;
  final calls = <(String, String, InteractionSource)>[];
  final kinds = <String>[];
  var closes = 0;
  void change(VoidCallback fn) => setState(fn);
  @override
  Widget build(BuildContext context) => scopedApp(
    MenuCommsPanel(
      view: view,
      organization: org,
      active: active,
      embedded: embedded,
      organizationSelected: orgSelected,
      onAction: (a, k) => calls.add((a, k, currentStarBridgeActivationSource)),
      onOrganizationAction: (a, k) =>
          calls.add(('org:$a', k, currentStarBridgeActivationSource)),
      onConversationKind: kinds.add,
      onProfile: (k) =>
          calls.add(('profile', k, currentStarBridgeActivationSource)),
      onClose: () => closes++,
    ),
    suite,
    light: light,
    reduce: reduce,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  InteractionSuite suite, {
  Size viewport = const Size(1000, 900),
}) async {
  size(t, viewport);
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: key));
  await frames(t);
  return key.currentState!;
}

void main() {
  for (final suite in InteractionSuite.values) {
    for (final retired in ['idle', 'restricted']) {
      testWidgets(
        '$suite actual panel $retired resets native search and filter together',
        (t) async {
          final h = await mount(t, suite);
          await t.enterText(
            find.byKey(const ValueKey('menu-comms-search')),
            '北辰',
          );
          await frames(t);
          expect(
            find.byKey(const ValueKey('menu-conversation-c2')),
            findsNothing,
          );
          h.change(() => h.view = MenuCommsView(retired));
          await frames(t);
          h.change(() => h.view = fixture(history: false, count: 4));
          await frames(t);
          expect(
            find.byKey(const ValueKey('menu-conversation-c2')),
            findsOneWidget,
          );
          final editable = find.descendant(
            of: find.byKey(const ValueKey('menu-comms-search')),
            matching: find.byType(EditableText),
          );
          expect(t.widget<EditableText>(editable).controller.text, '');
          expect(h.calls, isEmpty);
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$suite actual panel retired organization scope does not retain old channel names',
      (t) async {
        final h = await mount(t, suite);
        h.change(() => h.org = organization());
        await frames(t);
        final oldRow = find.byKey(
          const ValueKey('menu-organization-conversation-远航者组织'),
        );
        expect(oldRow, findsOneWidget);
        h.change(() => h.org = const MenuFeatureView('loading', scope: 's2'));
        await frames(t);
        expect(oldRow, findsNothing);
        expect(h.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite actual panel same organization scope retains disabled channel during refresh',
      (t) async {
        final h = await mount(t, suite);
        final initial = organization();
        h.change(() => h.org = initial);
        await frames(t);
        h.change(
          () => h.org = MenuFeatureView('loading', scope: initial.scope),
        );
        await frames(t);
        final oldRow = find.byKey(
          const ValueKey('menu-organization-conversation-远航者组织'),
        );
        expect(oldRow, findsOneWidget);
        final target = find.ancestor(
          of: oldRow,
          matching: find.byType(StarBridgeActionRow),
        );
        expect(t.widget<StarBridgeActionRow>(target).onActivate, isNull);
        expect(h.calls, isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
}
