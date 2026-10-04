import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/runtime/sharing_status_monitor.dart';
import 'package:starbridge_flutter/app/shell/widgets/sharing_status_notice.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';
import 'package:starbridge_flutter/features/settings/sharing_status_presentation.dart';
import 'package:starbridge_flutter/app/localization/privacy_scope_settings_strings.dart';

import '../features/settings/local_privacy_page_test.dart' show app, viewport;
import 'sharing_status_notice_test.dart' show NoticePrivacy;
import '../features/friends/social_layout_test.dart' show capture, loadFonts;

void main() {
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
      await capture(tester, key, 'sharing-status-${width.toInt()}');
      await tester.pumpWidget(const SizedBox.shrink());
      for (final status in statuses) {
        status.dispose();
      }
    }
  });
  const cases = {
    'network_unavailable': 'network',
    'timeout': 'timeout',
    'server_error': 'server',
    'rate_limited': 'rateLimited',
    'consent_required': 'consent',
    'identity_pending': 'identityPending',
    'identity_unavailable': 'signIn',
    'forbidden': 'permission',
    'response_invalid': 'contract',
    'identity_required': 'identity',
  };
  test('evidence distinguishes causes and all three locales cover them', () {
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
      'reconnecting',
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
      expect(find.text('实时共享服务暂时异常'), findsOneWidget);
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
