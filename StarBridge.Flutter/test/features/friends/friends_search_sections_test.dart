import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';
import 'package:starbridge_flutter/features/friends/friends_snapshot_decoder.dart';

const _at = '2026-10-31T00:00:00Z';
final _ref = 'a' * 32;
Map<String, Object?> _row(
  String name,
  String relationship, {
  String handle = '',
  List<String> actions = const [],
  bool target = true,
}) => {
  'callsign': name,
  'gameId': handle,
  'relationship': relationship,
  'updatedAt': _at,
  if (target) 'targetRef': _ref,
  'actions': actions,
};

Map<String, Object?> _directory({
  String? query,
  List<Map<String, Object?>> friends = const [],
  List<Map<String, Object?>> incoming = const [],
  List<Map<String, Object?>> results = const [],
}) => {
  'schemaVersion': 1,
  'query': query,
  'friends': friends,
  'incoming': incoming,
  'outgoing': <Object?>[],
  'blocked': <Object?>[],
  'results': results,
};

class _Port implements FriendsPort {
  _Port(this.search);
  final Map<String, Object?> search;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<FriendsReadResult> read({String? query}) async => FriendsReadResult(
    FriendsReadState.ready,
    snapshot: parseFriendsSnapshot(query == null ? _directory() : search),
  );
  @override
  void cancelPending() {}
  @override
  Future<void> close() async {}
}

Widget _page(Locale locale, Map<String, Object?> search) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    ...GlobalMaterialLocalizations.delegates,
  ],
  theme: buildStarBridgeTheme(
    StyleRegistry()
        .resolve(StyleRegistry.fallbackStyleId, AppearanceMode.dark)
        .tokens,
    locale,
  ),
  home: Scaffold(body: FriendsPage(createPort: () => _Port(search))),
);

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  test('a search may carry only the friends it also applies to', () {
    final carried = parseFriendsSnapshot(
      _directory(query: 'star', friends: [_row('星尘', 'friend')]),
    );
    expect(carried.groups[FriendsSection.friends], hasLength(1));
    expect(
      () => parseFriendsSnapshot(
        _directory(query: 'star', incoming: [_row('申请', 'incoming')]),
      ),
      throwsFormatException,
    );
  });

  test('only a target with no command is not addable here', () {
    FriendRow parsed(Map<String, Object?> row) =>
        parseFriendsSnapshot(_directory(query: 'x', results: [row]))
            .results
            .single;
    expect(parsed(_row('N', 'none')).notAddableHere, isTrue);
    expect(
      parsed(_row('N', 'none', actions: const ['send'])).notAddableHere,
      isFalse,
    );
    expect(
      parsed(_row('N', 'none', actions: const ['block'])).notAddableHere,
      isTrue,
    );
    expect(parsed(_row('N', 'none', target: false)).notAddableHere, isFalse);
    expect(parsed(_row('N', 'friend')).notAddableHere, isFalse);
  });

  for (final locale in AppStrings.supportedLocales) {
    String t(String key) => AppStrings.resolve(locale).text('friends.$key');

    testWidgets('the page lists matched friends before others $locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _page(
          locale,
          _directory(
            query: 'star',
            friends: [_row('星尘', 'friend', handle: 'Stardust-07')],
            results: [
              _row('Starhopper_91', 'none', actions: const ['send', 'block']),
              _row('Nova_Pilot', 'none'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _search(tester, 'star');
      expect(find.text('${t('searchFriends')} · 1'), findsOneWidget);
      expect(find.text('${t('searchOthers')} · 2'), findsOneWidget);
      expect(find.text(t('notAddableHere')), findsOneWidget);
      expect(find.text(t('searchRule')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the page explains when only friends match $locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        _page(
          locale,
          _directory(
            query: 'star',
            friends: [_row('星尘', 'friend', handle: 'Stardust-07')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _search(tester, 'star');
      expect(find.text('${t('searchOthers')} · 0'), findsOneWidget);
      expect(find.text(t('noOthers')), findsOneWidget);
      expect(find.text(t('searchRule')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
