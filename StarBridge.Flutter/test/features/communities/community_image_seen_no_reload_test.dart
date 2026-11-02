import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/communities/community_image_decoder.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

// User acceptance 2026-10-21 (build 11, V-1/V-2): "V 部分还会出现加载". An
// image already shown must not go back to a loading state when its row is
// recycled by scrolling or rebuilt, even though the bytes are in memory.

Widget _frame(Widget child) => MaterialApp(
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: Center(child: SizedBox(width: 48, height: 48, child: child)),
);

void main() {
  testWidgets('a recycled member row shows a seen avatar in its first frame', (
    tester,
  ) async {
    final source = (await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    ))!;
    var decodes = 0;
    final cache = CommunityImageDecodeCache(
      decoder: (bytes, width) async {
        decodes++;
        return source.clone();
      },
      capacity: 256,
    );
    final bytes = Uint8List.fromList([1, 2, 3]);
    Widget row({required bool peek}) => _frame(
      CommunityWorkspaceImage(
        bytes: bytes,
        icon: StandardIconSemantic.person,
        maxWidth: 96,
        decoder: cache.decode,
        peek: peek ? cache.peek : null,
      ),
    );

    await tester.pumpWidget(row(peek: true));
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);

    // Control: without the decoded-frame lookup, a remounted row waits a frame.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(row(peek: false));
    expect(find.byType(CommunityImageLoading), findsOneWidget);
    await tester.pump();

    // Scrolled out and back in: same bytes, new State, first frame painted.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(row(peek: true));
    expect(find.byType(CommunityImageLoading), findsNothing);
    expect(tester.widget<RawImage>(find.byType(RawImage)).image, isNotNull);
    expect(
      decodes,
      1,
      reason: 'the decoded frame is reused, not decoded again',
    );

    await tester.pumpWidget(const SizedBox());
    cache.dispose();
    source.dispose();
  });

  testWidgets('the decoded-frame cache keeps the most recent frames', (
    tester,
  ) async {
    final source = (await tester.runAsync(
      () => createTestImage(width: 2, height: 2),
    ))!;
    final cache = CommunityImageDecodeCache(
      decoder: (bytes, width) async => source.clone(),
      capacity: 4,
    );
    final rows = [
      for (var i = 0; i < 6; i++) Uint8List.fromList([i]),
    ];
    for (final bytes in rows) {
      (await tester.runAsync(() => cache.decode(bytes, 96)))!.dispose();
    }
    expect(cache.peek(rows.first, 96), isNull, reason: 'oldest evicted');
    final recent = cache.peek(rows.last, 96);
    expect(recent, isNotNull);
    recent!.dispose();
    expect(cache.peek(rows.last, 128), isNull, reason: 'size is part of key');
    cache.dispose();
    expect(cache.peek(rows.last, 96), isNull, reason: 'disposed at boundary');
    source.dispose();
  });

  testWidgets('a rebuilt organization logo never shows the loading spinner', (
    tester,
  ) async {
    final png = (await tester.runAsync(() async {
      final image = await createTestImage(width: 3, height: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
    }))!;
    Widget logo() =>
        _frame(CommunityLogo(data: png, downloadedBy: Object(), framed: false));

    await tester.pumpWidget(logo());
    expect(find.byType(CommunityImageLoading), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    // Rebuilt in a new tree position (e.g. a badge appears): a new State.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(logo());
    expect(find.byType(CommunityImageLoading), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the loading trace counts a seen image waiting again', (
    tester,
  ) async {
    final source = (await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    ))!;
    final cache = CommunityImageDecodeCache(
      decoder: (bytes, width) async => source.clone(),
    );
    final rows = <Map<String, Object>>[];
    var tick = 0;
    final metrics = LoadingMetrics(nowUs: () => tick++, write: rows.add);
    final bytes = Uint8List.fromList([7, 8, 9]);
    Future<void> mount({required bool peek}) => runZoned(
      () => tester.pumpWidget(
        _frame(
          CommunityWorkspaceImage(
            bytes: bytes,
            icon: StandardIconSemantic.person,
            maxWidth: 96,
            decoder: cache.decode,
            peek: peek ? cache.peek : null,
          ),
        ),
      ),
      zoneValues: {loadingMetricsZoneKey: metrics},
    );
    Iterable<Map<String, Object>> regressions() =>
        rows.where((row) => row['kind'] == 'imageRegressed');

    await mount(peek: true);
    await runZoned(tester.pump, zoneValues: {loadingMetricsZoneKey: metrics});
    expect(regressions(), isEmpty, reason: 'a first load is not a regression');

    await tester.pumpWidget(const SizedBox());
    await mount(peek: false);
    expect(regressions().single['cause'], 'redecode');
    await runZoned(tester.pump, zoneValues: {loadingMetricsZoneKey: metrics});

    await tester.pumpWidget(const SizedBox());
    await mount(peek: true);
    expect(
      regressions(),
      hasLength(1),
      reason: 'the fixed path never regresses',
    );

    await tester.pumpWidget(const SizedBox());
    metrics.stop();
    cache.dispose();
    source.dispose();
  });
}
