import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_session.dart';
import 'package:starbridge_flutter/features/achievements/achievement_detail.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'achievement_collection_controller_test.dart'
    show achievementTestAccount, DeferredAchievementPort;

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale refresh failure retains collection with localized notice and retry',
      (tester) async {
        final account = ValueNotifier(achievementTestAccount(1));
        final port = DeferredAchievementPort();
        final session = AchievementCollectionSession(
          account: account,
          port: port,
          clock: () => DateTime.utc(2026, 10, 15, 12),
        );
        addTearDown(account.dispose);
        addTearDown(session.dispose);
        await tester.pumpWidget(_app(account, port, session, locale));
        await tester.pumpAndSettle();
        port.requests.single.completion.complete(_ready());
        await tester.pumpAndSettle();
        final summary = tester
            .widget<Text>(find.byKey(const Key('achievement-summary')))
            .data;
        final refresh = find.byKey(const Key('achievement-refresh'));
        await tester.tap(refresh);
        await tester.pump();
        expect(session.collection.value.isRefreshing, isTrue);
        expect(tester.widget<IconButton>(refresh).onPressed, isNull);
        expect(
          find.byType(LinearProgressIndicator),
          findsNothing,
          reason: 'Reduced motion must use a static sync indication.',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const Key('achievement-summary')))
              .data,
          summary,
        );
        port.requests.last.completion.completeError(
          TimeoutException('synthetic outage'),
        );
        await tester.pumpAndSettle();
        final notice = tester
            .widget<Text>(find.byKey(const Key('achievement-sync-failed')))
            .data!;
        final context = tester.element(find.byType(AchievementsPage));
        final template = AppStrings.of(context)
            .text('achievements.syncFailedAt');
        expect(notice, startsWith(template.split('{time}').first));
        expect(notice, contains('2026'));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('achievement-summary')))
              .data,
          summary,
        );
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.partial,
        );
        await tester.tap(refresh);
        await tester.pump();
        port.requests.last.completion.complete(_ready());
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('achievement-sync-failed')), findsNothing);
        expect(tester.widget<IconButton>(refresh).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('an open inspector preserves permanent same-owner awards', (
    tester,
  ) async {
    final account = ValueNotifier(achievementTestAccount(1));
    final port = DeferredAchievementPort();
    final session = AchievementCollectionSession(account: account, port: port);
    addTearDown(account.dispose);
    addTearDown(session.dispose);
    await tester.pumpWidget(_app(account, port, session, const Locale('en')));
    await tester.pumpAndSettle();
    port.requests.single.completion.complete(_ready());
    await tester.pumpAndSettle();
    final entry = find.byKey(const Key('achievement-entry-first-entry'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AchievementDetail>(find.byType(AchievementDetail))
          .collection
          .isEarned('first-entry'),
      isTrue,
    );
    final updated = session.collection.refresh();
    await tester.pump();
    port.requests.last.completion.complete(
      AchievementCollection(
        generation: 1,
        status: AchievementCollectionStatus.ready,
      ),
    );
    await updated;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AchievementDetail>(find.byType(AchievementDetail))
          .collection
          .isEarned('first-entry'),
      isTrue,
    );
    await tester.tap(find.byKey(const Key('achievement-detail-close')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

AchievementCollection _ready() => AchievementCollection(
  generation: 1,
  status: AchievementCollectionStatus.ready,
  earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
);

Widget _app(
  ValueNotifier<AccountProjection> account,
  DeferredAchievementPort port,
  AchievementCollectionSession session,
  Locale locale,
) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(
    body: AchievementsPage(account: account, port: port, session: session),
  ),
);
