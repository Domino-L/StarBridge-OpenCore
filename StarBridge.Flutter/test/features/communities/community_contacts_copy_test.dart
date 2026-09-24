import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_port.dart';

import 'community_workspace_test.dart';
import 'community_workspace_view_test.dart' show host;

void main() {
  late WorkspaceTestPort port;
  late List<String> writes;
  setUp(() {
    port = WorkspaceTestPort();
    writes = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            writes.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await port.changes.close();
  });
  Future<void> open(WidgetTester tester, Locale locale) async {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(port, locale));
    await tester.pumpAndSettle();
    // The small-window header moves contact actions into its details sheet.
    await tester.tap(find.byKey(const Key('community-open-details')));
    await tester.pumpAndSettle();
    final copyAll = find.byKey(const Key('community-copy-all-contacts'));
    if (copyAll.evaluate().isNotEmpty) await tester.ensureVisible(copyAll);
    await tester.pumpAndSettle();
  }

  for (final locale in [const Locale('zh', 'CN'), const Locale('en')]) {
    testWidgets('copy all uses displayed contacts and WPF separators $locale', (
      tester,
    ) async {
      await open(tester, locale);
      await tester.tap(find.byKey(const Key('community-copy-all-contacts')));
      await tester.pumpAndSettle();
      expect(writes, [
        locale.languageCode == 'zh'
            ? 'Discord：organization-contact\r\n网站：https://example.org'
            : 'Discord: organization-contact\r\nWebsite: https://example.org',
      ]);
      expect(writes.single, isNot(contains('must-not-be-rendered')));
      expect(
        find.text(
          locale.languageCode == 'zh' ? '全部联系方式已复制。' : 'All contacts copied.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('single copy retains just the selected value', (tester) async {
    await open(tester, const Locale('zh', 'CN'));
    await tester.tap(find.byTooltip('复制').first);
    await tester.pumpAndSettle();
    expect(writes, ['organization-contact']);
    expect(find.text('已复制'), findsOneWidget);
  });
  testWidgets('clipboard failure explains selectable manual fallback', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard_busy');
          }
          return null;
        });
    await open(tester, const Locale('zh', 'CN'));
    await tester.tap(find.byKey(const Key('community-copy-all-contacts')));
    await tester.pumpAndSettle();
    expect(find.text('无法访问剪贴板，请选中文字手动复制。'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SelectableText &&
            widget.data!.contains('organization-contact'),
      ),
      findsOneWidget,
    );
    expect(find.text('全部联系方式已复制。'), findsNothing);
  });
  testWidgets('account change suppresses late clipboard feedback', (
    tester,
  ) async {
    final reply = Completer<Object?>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') return reply.future;
          return null;
        });
    await open(tester, const Locale('zh', 'CN'));
    await tester.tap(find.byKey(const Key('community-copy-all-contacts')));
    await tester.pump();
    port.changes.add(null);
    reply.complete();
    await tester.pumpAndSettle();
    expect(find.text('全部联系方式已复制。'), findsNothing);
    expect(find.textContaining('organization-contact'), findsNothing);
    expect(find.byKey(const Key('community-copy-all-contacts')), findsNothing);
  });
  testWidgets('empty contacts do not offer empty clipboard writes', (
    tester,
  ) async {
    port.reader = (target, query, offset) async => CommunityWorkspace.parse({
      ...workspacePayload(target: target, query: query),
      'externalContacts': <Object>[],
      'websiteUrl': null,
    });
    await open(tester, const Locale('en'));
    expect(find.byKey(const Key('community-copy-all-contacts')), findsNothing);
    expect(writes, isEmpty);
  });
}
