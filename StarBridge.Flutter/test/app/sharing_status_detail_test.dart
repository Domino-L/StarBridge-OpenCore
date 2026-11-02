import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/privacy_live_sharing_panel.dart';
import 'package:starbridge_flutter/features/settings/sharing_status_presentation.dart';
import 'package:starbridge_flutter/app/localization/privacy_scope_settings_strings.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;
import 'sharing_status_notice_test.dart' show NoticePrivacy;
import '../features/friends/social_layout_test.dart' show loadFonts;

Future<void> captureSharing(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  final directory = Platform.environment['STARBRIDGE_TEST_VISUAL_DIR'];
  if (directory == null || directory.isEmpty) return;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  for (final code in ['privacy_local.owner_unavailable', 'privacy_local.read_unavailable']) {
    testWidgets('temporary local policy recovers without save $code', (tester) async {
      final port = NoticePrivacy()..state = 'failed'..errorCode = code;
      final controller = LocalPrivacyController(port);
      final monitor = SharingStatusMonitor(controller: controller);
      await tester.pumpWidget(app(SharingStatusNotice(status: monitor, onOpenSettings: () {})));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 31)); await tester.pumpAndSettle();
      expect(monitor.value, 'localRecovering');
      expect(find.text('正在重新读取共享设置'), findsOneWidget);
      port.state = 'applied'; port.errorCode = null;
      await tester.pump(const Duration(seconds: 61)); await tester.pumpAndSettle();
      expect(monitor.value, isNull);
      expect(find.text('正在重新读取共享设置'), findsNothing);
      expect(port.writes, 0); expect(port.actions.where((a) => a == 'apply'), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink()); monitor.dispose(); controller.dispose();
    });
  }
  for (final observation in ['null', '0']) {
    testWidgets(
      'app-only empty Handle disconnect $observation shows network issue',
      (tester) async {
        // Matches the Host projection after app-only positive input disappears.
        final port = NoticePrivacy()
          ..state = 'reconnecting'
          ..errorCode = 'privacy_publication.network_unavailable';
        final controller = LocalPrivacyController(port);
        final monitor = SharingStatusMonitor(controller: controller);
        await tester.pumpWidget(
          app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
        );
        await tester.pumpAndSettle();
        // Shell retains its existing 30-second recovery grace period.
        await tester.pump(const Duration(seconds: 31));
        await tester.pumpAndSettle();
        expect(
          find.text(
            simplifiedPrivacyScopeSettingsStrings['privacy.notice.network.title']!,
          ),
          findsOneWidget,
        );
        expect(sharingStatusIssue(controller.publicationView, 1), 'network');
        expect(find.textContaining('等待身份'), findsNothing);
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: PrivacyLiveSharingPanel(controller: controller),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('网络'), findsWidgets);
        expect(find.textContaining('等待身份'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        monitor.dispose();
        controller.dispose();
      },
    );
  }
  testWidgets('identity notice stays through the Host publish attempts', (
    tester,
  ) async {
    final port = NoticePrivacy()..state = 'identityRequired';
    final controller = LocalPrivacyController(port);
    final monitor = SharingStatusMonitor(controller: controller);
    var changes = 0;
    monitor.addListener(() => changes++);
    await tester.pumpWidget(
      app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
    );
    await tester.pumpAndSettle();
    expect(monitor.value, 'identity');
    changes = 0;
    Future<void> read(String state) async {
      port.state = state;
      // Inside the fake clock, so the monitor's grace timer follows pump.
      final done = controller.refreshPublication();
      await tester.pump();
      await done;
    }

    for (var round = 0; round < 4; round++) {
      await read('publishing');
      expect(monitor.value, 'identity');
      await tester.pump(const Duration(seconds: 3));
      await read('identityRequired');
      expect(monitor.value, 'identity');
      await tester.pump(const Duration(seconds: 3));
    }
    expect(changes, 0);
    expect(find.byKey(const Key('sharing-status-notice')), findsOneWidget);

    // A publish that never ends is still reported after the usual grace.
    await read('publishing');
    await tester.pump(const Duration(seconds: 16));
    expect(monitor.value, 'waiting');

    // Confirmed sharing ends the notice.
    port.errorCode = null;
    await read('applied');
    expect(monitor.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    controller.dispose();
  });
  testWidgets('a first publish still waits out its grace without a notice', (
    tester,
  ) async {
    final port = NoticePrivacy()..state = 'publishing';
    final controller = LocalPrivacyController(port);
    final monitor = SharingStatusMonitor(controller: controller);
    await tester.pumpWidget(
      app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
    );
    await tester.pumpAndSettle();
    expect(monitor.value, isNull);
    await tester.pump(const Duration(seconds: 16));
    expect(monitor.value, 'waiting');
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    controller.dispose();
  });
  test(
    'exhausted authentication recovery requires sign-in, not network retry',
    () {
      for (final code in [
        'privacy_publication.identity_unavailable',
        'account.reauthorization_required',
      ]) {
        expect(
          sharingStatusIssue(
            PrivacyPublicationView('identityRequired', errorCode: code),
            1,
          ),
          'signIn',
        );
      }
    },
  );
  for (final (locale, strings) in [
    (const Locale('zh', 'CN'), simplifiedPrivacyScopeSettingsStrings),
    (const Locale('zh', 'TW'), traditionalPrivacyScopeSettingsStrings),
    (const Locale('en'), englishPrivacyScopeSettingsStrings),
  ]) {
    testWidgets('non-auth retry keeps its specific cause in $locale', (
      tester,
    ) async {
      for (final (code, issue) in [
        ('forbidden', 'permission'),
        ('response_invalid', 'contract'),
        ('unavailable', 'service'),
        ('route_retired', 'retired'),
      ]) {
        final port = NoticePrivacy()
          ..state = code == 'route_retired' ? 'failed' : 'reconnecting'
          ..errorCode = 'privacy_publication.$code';
        final controller = LocalPrivacyController(port);
        final monitor = SharingStatusMonitor(controller: controller);
        await tester.pumpWidget(
          app(
            SharingStatusNotice(status: monitor, onOpenSettings: () {}),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(strings['privacy.notice.$issue.title']!),
          findsOneWidget,
        );
        expect(
          find.text(strings['privacy.notice.$issue.body']!),
          findsOneWidget,
        );
        expect(
          find.text(strings['privacy.notice.network.title']!),
          findsNothing,
        );
        expect(
          find.text(strings['privacy.notice.signIn.title']!),
          findsNothing,
        );
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              child: PrivacyLiveSharingPanel(controller: controller),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(strings['privacy.notice.$issue.title']!),
          findsOneWidget,
        );
        expect(
          find.text(strings['privacy.notice.$issue.body']!),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        monitor.dispose();
        controller.dispose();
      }
    });
    testWidgets('identityRequired shows automatic resume copy in $locale', (
      tester,
    ) async {
      final port = NoticePrivacy()
        ..state = 'identityRequired'
        ..errorCode = 'privacy_publication.identity_unavailable';
      final controller = LocalPrivacyController(port);
      final monitor = SharingStatusMonitor(controller: controller);
      await tester.pumpWidget(
        app(
          SharingStatusNotice(status: monitor, onOpenSettings: () {}),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(strings['privacy.notice.signIn.title']!),
        findsOneWidget,
      );
      expect(find.text(strings['privacy.notice.signIn.body']!), findsOneWidget);
      expect(find.text(strings['privacy.notice.network.title']!), findsNothing);
      expect(port.actions.where((action) => action == 'apply'), isEmpty);
      await tester.pumpWidget(
        app(
          SingleChildScrollView(
            child: PrivacyLiveSharingPanel(controller: controller),
          ),
          locale: locale,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(strings['privacy.notice.signIn.title']!),
        findsOneWidget,
      );
      expect(find.text(strings['privacy.notice.signIn.body']!), findsOneWidget);
      expect(
        find.text(strings['privacy.scope.live.identityRequired']!),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      controller.dispose();
    });
  }
  testWidgets('isolated notice visual review at both acceptance widths', (
    tester,
  ) async {
    await loadFonts();
    for (final width in [1280.0, 1440.0]) {
      viewport(tester, Size(width, 900));
      final key = GlobalKey();
      final statuses = [
        'network',
        'timeout',
        'server',
        'rateLimited',
        'consent',
        'statusRead',
        'withdrawal',
      ].map((issue) => ValueNotifier<String?>(issue)).toList();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Padding(
              padding: const EdgeInsets.only(left: 224),
              child: Column(
                children: [
                  const Text('状态组件独立样例（实际客户端同一时间仅显示一条）'),
                  for (final status in statuses) ...[
                    const SizedBox(height: 24),
                    SharingStatusNotice(
                      status: status,
                      onOpenSettings: () {},
                      onRetry: () => () {},
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await captureSharing(tester, key, 'sharing-status-${width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      for (final status in statuses) {
        status.dispose();
      }
    }
  });
  const cases = {
    'network_unavailable': 'network',
    'timeout': 'network',
    'server_error': 'network',
    'rate_limited': 'network',
    'consent_required': 'consent',
    'identity_pending': 'identityPending',
    'identity_unavailable': 'reconnecting',
    'forbidden': 'permission',
    'response_invalid': 'contract',
    'rejected': 'rejected',
    'unavailable': 'service',
    'route_retired': 'retired',
    'identity_required': 'identity',
  };
  test('evidence distinguishes causes and all three locales cover them', () {
    expect(
      sharingStatusIssue(const PrivacyPublicationView('withdrawn'), 4),
      'paused',
    );
    expect(
      sharingStatusIssue(
        const PrivacyPublicationView(
          'reconnecting',
          errorCode: 'account.reauthorization_required',
        ),
        4,
      ),
      'reconnecting',
    );
    for (final entry in cases.entries) {
      expect(
        sharingStatusIssue(
          PrivacyPublicationView(
            'reconnecting',
            errorCode: 'privacy_publication.${entry.key}',
          ),
          4,
        ),
        entry.value,
      );
    }
    expect(
      sharingStatusIssue(
        const PrivacyPublicationView('reconnecting', errorCode: 'unknown'),
        4,
      ),
      'service',
    );
    expect(
      sharingStatusIssue(
        const PrivacyPublicationView('failed', errorCode: 'unknown'),
        4,
      ),
      'failed',
    );
    for (final strings in [
      simplifiedPrivacyScopeSettingsStrings,
      traditionalPrivacyScopeSettingsStrings,
      englishPrivacyScopeSettingsStrings,
    ]) {
      for (final issue in {
        ...cases.values,
        'statusRead',
        'withdrawal',
        'local',
      }) {
        expect(strings['privacy.notice.$issue.title'], isNotEmpty);
        expect(strings['privacy.notice.$issue.body'], isNotEmpty);
      }
    }
  });

  testWidgets(
    'transient server failure stays silent; persistent cause is clear and recovers',
    (tester) async {
      viewport(tester, const Size(430, 900));
      final port = NoticePrivacy()..state = 'applied';
      final c = LocalPrivacyController(port);
      final monitor = SharingStatusMonitor(controller: c);
      await tester.pumpWidget(
        app(
          SharingStatusNotice(status: monitor, onOpenSettings: () {}),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      port
        ..state = 'reconnecting'
        ..errorCode = 'privacy_publication.server_error';
      await c.refreshPublication();
      await tester.pump(const Duration(seconds: 6));
      expect(monitor.value, isNull);
      port.state = 'applied';
      await c.refreshPublication();
      await tester.pump(const Duration(seconds: 31));
      expect(monitor.value, isNull);
      port.state = 'reconnecting';
      await c.refreshPublication();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('网络问题'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(port.actions.every((a) => a == 'status'), isTrue);
      port.state = 'applied';
      await c.refreshPublication();
      await tester.pumpAndSettle();
      expect(monitor.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      c.dispose();
    },
  );

  testWidgets('withdrawal stays automatic, and failed read retry only reads', (
    tester,
  ) async {
    final port = NoticePrivacy()..state = 'withdrawalPending';
    final c = LocalPrivacyController(port);
    final monitor = SharingStatusMonitor(controller: c);
    await tester.pumpWidget(
      app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
    );
    await tester.pumpAndSettle();
    expect(monitor.value, 'withdrawal');
    expect(monitor.canRetry, isFalse);
    await monitor.retry();
    expect(port.actions.where((a) => a == 'stop'), isEmpty);
    expect(port.actions.where((a) => a == 'apply'), isEmpty);
    port.failStatus = true;
    await c.refreshPublication();
    await c.refreshPublication();
    expect(monitor.value, 'statusRead');
    final prior = port.actions.length;
    await monitor.retry();
    expect(port.actions.skip(prior), ['status']);
    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    c.dispose();
  });

  testWidgets(
    'consent is never inferred by polling and account switch clears reason',
    (tester) async {
      final port = NoticePrivacy()
        ..errorCode = 'privacy_publication.consent_required';
      final c = LocalPrivacyController(port);
      final monitor = SharingStatusMonitor(controller: c);
      await tester.pumpWidget(
        app(SharingStatusNotice(status: monitor, onOpenSettings: () {})),
      );
      await tester.pumpAndSettle();
      expect(monitor.value, 'consent');
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpAndSettle();
      expect(port.actions.every((a) => a == 'status'), isTrue);
      c.edit(c.draft!.copyWith(publicationEnabled: false));
      expect(monitor.canRetry, isFalse);
      await monitor.retry();
      expect(port.actions.every((a) => a == 'status'), isTrue);
      port.state = 'applied';
      port.errorCode = null;
      port.events.add(null);
      await tester.pumpAndSettle();
      expect(monitor.value, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      c.dispose();
    },
  );
}

