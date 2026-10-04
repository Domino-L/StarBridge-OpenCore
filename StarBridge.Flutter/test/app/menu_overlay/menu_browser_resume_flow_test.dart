import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/overlay_settings/menu_browser_resume_controller.dart';
import 'package:starbridge_flutter/platform/window/menu_browser_resume.dart';

import 'menu_browser_tabs_test.dart'
    show BrowserFake, mount, workspace, flush, page;
import '../../features/overlay_settings/menu_browser_resume_settings_test.dart'
    show MemoryBrowserResume;

void main() {
  testWidgets(
    'optional restoration failure never disables normal browser controls',
    (tester) async {
      final native = BrowserFake()..tabs.clear();
      native.tabs.add(page('t1', url: 'about:blank'));
      native.failure = StateError('synthetic navigation failure');
      final work = workspace(),
          store = MemoryBrowserResume()
            ..value = const MenuBrowserResume(
              1,
              true,
              'https://example.invalid/saved',
            );
      final c = MenuBrowserResumeController(store);
      await mount(tester, native, work, resume: c);
      expect(find.textContaining('仍可正常浏览'), findsOneWidget);
      expect(find.textContaining('请确认已安装 WebView2'), findsNothing);
      expect(find.text('访问'), findsOneWidget);
      expect(store.value.url, 'https://example.invalid/saved');
      await tester.enterText(
        find.byKey(const ValueKey('browser-address')),
        'https://example.invalid/manual',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await flush(tester);
      expect(
        native.calls
            .where((call) => call.$1 == 'browserNavigate')
            .last
            .$2['url'],
        'https://example.invalid/manual',
      );
      expect(find.textContaining('仍可正常浏览'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      work.dispose();
    },
  );
  testWidgets(
    'user-opened single blank browser restores once; confirmed status uses same update path',
    (tester) async {
      final native = BrowserFake()..tabs.clear();
      native.tabs.add(page('t1', url: 'about:blank'));
      final work = workspace(),
          store = MemoryBrowserResume()
            ..value = const MenuBrowserResume(
              2,
              true,
              'https://example.invalid/saved',
            );
      final c = MenuBrowserResumeController(store);
      await mount(tester, native, work, resume: c);
      expect(
        native.calls
            .where((call) => call.$1 == 'browserNavigate')
            .single
            .$2['url'],
        store.value.url,
      );
      expect(store.reads, 1);
      expect(store.writes, isEmpty);
      native.tabs[0]['url'] = 'https://example.invalid/new';
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(store.writes, ['https://example.invalid/new']);
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(store.writes.length, 1);
      expect(store.reads, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      work.dispose();
    },
  );
  for (final shape in ['off', 'retained', 'multiple', 'loading', 'failed']) {
    testWidgets(
      'restore respects existing pages and disabled consent for $shape',
      (tester) async {
        final native = BrowserFake(),
            work = workspace(),
            store = MemoryBrowserResume();
        store.value = shape == 'off'
            ? const MenuBrowserResume(0, false, null)
            : const MenuBrowserResume(1, true, 'https://example.invalid/saved');
        if (shape != 'multiple') {
          native.tabs.clear();
          native.tabs.add(
            page(
              't1',
              url: shape == 'retained'
                  ? 'https://example.invalid/retained'
                  : 'about:blank',
              loading: shape == 'loading',
              failed: shape == 'failed',
            ),
          );
        }
        final c = MenuBrowserResumeController(store);
        await mount(tester, native, work, resume: c);
        expect(
          native.calls.where((call) => call.$1 == 'browserNavigate'),
          shape == 'off' ? hasLength(1) : isEmpty,
        );
        if (shape == 'off') {
          expect(native.tabs.single['url'], 'https://www.bing.com/');
        }
        if (shape != 'retained' && shape != 'multiple') {
          expect(store.writes, isEmpty);
        }
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        work.dispose();
      },
    );
  }
  testWidgets(
    'resume read failure keeps normal browsing and does not create consent',
    (tester) async {
      final native = BrowserFake(),
          work = workspace(),
          store = MemoryBrowserResume()..readFails = true;
      final c = MenuBrowserResumeController(store);
      await mount(tester, native, work, resume: c);
      expect(
        native.calls.where((call) => call.$1 == 'browserNavigate'),
        isEmpty,
      );
      expect(find.textContaining('仍可正常浏览'), findsOneWidget);
      expect(store.writes, isEmpty);
      expect(find.text('访问'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      work.dispose();
    },
  );
  testWidgets(
    'loading, failed and unavailable pages never replace the saved last page',
    (tester) async {
      final native = BrowserFake()..tabs.clear();
      native.tabs.add({
        ...page('t1', url: 'https://example.invalid/loading', loading: true),
        'unavailable': false,
      });
      final work = workspace(),
          store = MemoryBrowserResume()
            ..value = const MenuBrowserResume(
              1,
              true,
              'https://example.invalid/saved',
            );
      final c = MenuBrowserResumeController(store);
      await mount(tester, native, work, resume: c);
      native.tabs[0]['loading'] = false;
      native.tabs[0]['failed'] = true;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      native.tabs[0]['failed'] = false;
      native.tabs[0]['unavailable'] = true;
      await tester.pump(const Duration(seconds: 1));
      await flush(tester);
      expect(store.writes, isEmpty);
      expect(c.saved!.url, 'https://example.invalid/saved');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      work.dispose();
    },
  );
}
