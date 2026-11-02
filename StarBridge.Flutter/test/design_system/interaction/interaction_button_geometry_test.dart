import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, mount;
import 'interaction_batch3l_test.dart'
    show MotionInvitationPort, directory, clean;
import '../../features/party_rooms/party_rooms_test.dart' show ready;
import 'interaction_batch3p_test.dart' show capture;

Rect glyphRect(WidgetTester t, Finder target, String label) {
  final paragraph = t.renderObject<RenderParagraph>(target);
  final line = paragraph
      .getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      )
      .map((box) => box.toRect())
      .reduce((a, b) => a.expandToInclude(b));
  return line.shift(paragraph.localToGlobal(Offset.zero));
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets(
      '$suite actual room toolbar labels have balanced vertical space',
      (t) async {
        size(t, const Size(700, 250));
        await t.pumpWidget(
          scopedApp(
            Center(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (label, kind) in [
                    ('房间邀请 · 0', StarBridgeActionKind.secondary),
                    ('创建房间', StarBridgeActionKind.primary),
                    ('输入房间码', StarBridgeActionKind.secondary),
                  ])
                    StarBridgeActionButton(
                      key: ValueKey(label),
                      kind: kind,
                      onActivate: (_) {},
                      child: Text(label),
                    ),
                ],
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        for (final label in ['房间邀请 · 0', '创建房间', '输入房间码']) {
          final button = t.getRect(find.byKey(ValueKey(label)));
          final text = glyphRect(t, find.text(label), label);
          if (suite != InteractionSuite.standard) {
            expect(
              button.height,
              34,
              reason: 'Approved lab basic-button height',
            );
          }
          expect(
            (text.center.dy - button.center.dy).abs(),
            lessThanOrEqualTo(1),
            reason:
                '$label button=$button text=$text: text must not sit at the top',
          );
        }
      },
    );
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        '$suite $scale icon label and expanded button align without width growth',
        (t) async {
          size(t, const Size(700, 320));
          await t.pumpWidget(
            scopedApp(
              MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Center(
                  child: SizedBox(
                    width: 360,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final kind in StarBridgeActionKind.values)
                          SizedBox(
                            width: 360,
                            child: StarBridgeActionButton(
                              key: ValueKey(kind),
                              kind: kind,
                              onActivate: (_) {},
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add, size: 18),
                                  const SizedBox(width: 6),
                                  Text('确认 Confirm ${kind.name}'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          for (final kind in StarBridgeActionKind.values) {
            final button = t.getRect(find.byKey(ValueKey(kind)));
            final label = '确认 Confirm ${kind.name}';
            final text = glyphRect(t, find.text(label), label);
            expect(button.width, 360);
            expect(
              (button.center.dy - text.center.dy).abs(),
              lessThanOrEqualTo(1),
            );
          }
          expect(t.takeException(), isNull);
        },
      );
    }
    testWidgets(
      '$suite real room page toolbar uses centered production buttons',
      (t) async {
        final port = MotionInvitationPort()..result = ready(directory());
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        final buttons = find.descendant(
          of: find.byType(Wrap),
          matching: find.byType(StarBridgeActionButton),
        );
        var checked = 0;
        for (final element in buttons.evaluate()) {
          final labelFinder = find.descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(Text),
          );
          if (labelFinder.evaluate().length != 1) continue;
          final label = t.widget<Text>(labelFinder).data!;
          if (!label.contains('房间')) continue;
          final button = t.getRect(find.byWidget(element.widget));
          final text = glyphRect(t, labelFinder, label);
          expect(
            (text.center.dy - button.center.dy).abs(),
            lessThanOrEqualTo(1),
          );
          checked++;
        }
        expect(checked, greaterThanOrEqualTo(3));
        await clean(t, module);
      },
    );
  }
  testWidgets(
    'scan screenshot comparison matches lab proportions and centers glyphs',
    (t) async {
      size(t, const Size(650, 270));
      final frame = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: frame,
          child: scopedApp(
            Builder(
              builder: (context) {
                Widget row(int version) => Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, kind) in [
                      ('房间邀请 · 0', StarBridgeActionKind.secondary),
                      ('创建房间', StarBridgeActionKind.primary),
                      ('输入房间码', StarBridgeActionKind.secondary),
                    ])
                      if (version == 1)
                        StarBridgeActionButton(
                          kind: kind,
                          tone: label.startsWith('房间邀请')
                              ? ActionTone.info
                              : null,
                          onActivate: (_) {},
                          child: Text(label),
                        )
                      else
                        SuitePressable(
                          kind: kind == StarBridgeActionKind.primary
                              ? PressableKind.primary
                              : PressableKind.secondary,
                          minHeight: version == 0 ? 40 : 34,
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: version == 0 ? 0 : 8,
                          ),
                          onActivate: (_) {},
                          builder: (_, visual) => DefaultTextStyle.merge(
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: visual.foreground),
                            child: Text(label),
                          ),
                        ),
                  ],
                );
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('修复前'),
                      const SizedBox(height: 6),
                      row(0),
                      const SizedBox(height: 14),
                      const Text('修复后 · 恢复实验室比例与内容居中'),
                      const SizedBox(height: 6),
                      row(1),
                      const SizedBox(height: 14),
                      const Text('实验室按钮配方 · 同字号对照'),
                      const SizedBox(height: 6),
                      row(2),
                    ],
                  ),
                );
              },
            ),
            InteractionSuite.scan,
          ),
        ),
      );
      await t.pumpAndSettle();
      await capture(t, frame, 'scan-button-alignment-comparison');
      expect(t.takeException(), isNull);
    },
  );
}
