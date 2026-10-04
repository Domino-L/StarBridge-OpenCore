import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_directory_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_screenshot_directory_controller.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_overlay_settings.dart';
import 'package:starbridge_flutter/platform/window/menu_screenshot_directory.dart';
import 'package:starbridge_flutter/platform/window/method_channel_menu_preview_window.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class DirectoryPort implements MenuScreenshotDirectoryPort {
  MenuScreenshotDirectory value = const MenuScreenshotDirectory(
    revision: 0,
    directory: r'C:\Synthetic\Pictures\StarBridge\Screenshots',
    isDefault: true,
  );
  bool fail = false, cancel = false;
  final calls = <String>[];
  Future<MenuScreenshotDirectory>? pending;
  @override
  Future<MenuScreenshotDirectory> read() async {
    calls.add('read');
    if (fail) throw StateError('synthetic');
    return value;
  }

  @override
  Future<MenuScreenshotDirectory> choose(MenuScreenshotDirectory saved) async {
    calls.add('choose');
    if (pending != null) return pending!;
    if (fail) throw StateError('unknown outcome');
    if (cancel) {
      return MenuScreenshotDirectory(
        revision: saved.revision,
        directory: saved.directory,
        isDefault: saved.isDefault,
        cancelled: true,
      );
    }
    return value = MenuScreenshotDirectory(
      revision: saved.revision + 1,
      directory: r'C:\Synthetic\A deliberately long screenshot folder name\StarBridge\Screenshots',
      isDefault: false,
    );
  }

  @override
  Future<MenuScreenshotDirectory> reset(MenuScreenshotDirectory saved) async {
    calls.add('reset');
    return value = MenuScreenshotDirectory(
      revision: saved.revision + 1,
      directory: r'C:\Synthetic\Pictures\StarBridge\Screenshots',
      isDefault: true,
    );
  }

  @override
  Future<MenuScreenshotDirectory> open(MenuScreenshotDirectory saved) async {
    calls.add('open');
    return MenuScreenshotDirectory(
      revision: saved.revision,
      directory: saved.directory,
      isDefault: saved.isDefault,
      opened: true,
    );
  }
}

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'formal settings expose the Host directory provider without opening demo or menu',
    (tester) async {
      size(tester, const Size(1040, 900));
      final port = DirectoryPort();
      final window = MethodChannelMenuPreviewWindow(
        lifetime: MenuWindowLifetime(),
        screenshotDirectory: port,
      );
      await tester.pumpWidget(app(MenuOverlaySettings(preview: window)));
      await tester.pumpAndSettle();
      expect(find.byType(MenuScreenshotDirectoryCard), findsOneWidget);
      expect(port.calls, ['read']);
      final choose = find.byKey(const Key('menu-screenshot-directory-choose'));
      await tester.ensureVisible(choose);
      await tester.tap(choose);
      await tester.pumpAndSettle();
      expect(port.calls, ['read', 'choose']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      window.dispose();
    },
  );
  test('cancel preserves confirmed destination, unknown result blocks actions until reload', () async {
    final port = DirectoryPort();
    final c = MenuScreenshotDirectoryController(port);
    await c.load();
    final before = c.saved!;
    port.cancel = true;
    await c.choose();
    expect(c.status, 'cancelled');
    expect(c.saved!.directory, before.directory);
    port.fail = true;
    await c.choose();
    expect(c.status, 'chooseFailed');
    expect(c.canAct, false);
    final count = port.calls.length;
    await c.open();
    await c.reset();
    await c.choose();
    expect(port.calls.length, count);
    port.fail = false;
    await c.load();
    expect(c.canAct, true);
    port.cancel = false;
    await c.choose();
    expect(c.saved!.isDefault, false);
    await c.open();
    expect(c.status, 'opened');
    await c.reset();
    expect(c.saved!.isDefault, true);
    c.dispose();
  });
  test('late picker never restores disposed settings and duplicate actions are merged', () async {
    final port = DirectoryPort(),
        pending = Completer<MenuScreenshotDirectory>();
    final c = MenuScreenshotDirectoryController(port);
    await c.load();
    port.pending = pending.future;
    final work = c.choose();
    await c.choose();
    await c.open();
    expect(port.calls, ['read', 'choose']);
    c.dispose();
    pending.complete(port.value);
    await work;
    expect(c.saved, isNull);
  });
  testWidgets(
    'normal settings actions route without screenshot capture or export',
    (tester) async {
      final port = DirectoryPort();
      size(tester, const Size(1040, 900));
      await tester.pumpWidget(
        app(
          SingleChildScrollView(child: MenuScreenshotDirectoryCard(port: port)),
        ),
      );
      await tester.pumpAndSettle();
      expect(port.calls, ['read']);
      for (final action in ['choose', 'open', 'reset']) {
        final button = find.byKey(Key('menu-screenshot-directory-$action'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(port.calls, ['read', 'choose', 'open', 'reset']);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [1040.0, 320.0]) {
      testWidgets(
        'directory $locale width=$width enlarged text wraps and recovery is reachable',
        (tester) async {
          size(tester, Size(width, 900));
          final port = DirectoryPort();
          await port.choose(port.value);
          final c = MenuScreenshotDirectoryController(port);
          await c.load();
          port.fail = true;
          await c.choose();
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
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: MenuScreenshotDirectoryCard(
                            port: port,
                            controller: c,
                          ),
                        ),
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
            'menu-directory-${locale.toLanguageTag()}-${width.toInt()}-top',
          );
          await tester.ensureVisible(
            find.byKey(const Key('menu-screenshot-directory-reload')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'menu-directory-${locale.toLanguageTag()}-${width.toInt()}-recovery',
          );
          port.fail = false;
          await tester.tap(
            find.byKey(const Key('menu-screenshot-directory-reload')),
          );
          await tester.pumpAndSettle();
          expect(c.canAct, true);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        },
      );
    }
  }
}
