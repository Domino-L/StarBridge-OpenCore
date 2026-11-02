import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/onboarding/bridge_online_review_adapter.dart';
import 'package:starbridge_flutter/features/onboarding/online_installation_port.dart';
import 'package:starbridge_flutter/features/onboarding/online_restore_dialog.dart';
import 'package:starbridge_flutter/features/onboarding/online_review_port.dart';

import '../../app/tray_quick_panel_test.dart' show app;
import 'online_review_test_support.dart';
import 'retained_online_review_test.dart' show retainedWire;

OnlineInstallationSnapshot receipt(String state, {bool running = false}) =>
    OnlineInstallationSnapshot(
      revision: 3,
      phase: running
          ? OnlineInstallationPhase.running
          : OnlineInstallationPhase.completed,
      controlGeneration: 8,
      modeRevision: 4,
      modeState: state,
    );

class InstallationPort implements OnlineInstallationPort {
  @override
  bool supported = true;
  final revisions = <int>[], readRevisions = <int>[];
  final pending = Completer<OnlineInstallationSnapshot>();
  OnlineInstallationSnapshot observation = receipt('online');
  @override
  Future<OnlineInstallationSnapshot> install(int revision) {
    revisions.add(revision);
    return pending.future;
  }

  @override
  Future<OnlineInstallationSnapshot> read(int revision) async {
    readRevisions.add(revision);
    return observation;
  }
}

void main() {
  Future<Future<bool> Function()> open(
    WidgetTester tester,
    FakeOnlinePort review,
    InstallationPort port,
    Future<bool> Function() installed,
  ) async {
    Future<bool>? completed;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              completed = showOnlineRestoreDialog(
                context,
                review: review,
                installation: port,
                onInstalled: installed,
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return () => completed!;
  }

  FakeOnlinePort confirmed() =>
      FakeOnlinePort()
        ..snapshot = OnlineReviewWire.parse(reviewWire(confirmed: true));

  testWidgets(
    'failed restore keeps local result and shows a copyable bounded diagnostic',
    (tester) async {
      final review = confirmed(), port = InstallationPort();
      var refreshes = 0;
      await open(tester, review, port, () async {
        refreshes++;
        return true;
      });
      await tester.tap(find.byKey(const Key('online-restore-install')));
      port.pending.complete(
        const OnlineInstallationSnapshot(
          revision: 3,
          phase: OnlineInstallationPhase.completed,
          controlGeneration: 8,
          modeRevision: 4,
          modeState: 'offline',
          failure: OnlineInstallationFailure('configureBusiness', 'storage'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已返回本机模式'), findsOneWidget);
      expect(
        find.byKey(const Key('online-restore-diagnostic')),
        findsOneWidget,
      );
      expect(find.textContaining('configureBusiness/storage'), findsOneWidget);
      expect(refreshes, 0);
      expect(port.revisions, [3]);
      await tester.pumpWidget(const SizedBox());
      await review.close();
    },
  );

  testWidgets(
    'direct restore observes its original installation without replay',
    (tester) async {
      final review = FakeOnlinePort(), port = InstallationPort();
      Future<bool>? done;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () {
                done = showOnlineRestoreDialog(
                  context,
                  review: review,
                  installation: port,
                  onInstalled: () async => true,
                  installationRevision: 3,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(await done!, true);
      expect(port.readRevisions, [3]);
      expect(port.revisions, isEmpty);
      expect(review.actions, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await review.close();
    },
  );

  testWidgets('a retained account confirmed here can be installed', (
    tester,
  ) async {
    final review = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(
        retainedWire(state: 'accountConfirmedForHandoff'),
        retainedProtocol: true,
      );
    await open(tester, review, InstallationPort(), () async => true);
    expect(find.byKey(const Key('online-restore-install')), findsOneWidget);
    await tester.tap(find.byKey(const Key('online-restore-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await review.close();
  });

  testWidgets('an unverified retained account has nothing to install', (
    tester,
  ) async {
    final review = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(
        retainedWire(state: 'verificationRequired'),
        retainedProtocol: true,
      );
    await open(tester, review, InstallationPort(), () async => true);
    expect(find.byKey(const Key('online-restore-install')), findsNothing);
    await tester.tap(find.byKey(const Key('online-restore-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await review.close();
  });

  testWidgets('opening and identity confirmation never install automatically', (
    tester,
  ) async {
    final review = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(reviewWire());
    final port = InstallationPort();
    var refreshed = 0;
    await open(tester, review, port, () async {
      refreshed++;
      return true;
    });
    expect(port.revisions, isEmpty);
    expect(find.byKey(const Key('online-restore-install')), findsNothing);
    await tester.tap(find.byKey(const Key('online-review-confirm')));
    await tester.pumpAndSettle();
    expect(review.actions, [OnlineReviewAction.confirm]);
    expect(port.revisions, isEmpty);
    await tester.tap(find.byKey(const Key('online-restore-install')));
    await tester.pumpAndSettle();
    expect(port.revisions, [3]);
    expect(refreshed, 0);
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('online-restore-recheck')))
          .onPressed,
      isNull,
    );
    port.pending.complete(receipt('online'));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await review.close();
  });

  testWidgets(
    'unknown outcome rechecks read-only and waits for fresh account confirmation',
    (tester) async {
      final review = confirmed(), port = InstallationPort();
      var refreshed = 0, accept = false;
      final done = await open(tester, review, port, () async {
        refreshed++;
        return accept;
      });
      await tester.tap(find.byKey(const Key('online-restore-install')));
      port.pending.completeError(TimeoutException('Observer wait expired'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未确认恢复结果'), findsOneWidget);
      await tester.tap(find.byKey(const Key('online-restore-recheck')));
      await tester.pumpAndSettle();
      expect(port.revisions, [3]);
      expect(port.readRevisions, [3]);
      expect(refreshed, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      accept = true;
      await tester.tap(find.byKey(const Key('online-restore-recheck')));
      await tester.pumpAndSettle();
      expect(await done(), true);
      expect(port.revisions, [3]);
      expect(port.readRevisions, [3, 3]);
      await tester.pumpWidget(const SizedBox());
      await review.close();
    },
  );

  for (final state in [
    'local',
    'offline',
    'recoveryRequired',
    'signInRequired',
  ]) {
    testWidgets(
      'completed $state does not announce online or replay installation',
      (tester) async {
        final review = confirmed(), port = InstallationPort();
        var refreshed = 0;
        await open(tester, review, port, () async {
          refreshed++;
          return true;
        });
        await tester.tap(find.byKey(const Key('online-restore-install')));
        port.pending.complete(receipt(state));
        port.observation = receipt(state);
        await tester.pumpAndSettle();
        if (state == 'signInRequired') {
          expect(find.textContaining('已返回本机模式'), findsNothing);
        }
        expect(refreshed, 0);
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.byKey(const Key('online-restore-recheck')));
        await tester.pumpAndSettle();
        expect(refreshed, 0);
        expect(port.revisions, [3]);
        expect(port.readRevisions, [3]);
        await tester.tap(find.byKey(const Key('online-restore-close')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        await review.close();
      },
    );
  }
  testWidgets('running physical task is polled, never installed twice', (
    tester,
  ) async {
    final review = confirmed(), port = InstallationPort();
    var refreshed = 0;
    await open(tester, review, port, () async {
      refreshed++;
      return true;
    });
    await tester.tap(find.byKey(const Key('online-restore-install')));
    port.pending.complete(receipt('switching', running: true));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(port.revisions, [3]);
    expect(port.readRevisions, [3]);
    expect(refreshed, 1);
    await tester.pumpWidget(const SizedBox());
    await review.close();
  });
  testWidgets('closing reviewed identity cancels review without installing', (
    tester,
  ) async {
    final review = FakeOnlinePort()
      ..snapshot = OnlineReviewWire.parse(reviewWire());
    final port = InstallationPort();
    final done = await open(tester, review, port, () async => true);
    await tester.tap(find.byKey(const Key('online-restore-close')));
    await tester.pumpAndSettle();
    expect(review.actions, [OnlineReviewAction.cancel]);
    expect(port.revisions, isEmpty);
    expect(await done(), false);
    await tester.pumpWidget(const SizedBox());
    await review.close();
  });
}
