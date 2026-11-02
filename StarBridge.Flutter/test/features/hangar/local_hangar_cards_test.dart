import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_detail.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_editor.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_cache.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_presentation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_card_image.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_card.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_ship_row.dart';

void main() {
  testWidgets(
    'pending old-revision image retries with the current port only once',
    (tester) async {
      final old = _ImagePort()..pending = Completer<String?>();
      final current = _ImagePort()..pending = Completer<String?>();
      final cache = LocalHangarImageCache();
      Widget image(LocalHangarImagePort port) => MaterialApp(
        theme: buildStarBridgeTheme(
          FutureRestraintStyle.resolve(AppearanceMode.dark),
          const Locale('en'),
        ),
        home: LocalHangarCardImage(
          item: LocalHangarPresentation.fromSaved(_snapshot().ships.first),
          width: 240,
          imagePort: port,
          cache: cache,
          cacheKey: 'owner:a2-one:content-0',
        ),
      );
      await tester.pumpWidget(image(old));
      await tester.pumpWidget(image(current));
      old.pending!.completeError(
        const LocalHangarFailure('hangar.revision_conflict'),
      );
      await tester.pump();
      expect(current.reads, 1);
      current.pending!.complete(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<ResizeImage>(),
      );
      expect(old.reads, 1);
    },
  );

  testWidgets(
    'status displays RSI inventory time instead of metadata modification time',
    (tester) async {
      final original = _snapshot();
      final port = _Port()
        ..value = LocalHangarSnapshot(
          revision: 1,
          ships: original.ships,
          savedAt: DateTime(2026, 10, 16, 15, 30),
          inventorySavedAt: DateTime(2026, 10, 14, 10, 5),
        );
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(find.textContaining('从 RSI 读取保存于'));
      expect(label.data, contains('10:05'));
      expect(label.data, isNot(contains('15:30')));
    },
  );

  testWidgets('bookmark retains custom image and explicit refresh rereads it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final image = _ImagePort()..pending = Completer<String?>();
    final port = _ImageOwnerPort(image);
    await tester.pumpWidget(_app(port));
    image.pending!.complete(
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpAndSettle();
    ImageProvider? customImage() {
      final pictures = tester.widgetList<Image>(
        find.descendant(
          of: find.byKey(const ValueKey('local-hangar-ship-a2-one')),
          matching: find.byType(Image),
        ),
      );
      return pictures
          .map((p) => p.image)
          .where(
            (p) =>
                p is MemoryImage ||
                p is ResizeImage && p.imageProvider is MemoryImage,
          )
          .firstOrNull;
    }

    final original = customImage();
    expect(original, isNotNull);
    image.pending = Completer<String?>();
    await tester.tap(find.byKey(const ValueKey('hangar-favorite-a2-one')));
    await tester.pumpAndSettle();
    expect(
      customImage(),
      original,
      reason: 'Bookmark must retain the decoded custom image.',
    );
    expect(image.reads, 1);
    expect(
      port.imageRevisions.last,
      2,
      reason: 'Requests still use the current inventory revision.',
    );
    await tester.tap(find.byKey(const Key('local-hangar-refresh')));
    await tester.pumpAndSettle();
    expect(
      image.reads,
      2,
      reason: 'Explicit refresh invalidates image content.',
    );
    image.pending!.complete(null);
    await tester.pumpAndSettle();
    expect(customImage(), isNull);
  });

  testWidgets('card price uses the right content edge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(_Port()));
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('local-hangar-ship-a2-one'));
    final price = find.descendant(
      of: card,
      matching: find.byWidgetPredicate(
        (w) => w is Text && w.data?.startsWith(r'$') == true,
      ),
    );
    expect(price, findsOneWidget);
    expect(
      tester.getRect(price).right,
      closeTo(tester.getRect(card).right - 12, 0.1),
    );
  });

  testWidgets(
    'bookmark inside detail renews the image revision before editing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = _ImageOwnerPort(_ImagePort());
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('local-hangar-ship-a2-one')));
      await tester.pumpAndSettle();
      expect(port.imageRevisions.last, 1);
      await tester.tap(find.byKey(const Key('hangar-detail-favorite')));
      await tester.pumpAndSettle();
      expect(port.imageRevisions.last, 2);
    },
  );
  test('decoded image cache coalesces, retains misses, bounds entries and retires late owner reads', () async {
    final cache = LocalHangarImageCache();
    final image = _ImagePort()..pending = Completer<String?>();
    final first = cache.read('ship:1', image);
    expect(cache.read('ship:1', image), same(first));
    image.pending!.complete(null);
    expect(await first, isNull);
    expect(await cache.read('ship:1', image), isNull);
    expect(image.reads, 1);
    for (var i = 0; i < 17; i++) {
      await cache.read('other:$i', image);
    }
    await cache.read('ship:1', image);
    expect(image.reads, 19);
    final late = _ImagePort()..pending = Completer<String?>();
    final retiring = cache.read('old-owner', late);
    cache.clear();
    late.pending!.complete(
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    expect(await retiring, isNull);
  });

  testWidgets('cards and rows reuse custom image bytes and instance labels', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final image = _ImagePort()..pending = Completer<String?>();
    final port = _ImageOwnerPort(image);
    await tester.pumpWidget(_app(port));
    image.pending!.complete(
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    await tester.pumpAndSettle();
    expect(image.reads, 1);
    await tester.tap(find.byKey(const Key('hangar-list')));
    await tester.pumpAndSettle();
    expect(image.reads, 1);
    expect(find.text('同型号第 1 / 2 艘'), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(LocalHangarCardImage),
              matching: find.byType(Image),
            ),
          )
          .any(
            (image) =>
                image.image is MemoryImage ||
                image.image is ResizeImage &&
                    (image.image as ResizeImage).imageProvider is MemoryImage,
          ),
      isTrue,
    );
    await tester.tap(find.byKey(const Key('hangar-grid')));
    await tester.pumpAndSettle();
    expect(image.reads, 1);
  });

  testWidgets('size filters and partial and refresh feedback remain visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final snapshot = _snapshot();
    final port = _Port()
      ..value = LocalHangarSnapshot(
        revision: 1,
        ships: snapshot.ships,
        partial: true,
      );
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-partial-warning')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hangar-size-capital')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local-hangar-ship-javelin')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local-hangar-ship-a2-one')),
      findsNothing,
    );
    port.pendingRead = Completer<LocalHangarSnapshot>();
    await tester.tap(find.byKey(const Key('local-hangar-refresh')));
    await tester.pump();
    expect(find.byKey(const Key('hangar-refresh-progress')), findsOneWidget);
    expect(find.text('正在刷新列表…'), findsOneWidget);
    port.pendingRead!.complete(port.value);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hangar-refresh-progress')), findsNothing);
  });

  testWidgets(
    'collection detail supports bookmarks and Escape without tabbing through every value',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = _Port();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('local-hangar-ship-a2-one')));
      await tester.pumpAndSettle();
      expect(find.text('本艘'), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(LocalHangarDetail),
          matching: find.byType(SelectableText),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('hangar-detail-favorite')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('hangar-detail-favorite')))
            .isSelected,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarDetail), findsNothing);
    },
  );
  testWidgets(
    'image refresh during bookmark never leaves controls busy or rolls back revision',
    (tester) async {
      final port = _ImageOwnerPort(_ImagePort())
        ..pendingWrite = Completer<LocalHangarSnapshot>();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-favorite-a2-one')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('local-hangar-ship-a2-one')));
      await tester.pump(const Duration(milliseconds: 400));
      port.pendingRead = Completer<LocalHangarSnapshot>();
      tester
          .widget<LocalHangarImageEditor>(find.byType(LocalHangarImageEditor))
          .onSaved();
      await tester.pump();
      port.pendingWrite!.complete(_snapshot(marked: 'a2-one', revision: 2));
      await tester.pump();
      port.pendingRead!.complete(_snapshot(revision: 1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byKey(const Key('hangar-detail-close')));
      await tester.pump(const Duration(milliseconds: 400));
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('hangar-favorite-a2-one')),
      );
      expect(button.onPressed, isNotNull);
      expect(button.isSelected, isTrue);
    },
  );
  setUpAll(() async {
    if (const bool.fromEnvironment('HANGAR_CARD_REVIEW')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final font in {
        'Source Sans 3': 'SourceSans3VF-Upright.ttf',
        'Saira': 'Saira-VF.ttf',
        'Rajdhani': 'Rajdhani-SemiBold.ttf',
        'Source Han Sans CN': 'SourceHanSansCN-VF.ttf',
        'Source Code Pro': 'SourceCodeVF-Upright.ttf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load('assets/fonts/${font.value}'))).load();
      }
    }
  });

  testWidgets(
    'cards preserve duplicate instances; resize and view switch never reload',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      final port = _Port();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarShipCard), findsWidgets);
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-one')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-two')),
        findsOneWidget,
      );
      for (final image in tester.widgetList<LocalHangarShipImage>(
        find.byType(LocalHangarShipImage),
      )) {
        expect(image.fit, BoxFit.contain);
      }
      await tester.binding.setSurfaceSize(const Size(440, 900));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-list')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarShipCard), findsNothing);
      expect(find.byType(LocalHangarShipRow), findsWidgets);
      await tester.tap(find.byKey(const Key('hangar-grid')));
      await tester.pumpAndSettle();
      expect(port.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'roles, delivery status, search and clear filters work on saved inventory',
    (tester) async {
      final port = _Port();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-role-transport')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-c2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-one')),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('local-hangar-search')),
        'missing',
      );
      await tester.pump();
      expect(find.text('没有符合条件的舰船'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hangar-clear-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-status-concept')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-javelin')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('local-hangar-ship-c2')), findsNothing);
      expect(port.reads, 1);
    },
  );

  testWidgets('overview expands once without changing inventory or rereading', (
    tester,
  ) async {
    final port = _Port();
    await tester.pumpWidget(_app(port));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('local-hangar-summary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('local-hangar-summary')), findsOneWidget);
    expect(find.byKey(const Key('local-hangar-total-count')), findsOneWidget);
    expect(
      find.byKey(const Key('local-hangar-expanded-summary')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('local-hangar-expanded-count')))
          .data,
      '5',
    );
    expect(port.reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'historical bookmarks retain each archived ship even when its model is currently owned',
    (tester) async {
      final port = _Port()
        ..value = const LocalHangarSnapshot(
          revision: 3,
          ships: [
            LocalHangarShip(
              id: 'current',
              title: 'Carrack',
              catalogId: 'carrack',
            ),
          ],
          formerShips: [
            LocalHangarShip(
              id: 'archived-one',
              title: 'Carrack',
              catalogId: 'carrack',
              isFavorite: true,
            ),
            LocalHangarShip(
              id: 'archived-two',
              title: 'Carrack',
              catalogId: 'carrack',
              isFavorite: false,
            ),
          ],
        );
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-former')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-archived-one')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-hangar-ship-archived-two')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('hangar-favorites')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-archived-one')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-hangar-ship-archived-two')),
        findsNothing,
      );
      expect(find.text('这里显示你已收藏、但不再拥有的舰船。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('hangar-favorites')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-archived-two')),
        findsOneWidget,
      );
      expect(port.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unbookmarked history shows its custom image and opens the archived instance',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final image = _ImagePort()
        ..pending = (Completer<String?>()
          ..complete(
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ));
      final port = _ImageOwnerPort(image)
        ..value = LocalHangarSnapshot(
          revision: 3,
          ships: const [
            LocalHangarShip(
              id: 'a2-two',
              title: 'A2 Hercules',
              catalogId: 'a2',
            ),
          ],
          formerShips: [
            LocalHangarShip(
              id: 'a2-one',
              title: 'A2 Hercules',
              catalogId: 'a2',
              addedAt: DateTime.utc(2026, 1, 1),
              removedAt: DateTime.utc(2026, 10, 16),
            ),
          ],
        );
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hangar-former')));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('local-hangar-ship-a2-one'));
      expect(card, findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-two')),
        findsNothing,
      );
      expect(
        tester
            .widgetList<Image>(
              find.descendant(of: card, matching: find.byType(Image)),
            )
            .any(
              (picture) =>
                  picture.image is MemoryImage ||
                  picture.image is ResizeImage &&
                      (picture.image as ResizeImage).imageProvider
                          is MemoryImage,
            ),
        isTrue,
      );
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarDetail), findsOneWidget);
      expect(find.textContaining('最后移出机库'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'card images are layout stable and reject late old-account images even for identical ids',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      final oldImage = _ImagePort()..pending = Completer<String?>();
      final oldOwner = _ImageOwnerPort(oldImage);
      await tester.pumpWidget(_app(oldOwner));
      await tester.pumpAndSettle();
      expect(oldImage.reads, 1);
      await tester.binding.setSurfaceSize(const Size(1080, 900));
      await tester.pumpAndSettle();
      expect(oldImage.reads, 1);
      final newImage = _ImagePort();
      await tester.pumpWidget(_app(_ImageOwnerPort(newImage)));
      await tester.pumpAndSettle();
      expect(newImage.reads, 1);
      oldImage.pending!.complete(
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpAndSettle();
      final pictures = tester.widgetList<Image>(
        find.descendant(
          of: find.byType(LocalHangarCardImage),
          matching: find.byType(Image),
        ),
      );
      expect(pictures.any((picture) => picture.image is MemoryImage), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'bookmark waits for confirmation, guards duplicates and selects only that instance',
    (tester) async {
      final port = _Port()..pendingWrite = Completer<LocalHangarSnapshot>();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('hangar-favorite-a2-one'));
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<IconButton>(button).isSelected, isFalse);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
      expect(port.writes, 1);
      port.pendingWrite!.complete(_snapshot(marked: 'a2-one', revision: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(button).isSelected, isTrue);
      await tester.tap(find.byKey(const Key('hangar-favorites')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-one')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-two')),
        findsNothing,
      );
      expect(port.request, ('a2-one', true, 1));
    },
  );

  testWidgets(
    'failed bookmark preserves previous data and does not claim success',
    (tester) async {
      final port = _Port()..pendingWrite = Completer<LocalHangarSnapshot>();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-favorite-a2-one')));
      await tester.pump();
      port.pendingWrite!.completeError(const LocalHangarFailure('storage'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('hangar-favorite-a2-one')),
            )
            .isSelected,
        isFalse,
      );
      expect(find.textContaining('未能确认收藏结果'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-two')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'account replacement ignores late bookmark and closes only owned details',
    (tester) async {
      final old = _Port()..pendingWrite = Completer<LocalHangarSnapshot>();
      await tester.pumpWidget(_app(old));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('hangar-favorite-a2-one')));
      await tester.pump();
      final current = _Port()
        ..value = const LocalHangarSnapshot(
          revision: 1,
          ships: [LocalHangarShip(id: 'new', title: 'New account ship')],
        );
      await tester.pumpWidget(_app(current));
      await tester.pumpAndSettle();
      old.pendingWrite!.complete(_snapshot(marked: 'a2-one', revision: 2));
      await tester.pumpAndSettle();
      expect(find.text('New account ship'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('local-hangar-ship-a2-one')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'cache keeps confirmed bookmarks when older inventory reads arrive',
    () async {
      final source = _Port();
      var current = true;
      final cache = CachedLocalHangar(source, isCurrent: () => current);
      await cache.read();
      source.pendingRead = Completer<LocalHangarSnapshot>();
      final late = cache.read();
      final saved = await cache.setFavorite('a2-one', true, 1);
      source.pendingRead!.complete(_snapshot());
      expect(await late, same(saved));
      expect(cache.snapshot, same(saved));
      current = false;
      expect(cache.favoritesAvailable, isFalse);
      await expectLater(
        cache.setFavorite('a2-one', false, 2),
        throwsA(isA<LocalHangarFailure>()),
      );
      expect(cache.snapshot, isNull);
    },
  );

  testWidgets(
    'right detail expands, scrolls and closes without losing inventory',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final port = _Port();
      await tester.pumpWidget(_app(port));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('local-hangar-ship-a2-one')));
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarDetail), findsOneWidget);
      final panel = find
          .descendant(
            of: find.byType(LocalHangarDetail),
            matching: find.byType(Material),
          )
          .first;
      expect(tester.getSize(panel).width, 440);
      await tester.tap(find.byKey(const Key('hangar-detail-expand')));
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, 880);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(LocalHangarDetail), findsNothing);
      expect(port.reads, 1);
    },
  );

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final mode in AppearanceMode.values) {
      testWidgets(
        'cards and detail fit 200 percent ${locale.toLanguageTag()} ${mode.name}',
        (tester) async {
          addTearDown(() => tester.binding.setSurfaceSize(null));
          for (final width in [360.0, 1120.0]) {
            await tester.binding.setSurfaceSize(Size(width, 900));
            final port = _Port();
            await tester.pumpWidget(
              _app(port, locale: locale, mode: mode, scale: 2),
            );
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('local-hangar-ship-a2-one')),
              200,
              scrollable: find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('local-hangar-ship-a2-one')),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('local-hangar-ship-a2-one')),
            );
            await tester.pumpAndSettle();
            expect(find.byType(LocalHangarDetail), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pumpAndSettle();
          }
        },
      );
    }
  }

  if (const bool.fromEnvironment('HANGAR_CARD_REVIEW')) {
    for (final mode in AppearanceMode.values) {
      testWidgets('review ${mode.name}', (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 960));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(_app(_Port(), mode: mode));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final context = tester.element(find.byType(LocalHangarPage));
          for (final path
              in _snapshot().ships
                  .map((s) => s.imageAsset)
                  .whereType<String>()
                  .toSet()) {
            await precacheImage(AssetImage(path), context);
          }
        });
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const Key('hangar-review-root')),
          matchesGoldenFile(
            '../../../build/reviews/hangar-cards-${mode.name}.png',
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('local-hangar-ship-a2-one')),
        );
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const Key('hangar-review-root')),
          matchesGoldenFile(
            '../../../build/reviews/hangar-detail-${mode.name}.png',
          ),
        );
        await tester.tap(find.byKey(const Key('hangar-detail-expand')));
        await tester.pumpAndSettle();
        await expectLater(
          find.byKey(const Key('hangar-review-root')),
          matchesGoldenFile(
            '../../../build/reviews/hangar-detail-expanded-${mode.name}.png',
          ),
        );
      });
    }
  }
}

Widget _app(
  LocalHangarPort port, {
  Locale locale = const Locale('zh', 'CN'),
  AppearanceMode mode = AppearanceMode.dark,
  double scale = 1,
}) => RepaintBoundary(
  key: const Key('hangar-review-root'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: locale,
    supportedLocales: const [
      Locale('zh', 'CN'),
      Locale('zh', 'TW'),
      Locale('en'),
    ],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(mode).withReducedMotion(true),
      locale,
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: LocalHangarPage(port: port, onRead: () {}),
    ),
  ),
);

LocalHangarSnapshot _snapshot({String? marked, int revision = 1}) =>
    LocalHangarSnapshot(
      revision: revision,
      ships: [
        for (final id in ['a2-one', 'a2-two'])
          LocalHangarShip(
            id: id,
            title: 'A2 Hercules',
            cn: 'A2 大力神',
            tw: 'A2 大力神',
            liner: 'Crusader Industries',
            category: 'combat',
            sizeClass: 'large',
            deliveryStatus: 'flyable',
            priceUsd: 750,
            imageAsset: 'assets/ships/catalog-a2-hercules.jpg',
            isFavorite: marked == id,
          ),
        const LocalHangarShip(
          id: 'c2',
          title: 'C2 Hercules',
          cn: 'C2 大力神',
          liner: 'Crusader Industries',
          category: 'transport',
          sizeClass: 'large',
          deliveryStatus: 'flyable',
          priceUsd: 400,
          imageAsset: 'assets/ships/catalog-c2-hercules.jpg',
        ),
        const LocalHangarShip(
          id: 'javelin',
          title: 'Javelin',
          cn: '标枪',
          tw: '標槍',
          liner: 'Aegis Dynamics',
          category: 'combat',
          sizeClass: 'capital',
          deliveryStatus: 'concept',
          priceUsd: 3000,
          imageAsset: 'assets/ships/catalog-javelin.jpg',
        ),
        const LocalHangarShip(
          id: 'vulture',
          title: 'Vulture',
          cn: '秃鹫',
          tw: '禿鷲',
          liner: 'Drake Interplanetary',
          category: 'industrial',
          sizeClass: 'small',
          deliveryStatus: 'flyable',
          priceUsd: 175,
          imageAsset: 'assets/ships/catalog-vulture.jpg',
        ),
      ],
    );

class _Port implements LocalHangarPort, LocalHangarFavoritesPort {
  var value = _snapshot();
  int reads = 0, writes = 0;
  Completer<LocalHangarSnapshot>? pendingWrite, pendingRead;
  (String, bool, int)? request;
  @override
  bool get favoritesAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() async {
    reads++;
    return pendingRead == null ? value : pendingRead!.future;
  }

  @override
  Future<LocalHangarSnapshot> setFavorite(
    String id,
    bool selected,
    int revision,
  ) async {
    writes++;
    request = (id, selected, revision);
    value = pendingWrite == null
        ? _snapshot(marked: selected ? id : null, revision: revision + 1)
        : await pendingWrite!.future;
    return value;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw StateError('No synthetic ownership save');
}

class _ImageOwnerPort extends _Port implements LocalHangarImageProvider {
  _ImageOwnerPort(this.image);
  final _ImagePort image;
  final imageRevisions = <int>[];
  @override
  LocalHangarImagePort? imageFor(String shipId, int revision) {
    imageRevisions.add(revision);
    return shipId == 'a2-one' ? image : null;
  }
}

class _ImagePort implements LocalHangarImagePort {
  int reads = 0;
  Completer<String?>? pending;
  @override
  Future<String?> readImage() async {
    reads++;
    return pending?.future;
  }

  @override
  bool get canPickLogo => false;
  @override
  Future<CommunityLogoSource?> pickLogo() async => null;
  @override
  Future<String> cropLogo(String sourceRef, double x, double y, double size) =>
      throw StateError('No crop in image fixture');
  @override
  Future<void> clearLogo() async {}
  @override
  Future<void> saveImage() async {}
  @override
  Future<void> restoreImage() async {}
}
