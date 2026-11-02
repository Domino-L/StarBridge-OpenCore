import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3dh_test.dart' show HelpPendingPort;

Map<String, dynamic> history({bool empty = false, String suffix = ''}) => {
  'schemaVersion': 1,
  'edition': 'starbridge',
  'entries': [
    if (!empty)
      {
        'version': 'fixture',
        'title': 'Version title$suffix',
        'publishedOn': '2026-10-16',
        'summary': 'Release summary$suffix',
        'highlights': ['One', 'Two'],
      },
  ],
};
Finder get header => find
    .descendant(
      of: find.byType(SuiteExpander),
      matching: find.byType(SuitePressable),
    )
    .first;
Finder get reload =>
    find.byKey(const Key('help-read-reload-helpSupport.history'));

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final result in [
      'failure',
      'update',
      'remove-return',
      'leave-opening',
      'leave-closing',
    ]) {
      testWidgets(
        '$suite real history $result preserves read owner and entry state',
        (t) async {
          size(t, const Size(1000, 1400));
          final port = HelpPendingPort();
          await t.pumpWidget(
            scopedApp(
              HelpSupportReadCard(name: 'helpSupport.history', port: port),
              suite,
            ),
          );
          await t.pump();
          await t.pump();
          expect(port.reads, hasLength(1));
          port.reads.single.$2.complete(history());
          await t.pumpAndSettle();
          await t.tap(header);
          await t.pump(const Duration(milliseconds: 30));
          expect(port.reads, hasLength(1));
          if (result == 'leave-opening') {
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            return;
          }
          await t.pumpAndSettle();
          expect(find.text('Release summary'), findsOneWidget);
          if (result == 'leave-closing') {
            await t.tap(header);
            await t.pump(const Duration(milliseconds: 30));
            await t.pumpWidget(const SizedBox());
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            return;
          }
          await t.tap(reload);
          await t.pump();
          expect(port.reads, hasLength(2));
          expect(find.text('Release summary'), findsOneWidget);
          if (result == 'failure') {
            port.reads.last.$2.completeError(StateError('read rejected'));
            await t.pumpAndSettle();
            expect(find.text('Release summary'), findsOneWidget);
            expect(
              t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
              isTrue,
            );
          } else if (result == 'update') {
            port.reads.last.$2.complete(history(suffix: ' updated'));
            await t.pumpAndSettle();
            expect(find.text('Release summary updated'), findsOneWidget);
            expect(
              t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
              isTrue,
            );
          } else {
            port.reads.last.$2.complete(history(empty: true));
            await t.pumpAndSettle();
            expect(find.byType(SuiteExpander), findsNothing);
            await t.tap(reload);
            await t.pump();
            expect(port.reads, hasLength(3));
            port.reads.last.$2.complete(history());
            await t.pumpAndSettle();
            expect(
              t.widget<SuiteExpander>(find.byType(SuiteExpander)).expanded,
              isTrue,
            );
            expect(find.text('Release summary'), findsOneWidget);
          }
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}
