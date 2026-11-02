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
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/features/communities/community_workspace_image.dart';

// User report 2026-10-20: "组织头像可能会突然消失 然后再恢复". A refresh that
// rebuilds the same (or a changed) image must keep the painted image until the
// replacement is ready; only a confirmed absence clears it.

Widget _frame(Widget child) => MaterialApp(
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    const Locale('en'),
  ),
  home: Center(child: SizedBox(width: 48, height: 48, child: child)),
);

void main() {
  testWidgets('organization image keeps its frame across refreshes', (
    tester,
  ) async {
    final source = (await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    ))!;
    var decodes = 0;
    Completer<void>? hold;
    Future<ui.Image> decoder(Uint8List bytes, int width) async {
      decodes++;
      final waiting = hold;
      if (waiting != null) await waiting.future;
      return source.clone();
    }

    Widget view(Uint8List? bytes) => _frame(
      CommunityWorkspaceImage(
        bytes: bytes,
        icon: StandardIconSemantic.brokenImage,
        decoder: decoder,
      ),
    );
    RawImage painted() => tester.widget<RawImage>(find.byType(RawImage));

    await tester.pumpWidget(view(Uint8List.fromList([1, 2, 3])));
    await tester.pump();
    expect(painted().image, isNotNull);

    // Same content in a new buffer (every refresh decodes base64 anew).
    await tester.pumpWidget(view(Uint8List.fromList([1, 2, 3])));
    expect(find.byType(CommunityImageLoading), findsNothing);
    expect(painted().image, isNotNull);
    expect(decodes, 1, reason: 'unchanged content is not decoded again');

    // Changed content: the old frame stays until the new one is ready.
    final pending = hold = Completer<void>();
    await tester.pumpWidget(view(Uint8List.fromList([4, 5, 6])));
    await tester.pump();
    expect(find.byType(CommunityImageLoading), findsNothing);
    expect(painted().image, isNotNull);
    pending.complete();
    hold = null;
    await tester.pump();
    expect(painted().image, isNotNull);
    expect(decodes, 2);

    // Confirmed removal clears immediately.
    await tester.pumpWidget(view(null));
    expect(find.byType(RawImage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    source.dispose();
  });

  testWidgets('organization logo never flashes loading when re-resolved', (
    tester,
  ) async {
    Future<String> png(int size) async {
      final image = await createTestImage(width: size, height: size);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return 'data:image/png;base64,${base64Encode(data!.buffer.asUint8List())}';
    }

    final first = (await tester.runAsync(() => png(2)))!;
    final second = (await tester.runAsync(() => png(3)))!;
    Widget view(String? data, Object row) =>
        _frame(CommunityLogo(data: data, downloadedBy: row, framed: false));

    await tester.pumpWidget(view(first, Object()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(CommunityImageLoading), findsNothing);

    // A refresh hands over a new row snapshot and a not-yet-decoded image.
    await tester.pumpWidget(view(second, Object()));
    expect(find.byType(CommunityImageLoading), findsNothing);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.byType(CommunityImageLoading), findsNothing);

    // Confirmed removal shows the fallback, not a stale logo.
    await tester.pumpWidget(view(null, Object()));
    expect(find.byType(Image), findsNothing);
  });
}
