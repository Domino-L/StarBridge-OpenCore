import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/common/user_avatar_menu.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_catalog_ship_image.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_controller.dart';
import 'package:starbridge_flutter/features/communities/community_ship_detail_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_ship_image_port.dart';
import 'package:starbridge_flutter/features/communities/community_ship_report_port.dart';
import 'package:starbridge_flutter/features/communities/community_ships_port.dart';

import 'community_ships_test.dart' show shipRow;
import 'community_workspace_test.dart' show WorkspaceTestPort;
import 'community_workspace_view_test.dart' show host;
import '../friends/social_layout_test.dart' show loadFonts;

final _target = 'a' * 32, _ship = 'c' * 32;
const _catalog = 'assets/ships/catalog-test.png';
const _thumbnail = 'assets/ships/catalog-test-thumb.png';

class _CatalogBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == _catalog || key == _thumbnail) {
      return ByteData.sublistView(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    }
    return rootBundle.load(key);
  }
}

class _Port extends WorkspaceTestPort
    implements
        CommunityShipsPort,
        CommunityShipImagePort,
        CommunityShipReportPort {
  String? readError;
  bool customImage = true, withCatalog = true;
  int reads = 0, imageReads = 0, reports = 0;
  Completer<CommunityShipsPage>? pending;
  @override
  bool get shipsAvailable => true;
  @override
  bool get shipImageAvailable => true;
  @override
  bool get shipReportAvailable => true;

  CommunityShipsPage page([CommunityShipQuery? query]) =>
      CommunityShipsPage.parse({
        'schemaVersion': 1,
        'queryVersion': query == null ? 0 : 2,
        'query': query?.toPayload(),
        'targetRef': _target,
        'revision': 'b' * 64,
        'offset': 0,
        'next': null,
        'totalCount': 1,
        'matchedCount': 1,
        'ships': [
          shipRow()
            ..['code'] = 'catalog-testship'
            ..['englishName'] = 'Fixture English Model'
            ..['manufacturer'] = 'Fixture Manufacturer'
            ..['ownerHasAvatar'] = false
            ..['hasCustomImage'] = customImage
            ..['catalogImageAsset'] = withCatalog ? _catalog : null
            ..['catalogThumbnailAsset'] = withCatalog ? _thumbnail : null,
        ],
      });
  @override
  Future<CommunityShipsPage> readShips(
    String targetRef, {
    int offset = 0,
    String? revision,
    CommunityShipQuery? query,
  }) async {
    reads++;
    if (readError != null) throw CommunityFailure(readError!);
    return pending?.future ?? page(query);
  }

  @override
  Future<Map<String, Object?>> readShipImage(
    String targetRef,
    String shipRef, {
    required int offset,
    String? version,
  }) async {
    imageReads++;
    throw StateError('Catalog-only UI must not request a custom image');
  }

  @override
  Future<CommunityShipReportOutcome> reportShipImage(
    CommunityShipReportIntent intent,
  ) async {
    reports++;
    throw StateError('Catalog artwork has no custom-image report action');
  }

  @override
  Future<CommunityShipReportOutcome> checkShipReport(
    CommunityShipReportIntent intent,
  ) async {
    throw StateError('No custom-image report UI');
  }
}

Future<void> _open(WidgetTester tester, _Port port, Locale locale) async {
  await tester.pumpWidget(
    DefaultAssetBundle(bundle: _CatalogBundle(), child: host(port, locale)),
  );
  await tester.pumpAndSettle();
  final entry = find.byKey(const ValueKey('community-section-ships'));
  await tester.ensureVisible(entry);
  await tester.tap(entry);
  await tester.pumpAndSettle();
  final thumbnail = tester
      .widgetList<CommunityCatalogShipImage>(
        find.byType(CommunityCatalogShipImage),
      )
      .where((image) => image.compact);
  expect(thumbnail.single.asset, port.withCatalog ? _thumbnail : null);
  final subtitle = locale.languageCode == 'en'
      ? 'Fixture Manufacturer'
      : 'Fixture English Model';
  expect(find.text(subtitle), findsOneWidget);
  expect(find.text('catalog-testship'), findsNothing);
  final details = find.byKey(ValueKey('community-ship-details-${'c' * 32}'));
  await tester.ensureVisible(details);
  await tester.tap(details);
  await tester.pumpAndSettle();
  expect(
    find.descendant(
      of: find.byType(CommunityShipDetailDialog),
      matching: find.text(subtitle),
    ),
    findsOneWidget,
  );
  expect(find.text('catalog-testship'), findsNothing);
}

void main() {
  setUpAll(loadFonts);
  test('background detail read keeps content and coalesces requests', () async {
    final port = _Port();
    final model = CommunityShipDetailController(port, port.page(), _ship);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    final previous = model.ship;
    port.pending = Completer();
    final refresh = model.load(background: true);
    expect(model.ship, same(previous));
    await model.load(background: true);
    expect(port.reads, 2);
    port.pending!.complete(port.page());
    await refresh;
    expect(model.ship, isNotNull);
    expect(model.busy, isFalse);
    expect(port.imageReads, 0);
  });
  test(
    'background detail revocation clears an already displayed ship',
    () async {
      final port = _Port();
      final model = CommunityShipDetailController(port, port.page(), _ship);
      addTearDown(model.dispose);
      addTearDown(port.changes.close);
      await model.load();
      expect(model.ship, isNotNull);
      port.readError = 'notAllowed';
      await model.load(background: true);
      expect(model.ship, isNull);
      expect(model.invalidated, isTrue);
      await model.load(background: true);
      expect(port.reads, 2);
    },
  );
  test('legacy custom metadata is preserved but never fetched', () async {
    final port = _Port();
    final model = CommunityShipDetailController(port, port.page(), _ship);
    addTearDown(model.dispose);
    addTearDown(port.changes.close);
    await model.load();
    expect(port.reads, 1);
    expect(port.imageReads, 0);
    expect(model.ship!.hasCustomImage, isTrue);
    expect(model.ship!.customImageCropFocusX, .3);
    expect(model.ship!.customImageCropFocusY, .7);
    expect(model.ship!.customImageCropZoom, 1.4);
    expect(model.ship!.catalogImageAsset, _catalog);
    expect(port.reports, 0);
  });
  for (final action in ['invalidate', 'dispose']) {
    test('late authorized page is ignored after $action', () async {
      final port = _Port()..pending = Completer();
      final model = CommunityShipDetailController(port, port.page(), _ship);
      addTearDown(port.changes.close);
      final pending = model.load();
      await Future<void>.delayed(Duration.zero);
      if (action == 'invalidate') {
        model.invalidate();
        addTearDown(model.dispose);
      } else {
        model.dispose();
      }
      port.pending!.complete(port.page());
      await pending;
      expect(model.ship, isNull);
      expect(port.imageReads, 0);
    });
  }
  for (final error in [
    'notAllowed',
    'refreshRequired',
    'identityUnavailable',
    'shipsChanged',
  ]) {
    test(
      'detail validation $error never exposes ship or requests image',
      () async {
        final port = _Port()..readError = error;
        final model = CommunityShipDetailController(port, port.page(), _ship);
        addTearDown(model.dispose);
        addTearDown(port.changes.close);
        await model.load();
        expect(port.imageReads, 0);
        expect(model.ship, isNull);
        expect(model.error, error);
      },
    );
  }
  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
  ]) {
    for (final width in [420.0, 1200.0]) {
      testWidgets(
        'catalog detail ${locale.toLanguageTag()} fits $width with legacy custom image',
        (tester) async {
          tester.view.physicalSize = Size(width, 950);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final port = _Port();
          addTearDown(port.changes.close);
          await _open(tester, port, locale);
          final details = find.byType(CommunityShipDetailDialog);
          expect(details, findsOneWidget);
          expect(port.reads, 2);
          final artwork = find.descendant(
            of: details,
            matching: find.byType(CommunityCatalogShipImage),
          );
          expect(
            tester.widget<CommunityCatalogShipImage>(artwork).asset,
            _catalog,
          );
          final size = tester.getSize(artwork);
          expect(size.width / size.height, greaterThan(2.7));
          expect(find.byIcon(Icons.flag_outlined), findsNothing);
          expect(port.imageReads, 0);
          expect(port.reports, 0);
          expect(tester.takeException(), isNull);
          if (width == 1200 && locale.countryCode == 'CN') {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find
                  .ancestor(of: details, matching: find.byType(RepaintBoundary))
                  .first,
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              final file = File('build/community-catalog-only-review.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(
            find.descendant(of: details, matching: find.byType(UserAvatarMenu)),
          );
          await tester.pumpAndSettle();
          expect(find.byType(MenuItemButton), findsWidgets);
          port.changes.add(null);
          await tester.pumpAndSettle();
          expect(details, findsNothing);
          expect(find.byType(MenuItemButton), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  for (final custom in [true, false]) {
    testWidgets(
      'missing catalog stays explicit, custom=$custom does not restore old image',
      (tester) async {
        final port = _Port()
          ..customImage = custom
          ..withCatalog = false;
        addTearDown(port.changes.close);
        await _open(tester, port, const Locale('zh', 'CN'));
        expect(find.text('尚无可用舰船图片。'), findsOneWidget);
        expect(find.byIcon(Icons.flag_outlined), findsNothing);
        expect(port.imageReads, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(CommunityShipDetailDialog), findsNothing);
        expect(port.reports, 0);
      },
    );
  }
  testWidgets('leaving parent removes catalog detail', (tester) async {
    final port = _Port();
    addTearDown(port.changes.close);
    await _open(tester, port, const Locale('en'));
    final app = host(port, const Locale('en')) as MaterialApp;
    await tester.pumpWidget(
      MaterialApp(
        locale: app.locale,
        supportedLocales: app.supportedLocales,
        localizationsDelegates: app.localizationsDelegates,
        theme: app.theme,
        home: const Scaffold(body: Text('Another page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CommunityShipDetailDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
