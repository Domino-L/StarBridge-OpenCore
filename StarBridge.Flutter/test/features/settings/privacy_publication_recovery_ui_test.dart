import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_controller.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_page.dart';
import 'package:starbridge_flutter/features/settings/local_privacy_settings.dart';
import 'package:starbridge_flutter/features/settings/privacy_publication_port.dart';

import 'local_privacy_page_test.dart' show app, viewport, PublishingPrivacy;

void main() {
  for (final code in [
    'privacy_publication.forbidden',
    'unexpected private body',
  ]) {
    testWidgets('failure feedback is curated rather than raw: $code', (
      tester,
    ) async {
      final port = RecoveryPrivacy()..failureCode = code;
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text(code), findsNothing);
      expect(
        find.text(
          code.endsWith('forbidden')
              ? '服务器未允许此次共享，请确认账号权限后重试。'
              : '未能确认共享结果，请检查连接后重试。',
        ),
        findsOneWidget,
      );
      expect(port.actions.where((a) => a == 'apply'), isEmpty);
    });
  }
  testWidgets(
    'saved enabled but inactive offers explicit recovery, never auto applies',
    (tester) async {
      final port = RecoveryPrivacy();
      final c = LocalPrivacyController(port);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
      await tester.pumpAndSettle();
      expect(find.text('共享尚未运行。已保存的范围保持不变，可重新应用。'), findsOneWidget);
      expect(port.actions.where((a) => a == 'apply'), isEmpty);
      final saved = port.snapshot;
      final retry = find.byKey(const Key('privacy-reapply'));
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(port.actions.where((a) => a == 'apply'), hasLength(1));
      expect(port.writes, 0);
      expect(identical(port.snapshot, saved), isTrue);
      expect(find.text('共享已生效'), findsOneWidget);
      expect(retry, findsNothing);
    },
  );

  testWidgets('dirty draft cannot be applied by recovery', (tester) async {
    final port = RecoveryPrivacy();
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    c.edit(c.draft!.copyWith(roomFields: 0));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('privacy-reapply')))
          .onPressed,
      isNull,
    );
    await c.applyPublication();
    expect(port.actions.where((a) => a == 'apply'), isEmpty);
  });

  testWidgets('disabled saved setting has no recovery shortcut', (
    tester,
  ) async {
    final port = RecoveryPrivacy();
    port.snapshot = LocalPrivacySnapshot(
      revision: 4,
      settings: port.snapshot.settings!.copyWith(publicationEnabled: false),
    );
    final c = LocalPrivacyController(port);
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('privacy-reapply')), findsNothing);
    expect(port.writes, 0);
  });

  testWidgets('recovery fits narrow enlarged text', (tester) async {
    viewport(tester, const Size(430, 900));
    final c = LocalPrivacyController(RecoveryPrivacy());
    addTearDown(c.dispose);
    await tester.pumpWidget(app(LocalPrivacyPage(controller: c), textScale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('privacy-reapply')), findsOneWidget);
  });
}

class RecoveryPrivacy extends PublishingPrivacy {
  RecoveryPrivacy() {
    snapshot = LocalPrivacySnapshot(
      revision: 4,
      settings: LocalPrivacySettings.editorDefaults.copyWith(
        publicationEnabled: true,
        roomFields: 1,
        fleetFields: 0,
        communities: [],
      ),
    );
  }
  bool applied = false;
  String? failureCode;
  @override
  Future<PrivacyPublicationView> publication(
    String action, {
    int? revision,
  }) async {
    actions.add(action);
    if (action == 'apply') applied = true;
    return PrivacyPublicationView(
      failureCode != null
          ? 'failed'
          : applied
          ? 'applied'
          : 'inactive',
      revision: revision,
      errorCode: failureCode,
    );
  }
}
