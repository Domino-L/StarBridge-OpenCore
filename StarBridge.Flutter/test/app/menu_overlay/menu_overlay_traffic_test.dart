import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_layout_sync.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_overlay_surface_app.dart';
import 'package:starbridge_flutter/platform/window/menu_window_preferences.dart';
import 'package:starbridge_flutter/platform/window/menu_live_presentation_feeds.dart';
import 'package:starbridge_flutter/platform/window/menu_notice.dart';

import 'menu_overlay_surface_app_test.dart' show channel, push, snapshot;

class _Notices extends ValueNotifier<MenuNotice?> implements MenuNoticeSource {
  _Notices() : super(const MenuNotice('Fixture', 'Visible notice'));
  var clears = 0;
  @override
  void clear() {
    clears++;
    value = null;
  }
}

void main() {
  testWidgets('a real surface drag sends bounded, final window geometry', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.reset);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'ready' ? snapshot(0, wanted: false) : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    const prefs = MenuWindowPreferences(
      3,
      {
        'version': 1,
        'panels': [],
        'open': ['friends'],
      },
      {
        'showClock': true,
        'showContext': true,
        'dimming': .5,
        'restoreDesktop': true,
      },
    );
    await tester.pumpWidget(
      const MenuOverlaySurfaceApp(workspacePreview: true),
    );
    await push(tester, {
      ...snapshot(1),
      'liveFriends': true,
      'preferences': prefs.encode(),
    });
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('menu-tool-friends')));
    await tester.pump(const Duration(seconds: 1));
    final handle = find.byKey(const ValueKey('menu-move-friends'));
    expect(handle, findsOneWidget);
    final panel = find.byKey(const ValueKey('menu-panel-friends'));
    final before = tester.getRect(panel);
    calls.clear();
    // 120 pointer updates inside one frame, as a high-rate mouse reports.
    final gesture = await tester.startGesture(tester.getCenter(handle));
    for (var i = 0; i < 120; i++) {
      await gesture.moveBy(const Offset(1, 0.5));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    final sent = calls.where((c) => c.method == 'preferencesChanged').toList();
    expect(sent.length, inInclusiveRange(1, 3));
    final after = tester.getRect(panel);
    expect(after.left, greaterThan(before.left + 50));
    final last = MenuWindowPreferences.parse(
      jsonDecode((sent.last.arguments as Map)['payload'] as String),
    )!;
    final friends = (last.layout['panels'] as List).cast<Map>().singleWhere(
      (p) => p['id'] == 'friends',
    );
    final bounds = (friends['bounds'] as List).cast<num>();
    expect(bounds[0], closeTo(after.left, 1), reason: 'final geometry kept');
    expect(bounds[1], closeTo(after.top, 1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('drag geometry crosses engines at most once per frame interval', (
    tester,
  ) async {
    var sent = 0;
    final sync = MenuLayoutSync(() => sent++);
    sync.changed();
    expect(sent, 1, reason: 'a single change (open/close) is not delayed');
    // A high-rate mouse reports many updates inside one frame interval.
    for (var i = 0; i < 40; i++) {
      sync.changed();
    }
    expect(sent, 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(sent, 2, reason: 'the trailing send carries the latest geometry');
    await tester.pump(const Duration(milliseconds: 16));
    expect(sent, 2, reason: 'no repeat once the drag is idle');

    for (var frame = 0; frame < 10; frame++) {
      for (var i = 0; i < 10; i++) {
        sync.changed();
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(sent, inInclusiveRange(11, 13), reason: '100 updates, ~10 frames');
    await tester.pump(const Duration(milliseconds: 32));
    final settled = sent;

    sync.changed();
    sync.changed();
    sync.cancel();
    await tester.pump(const Duration(milliseconds: 32));
    expect(sent, settled + 1, reason: 'a disposed surface sends nothing late');
  });

  test('only a real settings change dismisses the visible menu notice', () {
    final notices = _Notices();
    final feeds = MenuLivePresentationFeeds();
    Map settings(bool notifications) => {
      'social': {
        'friendSort': 'onlineFirst',
        'notifications': notifications,
        'preview': 'fullContent',
      },
    };
    feeds.start(
      notices: () => notices,
      settings: settings(true),
      isCurrent: () => true,
      publish: (_, _) {},
    );
    for (var i = 0; i < 20; i++) {
      // Every dragged-window geometry update re-applies unchanged settings.
      feeds.updateSettings(settings(true));
    }
    expect(notices.clears, 0);
    expect(notices.value?.message, 'Visible notice');
    feeds.updateSettings(settings(false));
    expect(notices.clears, 1);
    expect(notices.value, isNull);
    feeds.stop();
  });

  test('unchanged status rows are not resent within one opening', () {
    final feeds = MenuLivePresentationFeeds();
    final row = ['Ship', 'Location', 'Server', 'Shard', 'Fleet'];
    final first = feeds.changedContext(row);
    expect(first, MenuLivePresentationFeeds.contextPayload(row));
    expect(feeds.changedContext(List.of(row)), isNull);
    final moved = [...row.take(4), 'Fleet 2'];
    expect(feeds.changedContext(moved), isNotNull);
    expect(feeds.changedContext(moved), isNull);
    expect(feeds.changedContext(['too', 'short']), isNull);
    feeds.stop();
    expect(
      feeds.changedContext(moved),
      isNotNull,
      reason: 'a new opening always receives its first status row',
    );
  });
}
