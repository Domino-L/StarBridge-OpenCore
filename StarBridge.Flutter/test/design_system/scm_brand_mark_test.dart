import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

({int width, int height}) _pngSize(String path) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  return (width: header.getUint32(16), height: header.getUint32(20));
}
