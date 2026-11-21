import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/account_card_title.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/gameplay_time/gameplay_time_panel.dart';

import 'gameplay_time_test.dart' as support;

AccountCompatibilityProjection _compatibility(
  AccountCompatibilityIdentityState state,
) => AccountCompatibilityProjection(
  identityState: state,
  relayState: AccountCompatibilityRelayState.notApplicable,
  storedLegacyCredentialAvailable: false,
  legacyFeaturesAvailable: false,
  availableActions: const [],
);

void main() {
  const scmOnlyPrefix =
      '这个 SCM 账号还没有关联旧账号，暂时不能累计或重置账号时长，本机时长照常记录。'
      '有旧账号的，可以到 设置 › 账号与识别 › ';
  // Without the scope the account card is the compatibility card.
  const scmOnlyText = '$scmOnlyPrefix旧数据兼容。';

  for (final state in AccountCompatibilityIdentityState.values) {
    testWidgets('account total and reset follow compatibility: ${state.name}', (
      tester,
    ) async {
      final h = support.Harness(resetSupported: true);
      h.account.value = h.account.value.copyWith(
        compatibility: _compatibility(state),
      );
      await tester.pump();
      await tester.pumpWidget(
        support.app(GameplayTimePanel(controller: h.controller)),
      );
      await tester.pumpAndSettle();
      final scmOnly = state == AccountCompatibilityIdentityState.unlinked;
      expect(h.controller.value.scmOnly, scmOnly);
      expect(find.text(scmOnlyText), scmOnly ? findsOneWidget : findsNothing);
      expect(find.text('账号累计暂时读不到'), scmOnly ? findsNothing : findsOneWidget);
      expect(
        find.byKey(const Key('gameplay-reset-open')),
        scmOnly ? findsNothing : findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await h.close(tester);
    });
  }

  testWidgets('a compatibility read arriving later updates the same view', (
    tester,
  ) async {
    final h = support.Harness(resetSupported: true);
    await tester.pump();
    await tester.pumpWidget(
      support.app(GameplayTimePanel(controller: h.controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text(scmOnlyText), findsNothing);
    h.account.value = h.account.value.copyWith(
      compatibility: _compatibility(AccountCompatibilityIdentityState.unlinked),
    );
    await tester.pumpAndSettle();
    expect(find.text(scmOnlyText), findsOneWidget);
    expect(find.byKey(const Key('gameplay-reset-open')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });

  testWidgets('the prompt names the account card it will find, live', (
    tester,
  ) async {
    final h = support.Harness(resetSupported: true);
    h.account.value = h.account.value.copyWith(
      compatibility: _compatibility(AccountCompatibilityIdentityState.unlinked),
    );
    final offered = ValueNotifier(false);
    await tester.pump();
    await tester.pumpWidget(
      support.app(
        AccountCardTitle(
          migrationOffered: offered,
          child: GameplayTimePanel(controller: h.controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('$scmOnlyPrefix旧数据兼容。'), findsOneWidget);
    offered.value = true;
    await tester.pumpAndSettle();
    expect(find.text('$scmOnlyPrefix迁移旧账号。'), findsOneWidget);
    expect(find.text('$scmOnlyPrefix旧数据兼容。'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    offered.dispose();
    await h.close(tester);
  });

  testWidgets('an available account total is shown even when SCM-only', (
    tester,
  ) async {
    final h = support.Harness()
      ..accountTotalState = 'available'
      ..accountTotalSeconds = 7200;
    h.account.value = h.account.value.copyWith(
      compatibility: _compatibility(AccountCompatibilityIdentityState.unlinked),
    );
    await tester.pump();
    await tester.pumpWidget(
      support.app(GameplayTimePanel(controller: h.controller)),
    );
    await tester.pumpAndSettle();
    expect(find.text('账号累计 2 小时'), findsOneWidget);
    expect(find.text(scmOnlyText), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await h.close(tester);
  });
}
