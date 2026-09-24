import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/app/presence/manual_presence.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import '../features/settings/local_privacy_page_test.dart'
    show app, PublishingPrivacy, viewport;

void main() {
  testWidgets(
    'global notice appears outside editor, polls without writes, clears on recovery',
    (tester) async {
      final port = NoticePrivacy();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      final monitor = SharingStatusMonitor(controller: c);
      var monitorDisposed = false;
      addTearDown(() {
        if (!monitorDisposed) monitor.dispose();
      });
      var opens = 0;
      await tester.pumpWidget(
        app(
          Column(
            children: [
              SharingStatusNotice(
                status: monitor,
                onOpenSettings: () => opens++,
              ),
              const Text('home workspace'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);
      expect(find.text('实时共享未生效'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sharing-status-settings')));
      await tester.pumpAndSettle();
      expect(opens, 1);
      var repeatedAnnouncements = 0;
      monitor.addListener(() => repeatedAnnouncements++);
      c.open();
      c.closeEditor();
      final reads = port.actions.length;
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(port.actions.length, greaterThan(reads));
      expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);
      expect(repeatedAnnouncements, 0);
      port.state = 'applied';
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      expect(port.actions.every((a) => a == 'status'), isTrue);
      expect(port.writes, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      monitorDisposed = true;
      final stoppedReads = port.actions.length;
      await tester.pump(const Duration(seconds: 20));
      expect(port.actions.length, stoppedReads);
    },
  );

  testWidgets(
    'saved choice not draft controls warnings and invisible is intentional',
    (tester) async {
      final port = NoticePrivacy()..state = 'failed';
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      final source = ValueNotifier(
        const ManualPresenceSnapshot(
          scope: 'fixture',
          confirmedMode: PresenceVisibility.invisible,
        ),
      );
      final presence = ManualPresenceController(source: source);
      addTearDown(presence.dispose);
      addTearDown(source.dispose);
      final monitor = SharingStatusMonitor(controller: c, presence: presence);
      await tester.pumpWidget(
        app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      source.value = const ManualPresenceSnapshot(
        scope: 'fixture',
        confirmedMode: PresenceVisibility.online,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);
      c.edit(c.draft!.copyWith(publicationEnabled: false));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);
      port.snapshot = LocalPrivacySnapshot(revision: 5, settings: c.draft);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
    },
  );

  testWidgets(
    'brief startup and sending do not alert, sustained waiting does',
    (tester) async {
      final port = NoticePrivacy()..state = 'publishing';
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      final monitor = SharingStatusMonitor(controller: c);
      await tester.pumpWidget(
        app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      port.state = 'pending';
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);
      port.state = 'applied';
      await c.refreshPublication();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
    },
  );

  testWidgets('notice fits narrow enlarged text and account change clears it', (
    tester,
  ) async {
    viewport(tester, const Size(430, 900));
    final port = NoticePrivacy()..state = 'identityRequired';
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    final monitor = SharingStatusMonitor(controller: c);
    await tester.pumpWidget(
      app(
        SharingStatusNotice(status: monitor, onOpenSettings: () {}),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('实时共享等待身份确认'), findsOneWidget);
    expect(tester.takeException(), isNull);
    port.snapshot = const LocalPrivacySnapshot(revision: 0);
    port.events.add(null);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
  });

  testWidgets('old applied revision and status-read failure are not success', (
    tester,
  ) async {
    final port = NoticePrivacy()
      ..state = 'applied'
      ..reportedRevision = 3;
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    final monitor = SharingStatusMonitor(controller: c);
    await tester.pumpWidget(
      app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('实时共享未生效'), findsOneWidget);
    port.failStatus = true;
    await c.refreshPublication();
    await tester.pumpAndSettle();
    expect(find.text('实时共享异常'), findsOneWidget);
    port
      ..failStatus = false
      ..reportedRevision = 4;
    await c.refreshPublication();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sharing-status-notice')), findsNothing);
    expect(port.actions.every((a) => a == 'status'), isTrue);
    expect(port.writes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
  });
}

class NoticePrivacy extends PublishingPrivacy {
  NoticePrivacy() {
    snapshot = LocalPrivacySnapshot(
      revision: 4,
      settings: LocalPrivacySettings.editorDefaults.copyWith(
        publicationEnabled: true,
      ),
    );
  }
  String state = 'inactive';
  int? reportedRevision;
  bool failStatus = false;
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    actions.add(action);
    if (failStatus) throw StateError('fixture status unavailable');
    return PrivacyPublicationView(
      state,
      revision: reportedRevision ?? revision,
    );
  }
}
