import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_flutter/features/settings/in_memory_sync_privacy_adapter.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_settings_page.dart';
import 'package:starbridge_flutter/features/settings/sync_privacy_module.dart';

import '../../features/settings/privacy_publication_recovery_ui_test.dart'
    as original;
import 'interaction_batch3do_test.dart' as fixture;
import 'interaction_batch3dr_test.dart';

class RecoveringPort extends original.RecoveryPrivacy {
  Completer<PrivacyPublicationView>? pending;
  bool readFails = false;
  final requests = <String>[];
  @override
  Future<PrivacyPublicationView> publication(String action, {int? revision}) {
    requests.add(action);
    if (readFails && action == 'status') {
      return Future.error(StateError('synthetic status unavailable'));
    }
    return pending?.future ?? super.publication(action, revision: revision);
  }
}

void main() {
  setUpAll(fixture.loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final readStatus in [false, true]) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $source embedded recovery readStatus=$readStatus keeps pending visible and preserves original writes',
          (t) async {
            fixture.size(t, const Size(1000, 900));
            final semantics = t.ensureSemantics();
            final p = RecoveringPort();
            final c = LocalPrivacyController(p);
            final sync = createSyncPrivacyModule(
              InMemorySyncPrivacyAdapter.forReview(),
            );
            await sync.initialize();
            final pending = Completer<PrivacyPublicationView>();
            try {
              await t.pumpWidget(
                editorApp(
                  PrivacySettingsPage(localPrivacy: c, syncPrivacy: sync),
                  suite,
                ),
              );
              await editorFrames(t);
              if (readStatus) {
                p.readFails = true;
                await c.refreshPublication();
                await c.refreshPublication();
                p.readFails = false;
                await t.pump();
              }
              final saved = c.draft;
              final before = p.requests.length;
              p.pending = pending;
              await editorAct(t, 'privacy-reapply', source);
              await editorFrames(t, 2);
              expect(p.requests.skip(before), [
                readStatus ? 'status' : 'apply',
              ]);
              expect(p.writes, 0);
              expect(c.draft, same(saved));
              expect(c.dirty, isFalse);
              expect(find.byType(HelpSupportWaiting), findsOneWidget);
              final wait = find.byType(HelpSupportWaiting);
              final rect = t.getRect(wait);
              expect(rect.top, greaterThanOrEqualTo(0));
              expect(rect.bottom, lessThanOrEqualTo(900));
              expect(
                t.widget<HelpSupportWaiting>(wait).source,
                source == 'pointer'
                    ? InteractionSource.pointer
                    : InteractionSource.keyboard,
              );
              expect(
                find.byType(SuiteProgressBar),
                source == 'pointer' ? findsOneWidget : findsNothing,
              );
              pending.complete(
                PrivacyPublicationView('applied', revision: c.revision),
              );
              await editorFrames(t);
              expect(find.byType(HelpSupportWaiting), findsNothing);
              expect(c.publicationView.state, 'applied');
              expect(p.writes, 0);
              expect(c.draft, same(saved));
              expect(t.takeException(), isNull);
            } finally {
              if (!pending.isCompleted) {
                pending.complete(const PrivacyPublicationView('inactive'));
              }
              await t.pumpWidget(const SizedBox.shrink());
              await editorFrames(t, 2);
              c.dispose();
              sync.dispose();
              semantics.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
    }
  }
}
