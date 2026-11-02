import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_room_preset_control.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_preset_port.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../app/menu_overlay/menu_room_preset_test.dart' as original;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, dialogAction;
import 'interaction_batch3m_test.dart' show activate, action, choice, keyPress;

final _review = visualOutputDir(
  'interaction_motion_batch3ft_20261017',
  legacySubdirectory: 'review',
);
const _catalogKey = Key('menu-room-preset-catalog-wait');
const _prepareKey = Key('menu-room-preset-prepare-wait');
const _catalog = RoomPresetCatalog(99123, [
  RoomPresetChoice('private-preset-id', '测试预设'),
]);

class _Chat extends original.PresetChat {
  Completer<RoomPresetCatalog>? heldCatalog;
  @override
  Future<RoomPresetCatalog> readPresets() {
    if (heldCatalog case final pending?) {
      catalogs++;
      return pending.future;
    }
    return super.readPresets();
  }
}

class _Port extends original.PresetPort {
  @override
  // ignore: overridden_fields
  final _Chat roomChat = _Chat();
}

class _Probe {
  _Probe(this.suite, {this.light = false, this.large = false}) {
    session = MenuRoomsSession(
      port,
      (raw) => frame.value = MenuFeatureView.parse(raw),
    )..show(true);
  }
  final port = _Port();
  final frame = ValueNotifier(const MenuFeatureView('loading'));
  late final MenuRoomsSession session;
  final capture = GlobalKey();
  InteractionSuite suite;
  bool reduce = false, light, large;
  late StateSetter update;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, state) {
        update = state;
        final base = scopedApp(
          ValueListenableBuilder<MenuFeatureView>(
            valueListenable: frame,
            builder: (_, view, _) =>
                MenuRoomsPanel(view: view, onAction: session.act, active: true),
          ),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
}

Future<void> frames(WidgetTester t, [int count = 30]) async {
  for (var i = 0; i < count; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}

// ignore: library_private_types_in_public_api
Future<void> mount(WidgetTester t, _Probe p) async {
  size(t, const Size(1200, 1100));
  await t.pump();
  await t.pumpWidget(p.app());
  await frames(t);
  if (find.byKey(const Key('menu-channel-draft')).evaluate().isEmpty) {
    // At 1.5 text scale the real compact workspace starts on Members.
    await keyPress(t, find.byKey(const ValueKey('community-section-chat')));
    await frames(t);
  }
  await t.enterText(find.byKey(const Key('menu-channel-draft')), '菜单文字草稿');
  await t.pump();
}

Future<void> open(WidgetTester t, String source) async {
  await activate(t, action('分享浮层方案'), source);
  await frames(t);
}

void waitState(WidgetTester t, Key key, {required bool animate}) {
  final waiting = find.byKey(key);
  expect(waiting, findsOneWidget);
  expect(t.widget(waiting), isA<SocialReadActivity>());
  final busy = find.descendant(
    of: waiting,
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animate);
}

// ignore: library_private_types_in_public_api
Future<void> clean(WidgetTester t, _Probe p) async {
  await t.pumpWidget(const SizedBox());
  p.session.dispose();
  // Retire the fixture's held futures after disposal; do not leave the
  // production session's original Future.timeout timer pending in the test.
  final catalog = p.port.roomChat.heldCatalog;
  if (catalog != null && !catalog.isCompleted) catalog.complete(_catalog);
  final export = p.port.roomChat.heldExport;
  if (export != null && !export.isCompleted) {
    export.complete(original.PresetChat.attachment);
  }
  await frames(t, 2);
  p.frame.dispose();
  await p.port.close();
  await frames(t, 2);
  expect(t.takeException(), isNull);
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect region, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = region.top.ceil(); y < region.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + region.left.ceil()) * 4,
            (y * image.width + region.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

int changed(List<int> a, List<int> b) {
  expect(a.length, b.length);
  var result = 0;
  for (var i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      result++;
    }
  }
  return result;
}

void main() {
  setUpAll(loadFonts);

  testWidgets('3ft current keyboard catalog must stop indeterminate waiting', (
    t,
  ) async {
    final p = _Probe(InteractionSuite.rail);
    p.port.roomChat.heldCatalog = Completer();
    try {
      await mount(t, p);
      await open(t, 'keyboard');
      final marker = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(
        t.widget<LinearProgressIndicator>(marker).value,
        isNotNull,
        reason: 'Keyboard wait must remain visible without looping',
      );
    } finally {
      await clean(t, p);
    }
  });

  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3ft $suite $source catalog then prepare rejection and retry keep original draft owner',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = _Probe(suite);
          final catalog = p.port.roomChat.heldCatalog = Completer();
          try {
            await mount(t, p);
            await open(t, source);
            waitState(t, _catalogKey, animate: source == 'pointer');
            expect(p.port.roomChat.catalogs, 1);
            expect(p.port.roomChat.exports, 0);
            catalog.complete(_catalog);
            await frames(t);
            final preparing = p.port.roomChat.heldExport = Completer();
            final preparingSource = source == 'pointer'
                ? 'keyboard'
                : 'pointer';
            await activate(t, choice, preparingSource);
            await frames(t);
            waitState(t, _prepareKey, animate: preparingSource == 'pointer');
            expect(p.port.roomChat.exports, 1);
            expect(p.port.roomChat.exportedId, 'private-preset-id');
            expect(p.port.roomChat.exportedRevision, 99123);
            expect(p.frame.value.chat!.preset!.draftName, isNull);
            expect(p.port.roomChat.sends, 0);
            // Existing picker stays cancellable while a local prepare is pending.
            expect(
              t.widget<StarBridgeActionButton>(dialogAction('取消')).onActivate,
              isNotNull,
            );
            preparing.completeError(const RoomChatFailure('unavailable'));
            await frames(t);
            expect(find.byKey(_prepareKey), findsNothing);
            expect(p.frame.value.chat!.preset!.error, 'unavailable');
            expect(p.frame.value.chat!.preset!.draftName, isNull);
            expect(find.text('菜单文字草稿'), findsOneWidget);
            await keyPress(t, dialogAction('取消'));
            await frames(t);
            p.port.roomChat.heldCatalog = null;
            p.port.roomChat.heldExport = null;
            await open(t, source);
            await activate(t, choice, source);
            await frames(t);
            expect(find.byType(AlertDialog), findsNothing);
            expect(p.port.roomChat.catalogs, 2);
            expect(p.port.roomChat.exports, 2);
            expect(p.port.roomChat.sends, 0);
            expect(p.frame.value.chat!.preset!.draftName, '测试预设');
            expect(find.text('菜单文字草稿'), findsOneWidget);
          } finally {
            await clean(t, p);
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '3ft $suite cancelled catalog ignores disposed picker and can reopen',
      (t) async {
        final p = _Probe(suite);
        final catalog = p.port.roomChat.heldCatalog = Completer();
        try {
          await mount(t, p);
          await open(t, 'keyboard');
          waitState(t, _catalogKey, animate: false);
          await keyPress(t, dialogAction('取消'));
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          catalog.complete(_catalog);
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(p.port.roomChat.exports, 0);
          p.port.roomChat.heldCatalog = null;
          await open(t, 'keyboard');
          expect(find.text('测试预设'), findsOneWidget);
          expect(p.port.roomChat.catalogs, 2);
        } finally {
          await clean(t, p);
        }
      },
    );

    testWidgets(
      '3ft $suite cancelling picker does not cancel already-authorized local export',
      (t) async {
        final p = _Probe(suite);
        try {
          await mount(t, p);
          await open(t, 'keyboard');
          final export = p.port.roomChat.heldExport = Completer();
          await activate(t, choice, 'keyboard');
          await frames(t);
          waitState(t, _prepareKey, animate: false);
          await keyPress(t, dialogAction('取消'));
          await frames(t);
          export.complete(original.PresetChat.attachment);
          await frames(t);
          expect(find.byType(AlertDialog), findsNothing);
          expect(p.frame.value.chat!.preset!.draftName, '测试预设');
          expect(p.port.roomChat.exports, 1);
          expect(p.port.roomChat.sends, 0);
          expect(find.byType(MenuRoomPresetAttachment), findsOneWidget);
        } finally {
          await clean(t, p);
        }
      },
    );

    for (final phase in ['catalog', 'prepare']) {
      testWidgets(
        '3ft $suite account invalidation while $phase discards late result',
        (t) async {
          final p = _Probe(suite);
          final catalog = phase == 'catalog'
              ? p.port.roomChat.heldCatalog = Completer()
              : null;
          final export = phase == 'prepare'
              ? p.port.roomChat.heldExport = Completer()
              : null;
          try {
            await mount(t, p);
            await open(t, 'keyboard');
            if (phase == 'prepare') {
              await activate(t, choice, 'keyboard');
              await frames(t);
            }
            p.port.changes.add(null);
            await frames(t);
            catalog?.complete(_catalog);
            export?.complete(original.PresetChat.attachment);
            await frames(t);
            expect(find.byType(AlertDialog), findsNothing);
            expect(p.frame.value.chat?.preset?.draftName, isNull);
            expect(p.port.roomChat.sends, 0);
          } finally {
            await clean(t, p);
          }
        },
      );
    }

    for (final light in [false, true]) {
      testWidgets(
        '3ft $suite light=$light shared catalog pixels freeze live reduced motion',
        (t) async {
          final p = _Probe(suite, light: light, large: true);
          final catalog = p.port.roomChat.heldCatalog = Completer();
          try {
            await mount(t, p);
            await open(t, 'pointer');
            waitState(t, _catalogKey, animate: true);
            final rect = t.getRect(find.byKey(_catalogKey));
            final before = await pixels(
              t,
              p,
              rect,
              png: '${suite.name}-${light ? 'light' : 'dark'}',
            );
            await frames(t, 17);
            final moving = changed(before, await pixels(t, p, rect));
            expect(moving, greaterThan(0));
            p.update(() {
              p.reduce = true;
            });
            await t.pump();
            await t.pump();
            waitState(t, _catalogKey, animate: false);
            final stopped = await pixels(t, p, rect);
            await frames(t, 38);
            final staticPixels = changed(stopped, await pixels(t, p, rect));
            expect(staticPixels, 0);
            expect(t.getRect(find.byKey(_catalogKey)), rect);
            expect(p.port.roomChat.catalogs, 1);
            await t.runAsync(
              () =>
                  File(
                    '$_review/${suite.name}-${light ? 'light' : 'dark'}.json',
                  ).writeAsString(
                    jsonEncode({
                      'movingPixels': moving,
                      'staticPixels': staticPixels,
                      'rect': [rect.left, rect.top, rect.width, rect.height],
                    }),
                  ),
            );
            catalog.complete(_catalog);
            await frames(t);
            expect(find.byKey(_catalogKey), findsNothing);
          } finally {
            await clean(t, p);
          }
        },
      );
    }
  }
}
