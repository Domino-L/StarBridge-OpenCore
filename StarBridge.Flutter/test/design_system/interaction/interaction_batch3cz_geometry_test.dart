import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/tray/tray_command_button.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        for (final english in [false, true]) {
          testWidgets(
            '$suite light=$light scale=$scale english=$english matches native tray icon geometry',
            (t) async {
              try {
                await t.pumpWidget(
                  scopedApp(
                    Builder(
                      builder: (context) => MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: Localizations.override(
                          context: context,
                          locale: english
                              ? const Locale('en')
                              : const Locale('zh', 'CN'),
                          child: Builder(
                            builder: (context) => Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final native in [true, false])
                                  for (final danger in [false, true])
                                    Builder(
                                      builder: (context) {
                                        final id =
                                            '${native ? 'native' : 'adapter'}-$danger';
                                        final label = english
                                            ? (danger
                                                  ? 'Quit StarBridge'
                                                  : 'Open StarBridge')
                                            : (danger ? '完全退出' : '打开星海舰桥');
                                        final style = danger
                                            ? OutlinedButton.styleFrom(
                                                foregroundColor: context
                                                    .tokens
                                                    .colors
                                                    .danger,
                                              )
                                            : null;
                                        const icon = StarBridgeIcon(
                                          StarBridgeIconSemantic.home,
                                        );
                                        return SizedBox(
                                          width: 304,
                                          child: native
                                              ? OutlinedButton.icon(
                                                  key: Key(id),
                                                  onPressed: () {},
                                                  style: style,
                                                  icon: icon,
                                                  label: Text(label),
                                                )
                                              : TrayCommandButton(
                                                  controlKey: Key(id),
                                                  label: label,
                                                  icon: icon,
                                                  style: style,
                                                  onPressed: () {},
                                                ),
                                        );
                                      },
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                  ),
                );
                await t.pumpAndSettle();
                for (final danger in [false, true]) {
                  (Size, Rect, Rect, double?, double?) sample(String prefix) {
                    final target = find.byKey(Key('$prefix-$danger'));
                    final rect = t.getRect(target);
                    final text = find.descendant(
                      of: target,
                      matching: find.byType(Text),
                    );
                    final icon = find.descendant(
                      of: target,
                      matching: find.byType(StarBridgeIcon),
                    );
                    final label = t.widget<Text>(text),
                        style = DefaultTextStyle.of(t.element(text)).style;
                    final actual = style.merge(label.style);
                    return (
                      rect.size,
                      t.getRect(text).shift(-rect.topLeft),
                      t.getRect(icon).shift(-rect.topLeft),
                      actual.fontSize,
                      actual.letterSpacing,
                    );
                  }

                  expect(sample('adapter'), sample('native'));
                }
                expect(t.takeException(), isNull);
              } finally {
                await t.pumpWidget(const SizedBox());
                await t.pump();
              }
            },
          );
        }
      }
    }
  }
}
