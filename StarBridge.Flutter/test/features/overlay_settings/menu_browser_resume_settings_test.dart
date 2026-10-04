import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_card.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';

import '../friends/social_layout_test.dart' show app, size, loadFonts, capture;

class MemoryBrowserResume implements MenuBrowserResumePort {
  MenuBrowserResume value = const MenuBrowserResume(0, false, null);
  int reads = 0, updates = 0;
  final writes = <String>[];
  bool readFails = false, writeFails = false;
  Completer<MenuBrowserResume>? pendingRead, pendingWrite;
  @override
  Future<MenuBrowserResume> read() async {
    ++reads;
    if (readFails) throw StateError('synthetic read failure');
    return pendingRead?.future ?? value;
  }

  @override
  Future<MenuBrowserResume> setEnabled(
    MenuBrowserResume saved,
    bool enabled,
  ) async {
    ++updates;
    if (writeFails || saved.revision != value.revision) {
      throw StateError('synthetic write failure');
    }
    return value = MenuBrowserResume(
      value.revision + 1,
      enabled,
      enabled ? value.url : null,
    );
  }

  @override
  Future<MenuBrowserResume> remember(
    MenuBrowserResume saved,
    String url,
  ) async {
    if (writeFails || !value.enabled || saved.revision != value.revision) {
      throw StateError('synthetic stale policy');
    }
    writes.add(url);
    if (pendingWrite case final pending?) {
      pendingWrite = null;
      return pending.future;
    }
    return value = MenuBrowserResume(saved.revision, true, url);
  }
}

void main() {
  setUpAll(loadFonts);
  test('enabled default from Host remembers a confirmed page without rewriting the preference', () async {
    final store = MemoryBrowserResume()
      ..value = const MenuBrowserResume(0, true, null);
    final controller = MenuBrowserResumeController(store);
    await controller.load();
    await controller.confirmed('https://example.invalid/default');
    expect(store.writes, ['https://example.invalid/default']);
    expect(store.updates, 0);
    controller.dispose();
  });
  test('explicit disabled choice; safe confirmed URLs de-duplicate and no timer reads', () async {
    final store = MemoryBrowserResume();
    final controller = MenuBrowserResumeController(store);
    await controller.load();
    await controller.confirmed('https://example.invalid/a');
    expect(store.writes, isEmpty);
    await controller.setEnabled(true);
    for (final url in [
      'about:blank',
      'file:///c:/a',
      'javascript:alert(1)',
      'https://user:password@example.invalid',
      'https://example.invalid/a',
    ]) {
      await controller.confirmed(url);
    }
    await controller.confirmed('https://example.invalid/a');
    expect(store.writes, ['https://example.invalid/a']);
    expect(store.reads, 1);
    await controller.setEnabled(false);
    expect(controller.saved!.url, isNull);
    expect(store.value.url, isNull);
    controller.dispose();
  });
  test(
    'slow URL write coalesces to the latest confirmed active page',
    () async {
      final store = MemoryBrowserResume()
        ..value = const MenuBrowserResume(1, true, null);
      final pending = Completer<MenuBrowserResume>();
      store.pendingWrite = pending;
      final c = MenuBrowserResumeController(store);
      await c.load();
      final first = c.confirmed('https://example.invalid/a');
      final second = c.confirmed('https://example.invalid/b');
      final third = c.confirmed('https://example.invalid/c');
      pending.complete(
        const MenuBrowserResume(1, true, 'https://example.invalid/a'),
      );
      await Future.wait([first, second, third]);
      expect(store.writes, [
        'https://example.invalid/a',
        'https://example.invalid/c',
      ]);
      expect(c.saved!.url, 'https://example.invalid/c');
      c.dispose();
    },
  );
  test(
    'disable wins over an in-flight old page reply and clears queued URLs',
    () async {
      final store = MemoryBrowserResume()
        ..value = const MenuBrowserResume(1, true, null);
      final pending = Completer<MenuBrowserResume>();
      store.pendingWrite = pending;
      final c = MenuBrowserResumeController(store);
      await c.load();
      final write = c.confirmed('https://example.invalid/old');
      c.confirmed('https://example.invalid/queued');
      await c.setEnabled(false);
      pending.complete(
        const MenuBrowserResume(1, true, 'https://example.invalid/old'),
      );
      await write;
      expect(c.saved!.enabled, false);
      expect(c.saved!.url, isNull);
      expect(store.writes.length, 1);
      expect(store.value.url, isNull);
      c.dispose();
    },
  );
  test(
    'read failure remains unknown; failed writes stop until explicit reload',
    () async {
      final store = MemoryBrowserResume()..readFails = true;
      final c = MenuBrowserResumeController(store);
      await c.load();
      expect(c.saved, isNull);
      expect(c.failed, true);
      await c.setEnabled(true);
      expect(store.updates, 0);
      store.readFails = false;
      store.value = const MenuBrowserResume(2, true, null);
      await c.load();
      store.writeFails = true;
      await c.confirmed('https://example.invalid/a');
      expect(c.saved, isNull);
      expect(c.failed, true);
      await c.confirmed('https://example.invalid/b');
      expect(store.reads, 2);
      expect(store.writes, isEmpty);
      c.dispose();
    },
  );
  test('disposed opening ignores a late account-local read', () async {
    final store = MemoryBrowserResume();
    final pending = Completer<MenuBrowserResume>();
    store.pendingRead = pending;
    final c = MenuBrowserResumeController(store);
    final load = c.load();
    c.dispose();
    pending.complete(
      const MenuBrowserResume(8, true, 'https://example.invalid/old'),
    );
    await load;
    expect(c.saved, isNull);
    expect(store.writes, isEmpty);
  });
  testWidgets(
    'explicit toggle persists immediately and never reveals URL or fake success',
    (tester) async {
      final store = MemoryBrowserResume();
      await tester.pumpWidget(app(MenuBrowserResumeCard(port: store)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('menu-browser-resume-toggle')),
            )
            .value,
        false,
      );
      await tester.tap(find.byKey(const Key('menu-browser-resume-toggle')));
      await tester.pumpAndSettle();
      expect(store.value.enabled, true);
      expect(store.updates, 1);
      store.writeFails = true;
      await tester.tap(find.byKey(const Key('menu-browser-resume-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('menu-browser-resume-toggle')), findsNothing);
      expect(
        find.byKey(const Key('menu-browser-resume-reload')),
        findsOneWidget,
      );
      expect(store.value.enabled, true);
      store.writeFails = false;
      await tester.tap(find.byKey(const Key('menu-browser-resume-reload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu-browser-resume-toggle')));
      await tester.pumpAndSettle();
      expect(store.value.enabled, false);
      expect(store.value.url, isNull);
    },
  );
  testWidgets('port replacement drops late read and old account URL', (
    tester,
  ) async {
    final first = MemoryBrowserResume(), second = MemoryBrowserResume();
    final pending = Completer<MenuBrowserResume>();
    first.pendingRead = pending;
    await tester.pumpWidget(app(MenuBrowserResumeCard(port: first)));
    await tester.pump();
    await tester.pumpWidget(app(MenuBrowserResumeCard(port: second)));
    await tester.pumpAndSettle();
    pending.complete(
      const MenuBrowserResume(9, true, 'https://example.invalid/private'),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const Key('menu-browser-resume-toggle')),
          )
          .value,
      false,
    );
    expect(find.textContaining('example.invalid'), findsNothing);
    expect(first.updates, 0);
  });
  for (final locale in AppStrings.supportedLocales) {
    for (final width in [320.0, 1040.0]) {
      testWidgets(
        'resume card layout $locale $width with readable privacy copy',
        (tester) async {
          size(tester, Size(width, 900));
          final store = MemoryBrowserResume()
            ..value = const MenuBrowserResume(
              1,
              true,
              'https://example.invalid/private',
            );
          final boundary = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: app(
                Builder(
                  builder: (context) => Localizations.override(
                    context: context,
                    locale: locale,
                    child: MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: const TextScaler.linear(1.8)),
                      child: SingleChildScrollView(
                        child: MenuBrowserResumeCard(port: store),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await capture(
            tester,
            boundary,
            'menu-browser-resume-${locale.toLanguageTag()}-${width.toInt()}',
          );
          if (width == 320) {
            final toggle = find.byKey(const Key('menu-browser-resume-toggle'));
            await tester.ensureVisible(toggle);
            await tester.pumpAndSettle();
            expect(
              tester
                  .getRect(toggle)
                  .overlaps(const Rect.fromLTWH(0, 0, 320, 900)),
              true,
            );
            final state = find.byKey(const Key('menu-browser-resume-state'));
            await tester.ensureVisible(state);
            await tester.pumpAndSettle();
            expect(
              tester
                  .getRect(state)
                  .overlaps(const Rect.fromLTWH(0, 0, 320, 900)),
              true,
            );
            await capture(
              tester,
              boundary,
              'menu-browser-resume-${locale.toLanguageTag()}-320-bottom',
            );
          }
          expect(find.textContaining('example.invalid'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
