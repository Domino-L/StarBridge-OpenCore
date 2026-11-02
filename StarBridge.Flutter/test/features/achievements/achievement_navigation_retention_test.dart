import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/achievements/achievement_collection_port.dart';
import 'package:starbridge_flutter/features/achievements/achievements_feature.dart';

void main() {
  testWidgets(
    'returning to the same achievement feature retains data and scroll',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1080, 420);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final account = createAccountModule(
        InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
      );
      addTearDown(account.dispose);
      await account.initialize();
      final port = _CollectionPort();
      final feature = createAchievementsFeature(account, port: port);
      addTearDown(() => feature.onDispose?.call());
      var visible = true;
      late StateSetter navigate;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark),
            const Locale('en'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                navigate = setState;
                return visible
                    ? feature.buildDestination(context)
                    : const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final summary = tester
          .widget<Text>(find.byKey(const Key('achievement-summary')))
          .data;
      final scroll = find.byKey(const Key('achievement-collection-scroll'));
      await tester.drag(scroll, const Offset(0, -550));
      await tester.pumpAndSettle();
      final position = tester
          .widget<SingleChildScrollView>(scroll)
          .controller!
          .offset;
      expect(position, greaterThan(100));
      final reads = port.reads;
      navigate(() => visible = false);
      await tester.pumpAndSettle();
      port.hold = Completer<AchievementCollection>();
      navigate(() => visible = true);
      await tester.pump();
      expect(
        port.reads,
        reads,
        reason: 'A fresh same-session return must not reread or replace the first frame.',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('achievement-summary'))).data,
        summary,
      );
      expect(
        tester.widget<SingleChildScrollView>(scroll).controller!.offset,
        position,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

final class _CollectionPort implements AchievementCollectionPort {
  int reads = 0;
  Completer<AchievementCollection>? hold;
  @override
  Future<AchievementCollection> read({required int generation}) {
    reads++;
    return hold?.future ??
        Future.value(
          AchievementCollection(
            generation: generation,
            status: AchievementCollectionStatus.ready,
            earnedAt: {'first-entry': DateTime.utc(2026, 9, 4)},
          ),
        );
  }
}
