import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/localization/friends_strings.dart';
import 'package:starbridge_flutter/app/bootstrap/starbridge_app.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/friends/bridge_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/example_friends_adapter.dart';
import 'package:starbridge_flutter/features/friends/friends_module.dart';
import 'package:starbridge_flutter/features/friends/friends_page.dart';

Map<String, Object?> directory({String? query}) => {
  'schemaVersion': 1,
  'query': query,
  'refreshedAt': '2026-09-06T12:00:00Z',
  for (final s in FriendsSection.values) s.name: <Object?>[],
  'results': <Object?>[],
};
Map<String, Object?> row(String name) => {
  'callsign': name,
  'gameId': 'Example',
  'relationship': 'friend',
  'updatedAt': '2026-09-06T12:00:00Z',
};
FriendsReadResult ready(String name, {String? query}) => FriendsReadResult(
  FriendsReadState.ready,
  snapshot: parseFriendsSnapshot(
    directory(query: query)
      ..[query == null ? 'friends' : 'results'] = [row(name)],
  ),
);

class PendingPort implements FriendsPort {
  final events = StreamController<void>.broadcast(sync: true);
  final requests = <Completer<FriendsReadResult>>[];
  final queries = <String?>[];
  bool closed = false;
  int cancelled = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<FriendsReadResult> read({String? query}) {
    queries.add(query);
    final request = Completer<FriendsReadResult>();
    requests.add(request);
    return request.future;
  }

  @override
  void cancelPending() {
    cancelled++;
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
  }
}

void main() {
  test('silent refresh does not cancel an unfinished directory read', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    final first = module.refresh();
    final cancellations = port.cancelled;
    await module.refresh(silent: true).timeout(const Duration(seconds: 1));
    expect(port.requests.length, 1);
    expect(port.cancelled, cancellations);
    port.requests.single.complete(ready('first'));
    await first;
    expect(module.rows.single.callsign, 'first');
    final next = module.refresh(silent: true);
    expect(module.rows.single.callsign, 'first');
    port.requests.last.complete(ready('updated'));
    await next;
    expect(module.rows.single.callsign, 'updated');
    module.dispose();
  });

  test('invalid silent response clears previously shared directory', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    final first = module.refresh();
    port.requests.single.complete(ready('first'));
    await first;
    final next = module.refresh(silent: true);
    port.requests.last.complete(ready('wrong query', query: 'other'));
    await next;
    expect(module.state, FriendsReadState.unavailable);
    expect(module.snapshot, isNull);
    module.dispose();
  });

  test(
    'display projection preserves parentheses and refuses malformed groups',
    () {
      final data = directory()
        ..['friends'] = [
          row('呼号')..['avatarImageData'] = 'https://private/avatar',
        ];
      final value = parseFriendsSnapshot(data)
          .groups[FriendsSection.friends]!
          .single;
      expect(value.name, '呼号 (Example)');
      expect(value.avatar, isNull);
      expect(
        () => parseFriendsSnapshot({...data, 'schemaVersion': 2}),
        throwsFormatException,
      );
      expect(
        () => parseFriendsSnapshot({
          ...data,
          'friends': List.filled(2001, row('x')),
        }),
        throwsFormatException,
      );
      expect(
        () => parseFriendsSnapshot({
          ...data,
          'results': [row('x')],
        }),
        throwsFormatException,
      );
      expect(
        () => parseFriendsSnapshot({...data, 'query': 'xx'}),
        throwsFormatException,
      );
      expect(
        () => parseFriendsSnapshot(
          directory()..['friends'] = [row('x')..['relationship'] = 'admin'],
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'search query is bounded and unknown relationship remains non-actionable',
    () {
      final data = directory(query: 'xx')
        ..['results'] = [row('x')..['relationship'] = 'unknown'];
      expect(parseFriendsSnapshot(data).results.single.relationship, 'unknown');
      expect(
        () => parseFriendsSnapshot({
          ...data,
          'results': List.filled(21, row('x')),
        }),
        throwsFormatException,
      );
      expect(
        () => parseFriendsSnapshot({...data, 'query': 'x' * 129}),
        throwsFormatException,
      );
    },
  );
  test('later search wins even if earlier response completes last', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    module.editQuery('first');
    final first = module.refresh();
    module.editQuery('second');
    final second = module.refresh();
    port.requests[1].complete(ready('second', query: 'second'));
    await second;
    port.requests[0].complete(ready('first', query: 'first'));
    await first;
    expect(module.rows.single.callsign, 'second');
    module.dispose();
  });
  test('typing retires directory; account change clears projection and pending query', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    final initial = module.refresh();
    module.editQuery('search');
    port.requests[0].complete(ready('old'));
    await initial;
    expect(module.snapshot, isNull);
    final search = module.refresh();
    port.events.add(null);
    expect(module.query, isEmpty);
    expect(module.snapshot, isNull);
    expect(module.accountRevision, 1);
    expect(port.queries.last, isNull);
    port.requests[1].complete(ready('old account', query: 'search'));
    await search;
    expect(module.snapshot, isNull);
    port.requests[2].complete(
      const FriendsReadResult(FriendsReadState.signedOut),
    );
    await Future<void>.delayed(Duration.zero);
    expect(module.state, FriendsReadState.signedOut);
    module.dispose();
  });
  test('invalid search does not dispatch; response mismatch and failures are not empty success', () async {
    final port = PendingPort();
    final module = FriendsModule(port);
    for (final query in ['a', 'a' * 129, 'ab\n']) {
      module.editQuery(query);
      await module.refresh();
    }
    expect(port.requests, isEmpty);
    module.editQuery('valid');
    final read = module.refresh();
    port.requests[0].complete(ready('mismatch', query: 'other'));
    await read;
    expect(module.failure, 'invalidResponse');
    expect(module.snapshot, isNull);
    final failed = module.refresh();
    port.requests[1].completeError(StateError('private error'));
    await failed;
    expect(module.state, FriendsReadState.unavailable);
    expect(module.snapshot, isNull);
    final disposed = module.refresh();
    module.dispose();
    port.requests[2].complete(ready('late', query: 'valid'));
    await disposed;
    expect(port.closed, isTrue);
    expect(module.snapshot, isNull);
  });
  test(
    'all relationship tabs expose their own rows and localization keys match',
    () async {
      final module = FriendsModule(ExampleFriendsAdapter());
      await module.refresh();
      for (final section in FriendsSection.values) {
        module.select(section);
        expect(module.rows, hasLength(1));
        expect(
          module.rows.single.relationship,
          section == FriendsSection.friends ? 'friend' : section.name,
        );
      }
      module.dispose();
      expect(friendsZhTw.keys.toSet(), friendsZhCn.keys.toSet());
      expect(friendsEn.keys.toSet(), friendsZhCn.keys.toSet());
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    testWidgets('friend page tabs search and narrow layout $locale', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(page(locale, ExampleFriendsAdapter.new));
      await tester.pumpAndSettle();
      expect(find.text('示例好友 (Example)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('friends-nav-incoming')));
      await tester.pumpAndSettle();
      expect(find.text('示例申请 (Example)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'no-match');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text(AppStrings.resolve(locale).text('friends.noResults')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('read failure offers retry without claiming an empty directory', (
    tester,
  ) async {
    await tester.pumpWidget(
      page(const Locale('zh', 'CN'), UnavailableFriendsPort.new),
    );
    await tester.pumpAndSettle();
    expect(find.text(friendsZhCn['friends.hostUnavailable']!), findsOneWidget);
    expect(find.text(friendsZhCn['friends.empty.friends']!), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('friend page visual review', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final font in {
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
      'Source Code Pro': 'assets/fonts/SourceCodeVF-Upright.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: page(const Locale('zh', 'CN'), ExampleFriendsAdapter.new),
      ),
    );
    await tester.pumpAndSettle();
    if (Platform.environment['STARBRIDGE_CAPTURE_FRIENDS'] == '1') {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build/reviews').create(recursive: true);
        await File('build/reviews/friends-read.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'ordinary friends entry uses isolated examples only in review composition',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final example in [true, false]) {
        final composition = example
            ? AppComposition.forShellReview(
                windowChrome: InMemoryWindowChrome(),
              )
            : AppComposition.forTest(windowChrome: InMemoryWindowChrome());
        await tester.pumpWidget(StarBridgeApp(composition: composition));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('好友'));
        await tester.pumpAndSettle();
        expect(find.byType(FriendsPage), findsOneWidget);
        expect(
          find.text('示例好友 (Example)'),
          example ? findsOneWidget : findsNothing,
        );
        if (!example) {
          expect(
            find.text(friendsZhCn['friends.hostUnavailable']!),
            findsOneWidget,
          );
        }
        await tester.tap(find.byKey(const Key('friends-recent')));
        await tester.pumpAndSettle();
        expect(
          find.text('示例好友 (Example)'),
          example ? findsOneWidget : findsNothing,
        );
        if (!example) {
          expect(
            find.text(
              AppStrings.resolve(const Locale('zh', 'CN'))
                  .text('direct.error.unavailable'),
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );
}

Widget page(Locale locale, FriendsPort Function() factory) => MaterialApp(
  debugShowCheckedModeBanner: false,
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
  home: Scaffold(body: FriendsPage(createPort: factory)),
);
