import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/communities/community_chat_media_cache.dart';
import 'package:starbridge_flutter/features/communities/community_chat_message_tile.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_chat_media_cache_test.dart'
    show MediaPort, message;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;

final _review = visualOutputDir(
  'interaction_motion_batch3gg_20261017',
  legacySubdirectory: 'review',
);
Finder marker(String part) => find.byKey(ValueKey('community-chat-$part-wait'));

class _Probe {
  _Probe(this.suite, {this.cached = false});
  final InteractionSuite suite;
  final bool cached;
  final port = MediaPort();
  CommunityChatMediaCache? cache;
  final boundary = GlobalKey();
  late StateSetter update;
  bool reduce = false, large = false;
  String target = 'a' * 32;
  var item = message(1, attachment: true);
  SemanticsHandle? semantics;

  Widget app() => RepaintBoundary(
    key: boundary,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        return scopedApp(
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
              child: Center(
                child: SizedBox(
                  width: 620,
                  child: SingleChildScrollView(
                    child: CommunityChatMessageTile(
                      port: port,
                      targetRef: target,
                      message: item,
                      mediaCache: cache,
                    ),
                  ),
                ),
              ),
            ),
          ),
          suite,
          reduce: reduce,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
      },
    ),
  );
  Future<void> mount(WidgetTester t, {bool fail = false}) async {
    port.fail = fail;
    if (!fail) port.gate = Completer<void>();
    if (cached) cache = CommunityChatMediaCache(port, target);
    size(t, const Size(1100, 800));
    semantics = t.ensureSemantics();
    await t.pumpWidget(app());
    await frames(t);
  }

  Future<void> retry(WidgetTester t, String source) async {
    port.fail = false;
    port.gate = Completer<void>();
    await actTarget(
      t,
      find.widgetWithText(StarBridgeActionButton, '重试'),
      source,
    );
    await frames(t);
  }

  Future<void> clean(WidgetTester t) async {
    semantics?.dispose();
    semantics = null;
    await t.pumpWidget(const SizedBox());
    cache?.dispose();
    if (port.gate case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    await frames(t);
    await t.runAsync(port.changes.close);
    expect(t.takeException(), isNull);
  }
}

void waits(WidgetTester t, {required bool animated}) {
  for (final part in ['avatar', 'attachment']) {
    expect(marker(part), findsOneWidget);
    expect(
      find.descendant(of: marker(part), matching: find.byType(SocialReadActivity)),
      findsOneWidget,
    );
    final busy = find.descendant(
      of: marker(part),
      matching: find.byType(SuiteBusyFrame),
    );
    expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
  }
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p, {
  bool save = false,
}) async => (await t.runAsync(() async {
  final boundary =
      p.boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    if (save) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_review).create(recursive: true);
      await File('$_review/${p.suite.name}-retry.png')
          .writeAsBytes(png!.buffer.asUint8List());
    }
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rect = t.getRect(marker('attachment'));
    final raw = bytes!.buffer.asUint8List();
    return <int>[
      for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
        ...raw.sublist(
          (y * image.width + rect.left.ceil()) * 4,
          (y * image.width + rect.right.floor()) * 4,
        ),
    ];
  } finally {
    image.dispose();
  }
}))!;

void main() {
  setUpAll(loadFonts);
  testWidgets('3gg passive media has static suite waits', (t) async {
    final p = _Probe(InteractionSuite.scan);
    await p.mount(t);
    waits(t, animated: false);
    expect(p.port.calls, hasLength(1));
    await p.clean(t);
  });
  testWidgets('3gg mouse retry has same-source avatar and attachment waits', (
    t,
  ) async {
    final p = _Probe(InteractionSuite.rail);
    await p.mount(t, fail: true);
    await p.retry(t, 'pointer');
    waits(t, animated: true);
    expect(p.port.calls, hasLength(2));
    await p.clean(t);
  });
  for (final suite in InteractionSuite.values) {
    testWidgets('3gg $suite background cache read stays static', (t) async {
      final p = _Probe(suite, cached: true);
      await p.mount(t);
      waits(t, animated: false);
      final a = await pixels(t, p);
      await frames(t, 20);
      expect(changed(a, await pixels(t, p)), 0);
      expect(p.port.calls, hasLength(1));
      await p.clean(t);
    });
    testWidgets('3gg $suite rejected retry keeps original explicit retry', (
      t,
    ) async {
      final p = _Probe(suite)..reduce = true;
      await p.mount(t, fail: true);
      await p.retry(t, 'pointer');
      waits(t, animated: false);
      p.port.fail = true;
      p.port.gate!.complete();
      await frames(t);
      expect(marker('attachment'), findsNothing);
      expect(find.widgetWithText(StarBridgeActionButton, '重试'), findsOneWidget);
      expect(p.port.calls, hasLength(2));
      await frames(t, 40);
      expect(p.port.calls, hasLength(2));
      await p.retry(t, 'keyboard');
      waits(t, animated: false);
      expect(p.port.calls, hasLength(3));
      await p.clean(t);
    });
    for (final cached in [false, true]) {
      for (final source in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '3gg $suite cache=$cached $source retry preserves original request',
          (t) async {
            final p = _Probe(suite, cached: cached);
            await p.mount(t, fail: true);
            expect(marker('attachment'), findsNothing);
            await p.retry(t, source);
            waits(t, animated: source == 'pointer');
            expect(p.port.calls, [p.item.messageRef, p.item.messageRef]);
            p.port.gate!.complete();
            await frames(t);
            expect(marker('attachment'), findsNothing);
            expect(find.text(p.item.messageRef), findsOneWidget);
            expect(p.port.calls, hasLength(2));
            await p.clean(t);
          },
        );
      }
    }
    testWidgets('3gg $suite invalidation retires held retry without replay', (
      t,
    ) async {
      final p = _Probe(suite, cached: true);
      await p.mount(t, fail: true);
      await p.retry(t, 'pointer');
      p.port.changes.add(null);
      await frames(t);
      expect(marker('attachment'), findsNothing);
      p.port.gate!.complete();
      await frames(t);
      expect(find.text(p.item.messageRef), findsNothing);
      expect(p.port.calls, hasLength(2));
      await p.clean(t);
    });
    testWidgets('3gg $suite new message read cannot borrow old mouse source', (
      t,
    ) async {
      final p = _Probe(suite);
      await p.mount(t, fail: true);
      await p.retry(t, 'pointer');
      final old = p.port.gate!;
      p.port.gate = Completer<void>();
      p.update(() => p.item = message(2, attachment: true));
      await frames(t);
      waits(t, animated: false);
      old.complete();
      await frames(t);
      waits(t, animated: false);
      expect(p.port.calls, hasLength(3));
      await p.clean(t);
    });
    testWidgets('3gg $suite retry review and reduce without geometry change', (
      t,
    ) async {
      final p = _Probe(suite)..large = true;
      await p.mount(t, fail: true);
      await p.retry(t, 'pointer');
      waits(t, animated: true);
      final rect = t.getRect(marker('attachment'));
      expect(rect.size, const Size(36, 36));
      final a = await pixels(t, p, save: true);
      await frames(t, 13);
      expect(changed(a, await pixels(t, p)), greaterThan(0));
      p.update(() => p.reduce = true);
      await frames(t, 2);
      waits(t, animated: false);
      final b = await pixels(t, p);
      await frames(t, 38);
      expect(changed(b, await pixels(t, p)), 0);
      expect(t.getRect(marker('attachment')), rect);
      await p.clean(t);
    });
  }
}
