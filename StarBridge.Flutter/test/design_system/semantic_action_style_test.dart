import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
}

void main() {
  for (final mode in AppearanceMode.values) {
    testWidgets(
      '$mode semantic actions preserve readable and disabled states',
      (tester) async {
        final tokens = FutureRestraintStyle.resolve(mode);
        final colors = tokens.colors;
        late BuildContext actionContext;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildStarBridgeTheme(tokens, const Locale('en')),
            home: Builder(
              builder: (context) {
                actionContext = context;
                return const SizedBox();
              },
            ),
          ),
        );
        for (final tone in ActionTone.values) {
          final (color, soft) = switch (tone) {
            ActionTone.danger => (colors.danger, colors.dangerSoft),
            ActionTone.warning => (colors.warning, colors.warningSoft),
            ActionTone.success => (colors.success, colors.successSoft),
            ActionTone.info => (colors.info, colors.infoSoft),
          };
          expect(contrast(color, soft), greaterThanOrEqualTo(4.5));
          expect(contrast(color, colors.onAccent), greaterThanOrEqualTo(4.5));
          for (final emphasis in ActionEmphasis.values) {
            final style = semanticActionStyle(
              actionContext,
              tone,
              emphasis: emphasis,
            );
            final filled = emphasis == ActionEmphasis.filled;
            expect(
              style.foregroundColor!.resolve({}),
              filled ? colors.onAccent : color,
            );
            expect(
              style.foregroundColor!.resolve({WidgetState.disabled}),
              colors.textDisabled,
            );
            expect(
              style.overlayColor!.resolve({WidgetState.disabled}),
              Colors.transparent,
            );
            expect(
              style.overlayColor!.resolve({WidgetState.hovered})!.a,
              greaterThan(0),
            );
            expect(
              style.overlayColor!.resolve({WidgetState.pressed})!.a,
              greaterThan(
                style.overlayColor!.resolve({WidgetState.hovered})!.a,
              ),
            );
            expect(style.side!.resolve({WidgetState.focused})!.width, 2);
            expect(
              style.side!.resolve({WidgetState.focused})!.color,
              filled ? colors.onAccent : color,
            );
            expect(
              style.minimumSize,
              isNull,
              reason: 'Shared theme retains button geometry',
            );
            if (filled) {
              expect(style.backgroundColor!.resolve({}), color);
              expect(
                style.backgroundColor!.resolve({WidgetState.disabled}),
                tokens.surfaces.raised.fill,
              );
            }
          }
        }
      },
    );
  }
}
