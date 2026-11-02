import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_passive_count.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_feedback_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

const update = <String, dynamic>{
  'schemaVersion': 1,
  'state': 'up-to-date',
  'currentVersion': 'fixture',
};
Map<String, dynamic> stats([Object? accounts = 4]) => {
  'schemaVersion': 1,
  'downloadCount': 9,
  'onlineUserCount': 3,
  'registeredAccountCount': accounts,
  'fleetCount': 2,
  'overlayUsageSeconds': 3600,
  'updatedAt': '2026-10-15T00:00:00Z',
};

class HelpPendingPort implements HelpSupportPort {
  final reads = <(String, Completer<Map<String, dynamic>>)>[];
  final sends = <(String, String, Completer<void>)>[];
  @override
  Future<Map<String, dynamic>> read(String name) {
    final reply = Completer<Map<String, dynamic>>();
    reads.add((name, reply));
    return reply.future;
  }

  @override
  Future<void> send(String contact, String message) {
    final reply = Completer<void>();
    sends.add((contact, message, reply));
    return reply.future;
  }
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite feedback retains native editors under approved frames and action',
      (t) async {
        size(t, const Size(1400, 1100));
        final message = TextEditingController(),
            contact = TextEditingController();
        try {
          await t.pumpWidget(
            scopedApp(
              HelpSupportFeedbackForm(message: message, contact: contact),
              suite,
            ),
          );
          await t.pumpAndSettle();
          for (final id in ['help-feedback-message', 'help-feedback-contact']) {
            expect(
              find.ancestor(
                of: find.byKey(Key(id)),
                matching: find.byType(StarBridgeFieldFrame),
              ),
              findsOneWidget,
            );
          }
          expect(
            find.ancestor(
              of: find.byKey(const Key('help-feedback-send')),
              matching: find.byType(StarBridgeActionButton),
            ),
            findsOneWidget,
          );
        } finally {
          await t.pumpWidget(const SizedBox());
          message.dispose();
          contact.dispose();
        }
      },
    );
    testWidgets(
      '$suite actual read card has approved initial pending and reload action',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpPendingPort();
        await t.pumpWidget(
          scopedApp(
            HelpSupportReadCard(name: 'applicationUpdates.check', port: port),
            suite,
          ),
        );
        await t.pump();
        await t.pump();
        expect(port.reads, hasLength(1));
        expect(find.byType(SuiteProgressBar), findsOneWidget);
        expect(
          find.byKey(const Key('help-read-reload-applicationUpdates.check')),
          findsOneWidget,
        );
        port.reads.single.$2.complete(update);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$suite read-only stats use passive count without fabricating unknown',
      (t) async {
        size(t, const Size(1400, 1100));
        final port = HelpPendingPort();
        await t.pumpWidget(
          scopedApp(
            HelpSupportReadCard(name: 'helpSupport.stats', port: port),
            suite,
          ),
        );
        await t.pump();
        port.reads.single.$2.complete(stats(null));
        await t.pumpAndSettle();
        expect(find.byType(StarBridgePassiveCount), findsNWidgets(4));
        expect(find.text('暂不可用'), findsOneWidget);
        expect(find.text('1.0'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets('$suite support-group copy uses approved active feedback', (
      t,
    ) async {
      size(t, const Size(1400, 1100));
      await t.pumpWidget(
        scopedApp(
          const HelpSupportFeedbackContent(
            heading: SizedBox(),
            unavailableNotice: SizedBox(),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.ancestor(
          of: find.byKey(const Key('help-copy-feedback-group')),
          matching: find.byType(StarBridgeActionButton),
        ),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
