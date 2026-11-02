import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'friends_test.dart' show PendingPort, ready;

void main() {
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale friends retain visible rows through refresh, failure and retry',
      (tester) async {
        final port = PendingPort();
        final module = FriendsModule(
          port,
          now: () => DateTime.utc(2026, 10, 15, 12),
        );
        addTearDown(module.dispose);
        final first = module.enter();
        port.requests.single.complete(ready('Loaded pilot'));
        await first;
        await tester.pumpWidget(
          _app(
            FriendsPage(
              createPort: () => throw StateError('borrowed'),
              module: module,
            ),
            locale,
          ),
        );
        await tester.pumpAndSettle();
        final refresh = find.byKey(const Key('friends-refresh'));
        await tester.tap(refresh);
        await tester.pump();
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        expect(tester.widget<TextButton>(refresh).onPressed, isNull);
        expect(find.byKey(const Key('friends-syncing')), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        port.requests.last.completeError(
          TimeoutException('synthetic directory timeout'),
        );
        await tester.pumpAndSettle();
        final notice = tester
            .widget<Text>(find.byKey(const Key('friends-sync-failed')))
            .data!;
        expect(
          notice,
          startsWith(
            AppStrings.resolve(locale)
                .text('friends.syncFailedAt')
                .split('{time}')
                .first,
          ),
        );
        expect(notice, contains('2026'));
        expect(find.byKey(const Key('friend-card-0')), findsOneWidget);
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.partial,
        );
        await tester.tap(refresh);
        await tester.pump();
        port.requests.last.complete(ready('Recovered pilot'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('friends-sync-failed')), findsNothing);
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.data,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'leaving the friend page retains rows, selection and numeric viewport',
    (tester) async {
      final port = PendingPort();
      final module = FriendsModule(port);
      addTearDown(module.dispose);
      final first = module.enter();
      port.requests.single.complete(
        FriendsReadResult(
          FriendsReadState.ready,
          snapshot: FriendsSnapshot(
            groups: {
              FriendsSection.incoming: [
                for (var i = 0; i < 80; i++)
                  FriendRow('Pilot $i', '', 'incoming', DateTime.utc(2026)),
              ],
            },
            results: [],
          ),
        ),
      );
      await first;
      module.select(FriendsSection.incoming);
      Widget show() => _app(
        FriendsPage(
          createPort: () => throw StateError('borrowed'),
          module: module,
        ),
        const Locale('en'),
      );
      await tester.pumpWidget(show());
      await tester.pumpAndSettle();
      final directory = find.byKey(const ValueKey('incoming:null'));
      await tester.drag(directory, const Offset(0, -600));
      await tester.pumpAndSettle();
      final offset = tester
          .widget<ListView>(directory)
          .controller!
          .offset;
      expect(offset, greaterThan(100));
      await tester.pumpWidget(
        _app(const SizedBox.shrink(), const Locale('en')),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(show());
      await tester.pump();
      expect(port.requests, hasLength(1));
      expect(module.section, FriendsSection.incoming);
      expect(
        tester.widget<ListView>(directory).controller!.offset,
        offset,
      );
      port.events.add(null);
      await tester.pump();
      expect(find.byKey(const Key('friend-card-0')), findsNothing);
      port.requests.last.complete(FriendsReadResult(FriendsReadState.ready,
        snapshot: FriendsSnapshot(groups: {FriendsSection.friends: [
          for (var i = 0; i < 80; i++) FriendRow('Current $i', '', 'friend', DateTime.utc(2026)),
        ]}, results: [])));
      await tester.pumpAndSettle();
      expect(module.scrollOffset, 0);
      expect(tester.widget<ListView>(find.byKey(const ValueKey('friends:null'))).controller!.offset, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Widget _app(Widget child, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: child),
);
