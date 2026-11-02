import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_filter_panel.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ai_test.dart' show reveal, checkbox;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual Tab exits expanded groups and Enter opens targets without applying',
      (t) async {
        final applied = <String>[];
        try {
          await mount(
            t,
            CommunityFilterPanel(onApply: applied.add),
            suite,
            width: 520,
          );
          final header = find.byKey(const ValueKey('org-filter-targets'));
          await reveal(t, header);
          Finder expander() =>
              find.descendant(of: header, matching: find.byType(SuiteExpander));
          expect(expander(), findsOneWidget);
          expect(t.widget<SuiteExpander>(expander()).expanded, isFalse);
          var reached = false;
          final trace = <String>[];
          // Never requestFocus: this proves actual reachability from the route.
          // Resolve the current public owner after each Tab, since a lazy list
          // may legitimately retire and recreate offscreen headers.
          for (var step = 1; step <= 48; step++) {
            await t.sendKeyEvent(LogicalKeyboardKey.tab);
            await t.pump();
            await t.pump();
            final primary = FocusManager.instance.primaryFocus;
            final current = expander().evaluate().isEmpty
                ? null
                : t.widget<SuiteExpander>(expander()).focusNode;
            trace.add(
              '$step: ${primary?.debugLabel} scope=${primary?.enclosingScope?.debugLabel} edge=${primary?.enclosingScope?.traversalEdgeBehavior} target=${identical(primary, current)}',
            );
            if (current != null && identical(primary, current)) {
              reached = true;
              expect(current.hasPrimaryFocus, isTrue);
              break;
            }
          }
          expect(reached, isTrue, reason: trace.join('\n'));
          expect(t.widget<SuiteExpander>(expander()).expanded, isFalse);
          expect(applied, isEmpty);
          await t.sendKeyEvent(LogicalKeyboardKey.enter);
          await t.pump();
          await t.pump();
          expect(t.widget<SuiteExpander>(expander()).expanded, isTrue);
          final option = checkbox(
            const ValueKey('community-filter-targets-所有玩家'),
          );
          expect(option.hitTestable(), findsOneWidget);
          expect(t.getRect(option).height, greaterThan(0));
          expect(applied, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await settleCommunityImages(t);
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
