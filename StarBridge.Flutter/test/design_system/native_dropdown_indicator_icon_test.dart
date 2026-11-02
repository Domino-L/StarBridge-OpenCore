import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/native_dropdown_indicator_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final expandMore in [false, true]) {
    for (final appearance in AppearanceMode.values) {
      for (final direction in TextDirection.values) {
        testWidgets('native indicator preserves exact glyph/theme/rotation '
            'expandMore=$expandMore $appearance $direction', (tester) async {
          Future<List<int>> render({
            required bool resolved,
            required double extent,
            required double angle,
          }) async {
            final theme = buildStarBridgeTheme(
              FutureRestraintStyle.resolve(appearance),
              const Locale('en', 'US'),
            );
            final Widget glyph = resolved
                ? expandMore
                      ? const NativeDropdownIndicatorIcon.expandMore()
                      : const NativeDropdownIndicatorIcon()
                : Icon(expandMore ? Icons.expand_more : Icons.arrow_drop_down);
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Directionality(
                  textDirection: direction,
                  child: Center(
                    child: RepaintBoundary(
                      key: const Key('native-indicator-image'),
                      child: SizedBox.square(
                        dimension: 80,
                        child: IconTheme(
                          data: IconThemeData(
                            size: extent,
                            color: theme.colorScheme.secondary,
                            opacity: .7,
                          ),
                          child: Center(
                            child: Transform.rotate(angle: angle, child: glyph),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final icon = tester.widget<Icon>(find.byType(Icon));
            expect(
              icon.icon,
              expandMore ? Icons.expand_more : Icons.arrow_drop_down,
            );
            expect(icon.size, isNull);
            expect(icon.color, isNull);
            expect(icon.semanticLabel, isNull);
            expect(tester.getSize(find.byType(Icon)), Size.square(extent));
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('native-indicator-image')),
            );
            return (await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final data = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                return data.buffer
                    .asUint8List(data.offsetInBytes, data.lengthInBytes)
                    .toList();
              } finally {
                image.dispose();
              }
            }))!;
          }

          for (final extent in [18.0, 30.0]) {
            for (final angle in [0.0, math.pi * .37, math.pi]) {
              final reference = await render(
                resolved: false,
                extent: extent,
                angle: angle,
              );
              final candidate = await render(
                resolved: true,
                extent: extent,
                angle: angle,
              );
              expect(
                candidate,
                orderedEquals(reference),
                reason:
                    'The resolver must preserve the exact native pixels '
                    'including ambient theme, extent and caller rotation.',
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
  for (final appearance in AppearanceMode.values) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'default field keeps SDK glyph geometry and ambient theme $appearance $direction',
        (tester) async {
          Future<List<int>> render({Widget? icon}) async {
            await tester.pumpWidget(
              MaterialApp(
                theme: buildStarBridgeTheme(
                  FutureRestraintStyle.resolve(appearance),
                  const Locale('en', 'US'),
                ),
                home: Directionality(
                  textDirection: direction,
                  child: Scaffold(
                    body: Center(
                      child: RepaintBoundary(
                        key: const Key('native-field-image'),
                        child: SizedBox(
                          width: 340,
                          height: 120,
                          child: StarBridgeSelectFormField<int>(
                            identity: 'bounded-native-field',
                            initialValue: 1,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Preset',
                              helperText: 'Local setting',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 1,
                                child: Text('Original choice'),
                              ),
                            ],
                            onChanged: (_) {},
                            icon: icon,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('native-field-image')),
            );
            return (await tester.runAsync(() async {
              final image = await boundary.toImage();
              try {
                final bytes = (await image.toByteData(
                  format: ui.ImageByteFormat.rawRgba,
                ))!;
                return bytes.buffer
                    .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes)
                    .toList();
              } finally {
                image.dispose();
              }
            }))!;
          }

          final sdk = await render(icon: const Icon(Icons.arrow_drop_down));
          expect(find.byType(NativeDropdownIndicatorIcon), findsNothing);
          final resolved = await render();
          expect(find.byType(NativeDropdownIndicatorIcon), findsOneWidget);
          expect(resolved.length, sdk.length);
          int? mismatch;
          for (var index = 0; index < sdk.length; index++) {
            if (resolved[index] != sdk[index]) {
              mismatch = index;
              break;
            }
          }
          expect(
            mismatch,
            isNull,
            reason: 'Moving glyph selection into the resolver must not change field pixels or baseline.',
          );
        },
      );
    }
  }
}
