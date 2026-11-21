import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/brand/github_mark.dart';
import 'package:starbridge_flutter/design_system/brand/scm_brand_mark.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SCM brand mark preserves the approved upstream asset', (
    tester,
  ) async {
    expect(_pngSize(ScmBrandMark.markAssetPath), (width: 984, height: 1051));
    expect(_pngSize(ScmBrandMark.wordmarkAssetPath), (width: 937, height: 226));

    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: [FutureRestraintStyle.resolve(AppearanceMode.dark)],
        ),
        home: const Scaffold(body: Center(child: ScmBrandMark())),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel('SCM'), findsOneWidget);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => (image.image as AssetImage).assetName),
      [ScmBrandMark.markAssetPath, ScmBrandMark.wordmarkAssetPath],
    );
    semantics.dispose();
  });

  testWidgets('compact SCM mark remains available in light appearance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [FutureRestraintStyle.resolve(AppearanceMode.light)],
        ),
        home: const Scaffold(body: Center(child: ScmBrandMark.compact())),
      ),
    );
    await tester.pump();

    expect(find.byType(ScmBrandMark), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, ScmBrandMark.markAssetPath);
    expect(tester.takeException(), isNull);
  });

  // Help header (user 11-16): marks shown without their plate.
  for (final mode in AppearanceMode.values) {
    testWidgets('unframed SCM and GitHub marks keep their size in $mode', (
      tester,
    ) async {
      final light = mode == AppearanceMode.light;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: light ? Brightness.light : Brightness.dark,
            extensions: [FutureRestraintStyle.resolve(mode)],
          ),
          home: const Scaffold(
            body: Column(
              children: [
                ScmBrandMark(key: Key('framed')),
                ScmBrandMark(key: Key('bare'), framed: false),
                GitHubMark(key: Key('github')),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final framed = tester.getSize(find.byKey(const Key('framed')));
      expect(tester.getSize(find.byKey(const Key('bare'))), framed);
      expect(
        tester.getSize(find.byKey(const Key('github'))).height,
        framed.height,
      );
      final plates = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byKey(const Key('bare')),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).color);
      expect(plates.whereType<Color>(), isEmpty);
      final tints = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byKey(const Key('bare')),
              matching: find.byType(Image),
            ),
          )
          .map((image) => image.color);
      // Light-grey upstream art would vanish on a light surface.
      expect(tints.every((tint) => (tint != null) == light), isTrue);
      expect(find.bySemanticsLabel('GitHub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  return (width: header.getUint32(16), height: header.getUint32(20));
}
