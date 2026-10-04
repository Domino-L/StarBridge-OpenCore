import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_bridge_preview.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_image_editor.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_image_settings_card.dart';
import 'package:starbridge_flutter/platform/window/menu_image_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';

import '../../app/menu_overlay/menu_preview_window_test.dart'
    show MemoryMenuPreferences;
import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class _Store extends MemoryMenuPreferences {
  bool fail = false;
  @override
  Future<MenuWindowPreferences> save(MenuWindowPreferences value) async {
    if (fail) throw StateError('synthetic storage failure');
    return super.save(value);
  }
}

Future<Uint8List> _png(WidgetTester tester) async {
  late Uint8List bytes;
  await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 640, 360),
      Paint()..color = const Color(0xff173348),
    );
    canvas.drawRect(
      const Rect.fromLTWH(40, 40, 100, 100),
      Paint()..color = const Color(0xff4cb2f5),
    );
    final picture = recorder.endRecording(),
        image = await picture.toImage(640, 360);
    bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
        .asUint8List();
    image.dispose();
    picture.dispose();
  });
  return bytes;
}

void main() {
  setUpAll(loadFonts);
  for (final interfaceScale in [.85, 1.0, 1.25]) {
    for (final failPin in [false, true]) {
      testWidgets(
        'default pin captures a ready viewport once, failure=$failPin scale=$interfaceScale',
        (tester) async {
          size(tester, const Size(1000, 720));
          final bytes = await _png(tester);
          var attempts = 0;
          Map<String, Object?>? frame;
          final tools = MenuLocalToolsController((action, args) async {
            if (action == 'image') {
              return {
                'bytes': bytes,
                'imageId': '{00000000-0000-0000-0000-000000000001}',
              };
            }
            if (action == 'imagePin') {
              attempts++;
              frame = args;
              if (failPin) throw StateError('synthetic pin failure');
            }
            return true;
          });
          tools.settings(
            image: const MenuImagePreferences(defaultPinned: true),
          );
          await tools.image();
          expect(attempts, 0);
          await tester.pumpWidget(
            app(
              MediaQuery(
                data: const MediaQueryData(devicePixelRatio: 1.5),
                child: Transform.scale(
                  scale: interfaceScale,
                  alignment: Alignment.topLeft,
                  child: MenuImageTool(tools: tools),
                ),
              ),
            ),
          );
          await tester.runAsync(
            () => precacheImage(
              MemoryImage(bytes),
              tester.element(find.byType(MaterialApp)),
            ),
          );
          for (var i = 0; i < 30 && (attempts == 0 || tools.busy); i++) {
            await tester.pump();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          await tester.pumpAndSettle();
          expect(attempts, 1);
          expect(menuPngSize(frame!['bytes'] as Uint8List), isNotNull);
          expect(frame!['width'], greaterThan(0));
          if (!failPin) {
            final box = tester.renderObject<RenderRepaintBoundary>(
              find.descendant(
                of: find.byType(MenuImageTool),
                matching: find.byWidgetPredicate(
                  (w) => w is RepaintBoundary && w.key is GlobalKey,
                ),
              ),
            );
            final start = box.localToGlobal(Offset.zero) * 1.5;
            final end =
                box.localToGlobal(box.size.bottomRight(Offset.zero)) * 1.5;
            expect(frame!['x'], closeTo(start.dx, .001));
            expect(frame!['y'], closeTo(start.dy, .001));
            expect(frame!['width'], closeTo(end.dx - start.dx, .001));
            expect(frame!['height'], closeTo(end.dy - start.dy, .001));
            final pixels = menuPngSize(frame!['bytes'] as Uint8List)!;
            expect(pixels.width, (end.dx - start.dx).ceil());
            expect(pixels.height, (end.dy - start.dy).ceil());
          }
          expect(tools.pinned, !failPin);
          expect(tools.referenceAutoPinPending, isFalse);
          if (failPin) expect(find.text('固定到游戏'), findsOneWidget);
          for (var i = 0; i < 3; i++) {
            await tester.pump();
          }
          expect(attempts, 1);
          if (!failPin) {
            await tools.clear(unpinOnly: true);
            await tester.pumpAndSettle();
            expect(tools.pinned, isFalse);
            expect(attempts, 1);
          }
          await tester.pumpWidget(const SizedBox());
          tools.dispose();
        },
      );
    }
  }
  test(
    'strict image defaults preserve legacy document and unrelated settings',
    () {
      final legacy = {...MenuWindowPreferences.defaults.settings};
      expect(
        MenuImagePreferences.fromSettings(legacy)!.toMap(),
        const MenuImagePreferences().toMap(),
      );
      expect(legacy.containsKey('image'), isFalse);
      final oldImage = MenuImagePreferences.fromSettings({
        'image': {
          'openMode': 'edit',
          'scaleMode': 'fit',
          'opacityPercent': 100,
        },
      })!;
      expect(oldImage.rememberAdjustments, isTrue);
      expect(oldImage.defaultPinned, isFalse);
      for (final invalid in [
        null,
        {},
        {...const MenuImagePreferences().toMap(), 'openMode': true},
        {...const MenuImagePreferences().toMap(), 'openMode': 'unknown'},
        {...const MenuImagePreferences().toMap(), 'scaleMode': null},
        {...const MenuImagePreferences().toMap(), 'scaleMode': 'unknown'},
        {...const MenuImagePreferences().toMap(), 'opacityPercent': 19},
        {...const MenuImagePreferences().toMap(), 'opacityPercent': 101},
        {...const MenuImagePreferences().toMap(), 'opacityPercent': 20.5},
        {...const MenuImagePreferences().toMap(), 'opacityPercent': '100'},
        {...const MenuImagePreferences().toMap(), 'path': 'synthetic.png'},
        {...const MenuImagePreferences().toMap(), 'rememberAdjustments': null},
        {...const MenuImagePreferences().toMap(), 'defaultPinned': 1},
      ]) {
        expect(
          MenuWindowPreferences.parse({
            ...MenuWindowPreferences.defaults.toMap(),
            'settings': {...legacy, 'image': invalid},
          }),
          isNull,
        );
      }
      for (final mode in ['edit', 'imageOnly']) {
        for (final scale in ['fit', 'actualSize']) {
          for (final opacity in [20, 100]) {
            final value = MenuWindowPreferences.defaults.withSettingsPatch(
              MenuImagePreferences(
                openMode: mode,
                scaleMode: scale,
                opacityPercent: opacity,
              ).toSettingsPatch(),
            );
            expect(MenuWindowPreferences.parse(value.toMap()), isNotNull);
            expect(value.layout, MenuWindowPreferences.defaults.layout);
          }
        }
      }
    },
  );
  test(
    'actual scale accounts for rotation, viewport and physical screen pixels',
    () {
      expect(
        menuReferenceActualScale(
          const Size(640, 360),
          const Size(320, 180),
          1,
          0,
        ),
        2,
      );
      expect(
        menuReferenceActualScale(
          const Size(640, 360),
          const Size(320, 180),
          2,
          0,
        ),
        1,
      );
      expect(
        menuReferenceActualScale(
          const Size(640, 360),
          const Size(180, 320),
          1.5,
          1,
        ),
        closeTo(4 / 3, .00001),
      );
      expect(
        menuReferenceActualScale(
          const Size(10, 10),
          const Size(1000, 1000),
          2,
          0,
        ),
        .005,
      );
      expect(
        menuReferenceActualScale(Size.zero, const Size(20, 20), 1, 0),
        isNull,
      );
      expect(
        menuReferenceActualScale(
          const Size(10, 10),
          const Size(20, 20),
          double.nan,
          0,
        ),
        isNull,
      );
    },
  );
  test('defaults apply only after successful selection; cancellation failure and late replies preserve state', () async {
    final bytes = Uint8List.fromList([1, 2]);
    Object? response = bytes;
    var fails = false;
    final tools = MenuLocalToolsController((_, _) async {
      if (fails) throw StateError('synthetic');
      return response;
    });
    await tools.image();
    tools.referenceChanged(opacity: .6, turns: 1);
    tools.settings(
      image: const MenuImagePreferences(
        openMode: 'imageOnly',
        scaleMode: 'actualSize',
        opacityPercent: 30,
      ),
    );
    expect(tools.referenceOpacity, .6);
    expect(tools.referenceTurns, 1);
    response = null;
    await tools.image();
    expect(tools.referenceOpacity, .6);
    expect(tools.referenceImageOnly, false);
    fails = true;
    await tools.image();
    expect(tools.reference, bytes);
    fails = false;
    response = bytes;
    await tools.image();
    expect(tools.referenceOpacity, .3);
    expect(tools.referenceTurns, 0);
    expect(tools.referenceImageOnly, true);
    expect(tools.referenceScaleMode, 'actualSize');
    await tools.image(capture: true);
    expect(tools.referenceOpacity, .3);
    tools.dispose();
    final pending = Completer<Object?>();
    final disposed = MenuLocalToolsController((_, _) => pending.future);
    final pick = disposed.image();
    disposed.dispose();
    pending.complete(bytes);
    await pick;
    expect(disposed.reference, isNull);
  });
  testWidgets(
    'image-only exit, actual size at DPI2, fit and user zoom are functional without native writes',
    (tester) async {
      size(tester, const Size(1000, 720));
      final bytes = await _png(tester), calls = <String>[];
      final tools = MenuLocalToolsController((action, _) async {
        calls.add(action);
        return {
          'bytes': bytes,
          'imageId': '{00000000-0000-0000-0000-000000000001}',
        };
      });
      tools.settings(
        image: const MenuImagePreferences(
          openMode: 'imageOnly',
          scaleMode: 'actualSize',
          opacityPercent: 40,
        ),
      );
      await tools.image();
      final key = GlobalKey();
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: key,
            child: MediaQuery(
              data: const MediaQueryData(devicePixelRatio: 2),
              child: MenuImageTool(tools: tools),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(MenuImageTool)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('旋转').hitTestable(), findsNothing);
      expect(find.text('显示图片工具'), findsNothing);
      final image = tester.getSize(find.byType(Image));
      expect(
        tools.referenceTransform.value.getMaxScaleOnAxis(),
        closeTo(
          menuReferenceActualScale(const Size(640, 360), image, 2, 0)!,
          .00001,
        ),
      );
      await capture(tester, key, 'menu-reference-image-only');
      await tester.tap(find.byKey(const ValueKey('reference-image-viewport')));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byKey(const ValueKey('reference-image-viewport')));
      await tester.pumpAndSettle();
      expect(find.text('不透明度 40%'), findsOneWidget);
      expect(find.text('旋转'), findsOneWidget);
      final after = tester.getSize(find.byType(Image));
      expect(
        tools.referenceTransform.value.getMaxScaleOnAxis(),
        closeTo(
          menuReferenceActualScale(const Size(640, 360), after, 2, 0)!,
          .00001,
        ),
      );
      await tester.tap(find.text('适合窗口'));
      await tester.pumpAndSettle();
      expect(tools.referenceTransform.value.getMaxScaleOnAxis(), 1);
      await tester.tap(find.text('缩小'));
      await tester.pumpAndSettle();
      expect(tools.referenceTransform.value.getMaxScaleOnAxis(), .8);
      await tester.tap(find.text('缩小'));
      await tester.pumpAndSettle();
      expect(
        tools.referenceTransform.value.getMaxScaleOnAxis(),
        closeTo(.64, .00001),
      );
      await tester.tap(find.text('适合窗口'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放大'));
      await tester.pumpAndSettle();
      expect(tools.referenceScaleMode, isNull);
      expect(tools.referenceTransform.value.getMaxScaleOnAxis(), 1.25);
      await tester.tap(find.text('实际大小'));
      await tester.pumpAndSettle();
      expect(tools.referenceScaleMode, 'actualSize');
      expect(calls, ['image']);
      expect(tester.takeException(), isNull);
      await capture(tester, key, 'menu-reference-actual-size');
      await tester.pumpWidget(const SizedBox());
      tools.dispose();
    },
  );
  testWidgets(
    'replacing tools detaches transforms and a pending pin cannot enter the new owner',
    (tester) async {
      size(tester, const Size(1000, 720));
      final bytes = await _png(tester),
          oldCalls = <String>[],
          newCalls = <String>[];
      final old = MenuLocalToolsController((action, _) async {
        oldCalls.add(action);
        return true;
      })..reference = bytes;
      final next = MenuLocalToolsController((action, _) async {
        newCalls.add(action);
        return true;
      })..reference = bytes;
      await tester.pumpWidget(app(MenuImageTool(tools: old)));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(MenuImageTool)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('固定到游戏'));
      await tester.pumpWidget(app(MenuImageTool(tools: next)));
      await tester.pumpAndSettle();
      expect(oldCalls, isEmpty);
      expect(newCalls, isEmpty);
      final nextSerial = next.referenceEditSerial;
      old.referenceTransform.value = Matrix4.diagonal3Values(2, 2, 2);
      expect(next.referenceEditSerial, nextSerial);
      await tester.tap(find.text('放大'));
      await tester.pumpAndSettle();
      expect(next.referenceScaleMode, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      old.dispose();
      next.dispose();
    },
  );
  testWidgets(
    'save failure preserves draft; reload and save retain unrelated settings and layout',
    (tester) async {
      final store = _Store()..fail = true;
      await tester.pumpWidget(
        app(SingleChildScrollView(child: MenuImageSettingsCard(port: store))),
      );
      await tester.pumpAndSettle();
      tester
          .widget<Slider>(find.byKey(const Key('menu-image-default-opacity')))
          .onChanged!(35);
      await tester.pumpAndSettle();
      tester
          .widget<SwitchListTile>(find.byKey(const Key('menu-image-remember')))
          .onChanged!(false);
      await tester.pumpAndSettle();
      tester
          .widget<SwitchListTile>(find.byKey(const Key('menu-image-pinned')))
          .onChanged!(true);
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('menu-image-save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-image-error')), findsOneWidget);
      expect(
        tester
            .widget<MenuImageEditor>(find.byType(MenuImageEditor))
            .value
            .opacityPercent,
        35,
      );
      final original = MenuWindowPreferences(
        9,
        const {
          'version': 1,
          'panels': [],
          'open': ['image'],
        },
        {
          ...MenuWindowPreferences.defaults.settings,
          'restoreDesktop': true,
          'showClock': false,
        },
      );
      store.value = original;
      store.fail = false;
      await tester.ensureVisible(find.byKey(const Key('menu-image-reload')));
      await tester.tap(find.byKey(const Key('menu-image-reload')));
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(store.value.layout, original.layout);
      expect(store.value.settings['showClock'], false);
      expect(
        MenuImagePreferences.fromSettings(store.value.settings)!.opacityPercent,
        35,
      );
      expect(find.byKey(const Key('menu-image-error')), findsNothing);
      final saved = MenuImagePreferences.fromSettings(store.value.settings)!;
      expect(saved.rememberAdjustments, isFalse);
      expect(saved.defaultPinned, isTrue);
    },
  );
  testWidgets('menu settings use the same image model and persistence patch', (
    tester,
  ) async {
    size(tester, const Size(1280, 900));
    final tools = MenuLocalToolsController((_, _) async => null);
    final changes = <Map<String, Object?>>[];
    await tester.pumpWidget(
      app(
        MenuBridgePreview(
          visible: true,
          onDismiss: () {},
          localToolsController: tools,
          localCall: (_, _) async => null,
          onSettingsChanged: changes.add,
          initialSettings: {
            ...MenuWindowPreferences.defaults.settings,
            'restoreDesktop': true,
            ...const MenuImagePreferences(opacityPercent: 25).toSettingsPatch(),
          },
          initialLayout: const {
            'version': 1,
            'panels': [],
            'open': ['settings'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tools.imagePreferences.opacityPercent, 25);
    final slider = find.byKey(const Key('menu-image-default-opacity'));
    await tester.ensureVisible(slider);
    tester.widget<Slider>(slider).onChanged!(45);
    await tester.pumpAndSettle();
    expect(tools.imagePreferences.opacityPercent, 45);
    expect((changes.last['image'] as Map)['opacityPercent'], 45);
    expect(
      MenuWindowPreferences.parse({
        'revision': 1,
        'layout': MenuWindowPreferences.defaults.layout,
        'settings': changes.last,
      }),
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    tools.dispose();
  });
  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      'image-only mode $locale remains reversible at 320x240 and large text',
      (tester) async {
        size(tester, const Size(320, 240));
        final bytes = await _png(tester), calls = <String>[];
        final tools = MenuLocalToolsController((action, _) async {
          calls.add(action);
          return {
            'bytes': bytes,
            'imageId': '{00000000-0000-0000-0000-000000000001}',
          };
        });
        tools.settings(
          image: const MenuImagePreferences(openMode: 'imageOnly'),
        );
        await tools.image();
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(2)),
                  child: RepaintBoundary(
                    key: key,
                    child: MenuImageTool(tools: tools),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => precacheImage(
            MemoryImage(bytes),
            tester.element(find.byType(MenuImageTool)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(OutlinedButton).hitTestable(), findsNothing);
        expect(tester.getSize(find.byType(Image)).height, greaterThan(0));
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-reference-only-${locale.toLanguageTag()}-320',
        );
        await tester.tap(
          find.byKey(const ValueKey('reference-image-viewport')),
        );
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tap(
          find.byKey(const ValueKey('reference-image-viewport')),
        );
        await tester.pumpAndSettle();
        expect(tools.referenceImageOnly, isFalse);
        expect(calls, ['image']);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        tools.dispose();
      },
    );
    for (final width in [320.0, 1040.0]) {
      testWidgets('reference defaults $locale width=$width large text', (
        tester,
      ) async {
        size(tester, Size(width, 900));
        final key = GlobalKey();
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => Localizations.override(
                context: context,
                locale: locale,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: RepaintBoundary(
                    key: key,
                    child: SingleChildScrollView(
                      child: MenuImageSettingsCard(port: _Store()),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'menu-image-settings-${locale.toLanguageTag()}-${width.toInt()}',
        );
        if (width == 320) {
          await tester.ensureVisible(
            find.byKey(const Key('menu-image-reload')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'menu-image-settings-${locale.toLanguageTag()}-320-bottom',
          );
        }
      });
    }
  }
}
