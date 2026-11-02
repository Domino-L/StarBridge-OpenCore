import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_session.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_friends_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_locale.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';

class SearchPort implements FriendsPort, FriendsCommandPort {
  SearchPort(this.answer);
  final FriendsSnapshot Function(String? query) answer;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) async =>
      FriendsReadResult(FriendsReadState.ready, snapshot: answer(query));
  @override
  bool get commandsAvailable => true;
  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async =>
      const FriendCommandResult('rejected');
  @override
  void cancelPending() {}
  @override
  Future<void> close() async => events.close();
}

final _at = DateTime(2026, 10, 31);
FriendRow friend(String name, String handle, String ref) => FriendRow(
  name,
  handle,
  'friend',
  _at,
  targetRef: ref,
  chatTargetRef: 'chat-$ref',
  actions: const ['remove', 'block'],
);
FriendRow other(String name, String ref, {bool addable = true}) => FriendRow(
  name,
  '',
  'none',
  _at,
  targetRef: ref,
  actions: addable ? const ['send', 'block'] : const [],
);
FriendsSnapshot result(
  String query, {
  List<FriendRow> friends = const [],
  List<FriendRow> others = const [],
}) => FriendsSnapshot(
  groups: {FriendsSection.friends: friends},
  results: others,
  query: query,
);

Future<MenuFriendsView> search(
  WidgetTester tester,
  FriendsSnapshot snapshot,
) async {
  final views = <Map<String, Object?>>[];
  final session = MenuFriendsSession(
    SearchPort(
      (query) => query == null
          ? FriendsSnapshot(groups: const {}, results: const [])
          : snapshot,
    ),
    views.add,
  );
  session.show(true);
  await tester.pump();
  session.act('search', '', snapshot.query!);
  await tester.pump();
  await tester.pump();
  final view = MenuFriendsView.parse(jsonEncode(views.last));
  expect(view.state, 'ready', reason: jsonEncode(views.last));
  session.dispose();
  await tester.pump();
  return view;
}

Future<void> panel(
  WidgetTester tester,
  MenuFriendsView view, {
  Locale locale = const Locale('zh', 'CN'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 700,
          child: MenuFriendsPanel(
            view: view,
            onClose: () {},
            embedded: true,
            onAction: (_, _, _) {},
          ),
        ),
      ),
    ),
  );
  // Localized strings load after the first frame.
  await tester.pump();
}

String text(
  Locale locale,
  String key, [
  Map<String, Object?> args = const {},
]) => menuOverlayFormat(AppStrings.resolve(locale), key, args);

void main() {
  for (final locale in AppStrings.supportedLocales) {
    String t(String key, [Map<String, Object?> args = const {}]) =>
        text(locale, 'menu.overlay.friends.$key', args);

    testWidgets('friend found, nobody else: says who is findable $locale', (
      tester,
    ) async {
      final view = await search(
        tester,
        result('Stardust', friends: [friend('星尘', 'Stardust-07', 'f')]),
      );
      expect(view.matched, 1);
      expect(view.rows.single.name, '星尘');
      expect(view.gameIds.values.single, 'Stardust-07');
      expect(view.chatKeys, hasLength(1));
      await panel(tester, view, locale: locale);
      expect(find.text('${t('searchFriends')} · 1'), findsOneWidget);
      expect(find.text('${t('searchOthers')} · 0'), findsOneWidget);
      expect(find.text(t('noOthers')), findsOneWidget);
      expect(find.text(t('searchRule')), findsOneWidget);
      expect(find.textContaining('Stardust-07'), findsOneWidget);
      expect(find.text(t('noRecords')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('friends first, the others keep their request $locale', (
      tester,
    ) async {
      final view = await search(
        tester,
        result(
          'star',
          friends: [friend('星尘', 'Stardust-07', 'f')],
          others: [other('Starhopper_91', 'o')],
        ),
      );
      await panel(tester, view, locale: locale);
      expect(find.text('${t('searchFriends')} · 1'), findsOneWidget);
      expect(find.text('${t('searchOthers')} · 1'), findsOneWidget);
      expect(find.text(t('searchRule')), findsNothing);
      final send = view.actions.entries
          .where((entry) => entry.value.contains('send'))
          .single
          .key;
      expect(find.byKey(ValueKey('friend-inline-send-$send')), findsOneWidget);
      final top = tester.getTopLeft(find.textContaining('星尘')).dy;
      expect(
        top,
        lessThan(tester.getTopLeft(find.textContaining('Starhopper_91')).dy),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('nobody found names the search and the rule $locale', (
      tester,
    ) async {
      final view = await search(tester, result('Raven'));
      expect(view.matched, 0);
      await panel(tester, view, locale: locale);
      expect(find.text('${t('results')} · 0'), findsOneWidget);
      expect(find.text(t('noneFound', {'query': 'Raven'})), findsOneWidget);
      expect(find.text(t('searchRule')), findsOneWidget);
      expect(find.text('${t('searchFriends')} · 0'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'someone Relay cannot reach shows why, with no request $locale',
      (tester) async {
        final view = await search(
          tester,
          result('nova', others: [other('Nova_Pilot', 'n', addable: false)]),
        );
        expect(view.notAddable, hasLength(1));
        expect(view.actions.values.expand((actions) => actions), isEmpty);
        await panel(tester, view, locale: locale);
        expect(find.text('${t('results')} · 1'), findsOneWidget);
        expect(find.text(t('notAddableHere')), findsOneWidget);
        expect(find.textContaining('friend-inline-send'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  group('feedback stays with what the person just did', () {
    Future<(MenuFriendsSession, String Function())> open(
      WidgetTester tester,
    ) async {
      final views = <Map<String, Object?>>[];
      final session = MenuFriendsSession(
        SearchPort(
          (query) => query == null
              ? FriendsSnapshot(groups: const {}, results: const [])
              : result(query),
        ),
        views.add,
      )..show(true);
      await tester.pump();
      await tester.pump();
      return (
        session,
        () => MenuFriendsView.parse(jsonEncode(views.last)).feedback,
      );
    }

    Future<void> close(WidgetTester tester, MenuFriendsSession session) async {
      session.dispose();
      await tester.pump();
    }

    testWidgets('a plain refresh asks nobody to check relationships', (
      tester,
    ) async {
      final (session, feedback) = await open(tester);
      session.act('refresh', '', '');
      await tester.pump();
      await tester.pump();
      expect(feedback(), '');
      session.act('search', '', 'Raven');
      await tester.pump();
      await tester.pump();
      expect(feedback(), '');
      await close(tester, session);
    });

    testWidgets('a new search or section drops the last notice', (
      tester,
    ) async {
      final (session, feedback) = await open(tester);
      session.act('search', '', 'x');
      expect(feedback(), 'invalidSearch');
      session.act('search', '', 'Raven');
      await tester.pump();
      await tester.pump();
      expect(feedback(), '');
      session.act('search', '', 'x');
      expect(feedback(), 'invalidSearch');
      session.act('section', '', 'incoming');
      await tester.pump();
      await tester.pump();
      expect(feedback(), '');
      await close(tester, session);
    });
  });

  testWidgets('a person Relay can reach never shows the notice', (
    tester,
  ) async {
    final view = await search(
      tester,
      result('nova', others: [other('Nova_Pilot', 'n')]),
    );
    expect(view.notAddable, isEmpty);
  });

  test('a matched count beyond the rows is not a valid view', () {
    final view = MenuFriendsView.parse(
      jsonEncode({
        'state': 'ready',
        'incoming': 0,
        'matched': 1,
        'rows': <Object?>[],
      }),
    );
    expect(view.state, 'unavailable');
  });
}
