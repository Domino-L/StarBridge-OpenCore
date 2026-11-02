import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:ui' show SemanticsAction;

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_expansion_tile.dart';
import 'package:starbridge_flutter/features/settings/help_support_disclosure.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dh_test.dart' show HelpPendingPort;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite actual colored disclosure uses approved expander', (
      t,
    ) async {
      size(t, const Size(800, 900));
      await t.pumpWidget(
        scopedApp(
          const HelpSupportDisclosureCard(
            titleKey: 'help.log.catalog',
            bodyKey: 'help.log.troubleshoot.body',
            accent: Colors.cyan,
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(StarBridgeExpansionTile), findsOneWidget);
      expect(find.byType(SuiteExpander), findsOneWidget);
      expect(find.byType(ExpansionTile), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
    for (final source in ['keyboard', 'reader']) {
      testWidgets(
        '$suite colored disclosure $source opens and closes immediately',
        (t) async {
          size(t, const Size(800, 1000));
          final semantics = t.ensureSemantics();
          await t.pumpWidget(
            scopedApp(
              const HelpSupportDisclosureCard(
                titleKey: 'help.log.catalog',
                bodyKey: 'help.log.troubleshoot.body',
                accent: Colors.cyan,
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          Future<void> activate() async {
            final header = find
                .descendant(
                  of: find.byType(SuiteExpander),
                  matching: find.byType(SuitePressable),
                )
                .first;
            if (source == 'keyboard') {
              t.widget<SuitePressable>(header).focusNode!.requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.enter);
            } else {
              final node = t.getSemantics(header);
              t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
                node.id,
                SemanticsAction.tap,
              );
            }
            await t.pump();
          }

          await activate();
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isTrue,
          );
          expect(t.hasRunningAnimations, isFalse);
          await activate();
          expect(
            t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
            isFalse,
          );
          expect(t.hasRunningAnimations, isFalse);
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
    testWidgets(
      '$suite rapid pointer toggles retain latest target and reduced motion interrupts',
      (t) async {
        size(t, const Size(800, 1100));
        var reduce = false;
        Widget app() => scopedApp(
          const HelpSupportDisclosureCard(
            titleKey: 'help.log.catalog',
            bodyKey: 'help.log.troubleshoot.body',
            accent: Colors.cyan,
          ),
          suite,
          reduce: reduce,
        );
        await t.pumpWidget(app());
        await t.pumpAndSettle();
        Finder header() => find
            .descendant(
              of: find.byType(SuiteExpander),
              matching: find.byType(SuitePressable),
            )
            .first;
        for (var i = 0; i < 5; i++) {
          await t.tap(header());
          await t.pump(const Duration(milliseconds: 30));
        }
        expect(
          t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
          isTrue,
        );
        reduce = true;
        await t.pumpWidget(app());
        await t.pump();
        expect(t.hasRunningAnimations, isFalse);
        await t.tap(header());
        await t.pump();
        expect(
          t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
          isFalse,
        );
        expect(t.hasRunningAnimations, isFalse);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite actual release retains entry identity and suite body', (
      t,
    ) async {
      size(t, const Size(800, 900));
      final port = HelpPendingPort();
      await t.pumpWidget(
        scopedApp(
          HelpSupportReadCard(name: 'helpSupport.history', port: port),
          suite,
        ),
      );
      await t.pump();
      await t.pump();
      port.reads.single.$2.complete({
        'schemaVersion': 1,
        'edition': 'starbridge',
        'entries': [
          {
            'version': 'fixture',
            'title': 'Version title',
            'publishedOn': '2026-10-15',
            'summary': 'Release summary',
            'highlights': ['One', 'Two'],
          },
        ],
      });
      await t.pumpAndSettle();
      expect(find.byType(SuiteExpander), findsOneWidget);
      expect(
        find.byKey(const PageStorageKey('release-fixture')),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
