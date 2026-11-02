import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_slider.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3cn_visual_test.dart' as render;
import 'interaction_batch3cr_test.dart' show RecordingThumb;

FocusNode focus(WidgetTester t) {
  final raw = t.widget(find.byKey(const Key('control')));
  return raw is Slider ? raw.focusNode! : (raw as SuiteSlider).focusNode!;
}

SemanticsNode sliderNode(SemanticsNode root) {
  final nodes = <SemanticsNode>[];
  void visit(SemanticsNode node) {
    if (node.getSemanticsData().flagsCollection.isSlider) nodes.add(node);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  expect(nodes, hasLength(1));
  return nodes.single;
}

void main() {
  setUpAll(loadFonts);
  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final scale in [1.0, 2.0]) {
      for (final rtl in [false, true]) {
        for (final divisions in [null, 100]) {
          for (final value in [.2, .8]) {
            testWidgets(
              'native geometry $platform text=$scale rtl=$rtl divisions=$divisions value=$value',
              (t) async {
                var native = true;
                late StateSetter update;
                final centers = <Offset>[];
                await t.pumpWidget(
                  StatefulBuilder(
                    builder: (_, state) {
                      update = state;
                      return scopedApp(
                        Builder(
                          builder: (context) => Theme(
                            data: Theme.of(context).copyWith(
                              platform: platform,
                              visualDensity: platform == TargetPlatform.macOS
                                  ? VisualDensity.standard
                                  : VisualDensity.compact,
                            ),
                            child: MediaQuery(
                              data: MediaQuery.of(
                                context,
                              ).copyWith(textScaler: TextScaler.linear(scale)),
                              child: Directionality(
                                textDirection: rtl
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                child: Align(
                                  alignment: Alignment.topLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      left: 61,
                                      top: 39,
                                    ),
                                    child: SizedBox(
                                      width: 300,
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          thumbShape: RecordingThumb(
                                            centers.add,
                                          ),
                                        ),
                                        child: native
                                            ? Slider(
                                                key: const Key('geometry'),
                                                value: value,
                                                divisions: divisions,
                                                onChanged: (_) {},
                                              )
                                            : StarBridgeSlider(
                                                controlKey: const Key(
                                                  'geometry',
                                                ),
                                                value: value,
                                                divisions: divisions,
                                                onChanged: (_) {},
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        InteractionSuite.standard,
                        reduce: true,
                      );
                    },
                  ),
                );
                await t.pumpAndSettle();
                final rect = t.getRect(find.byKey(const Key('geometry')));
                final center = centers.last;
                update(() => native = false);
                await t.pumpAndSettle();
                expect(t.getRect(find.byKey(const Key('geometry'))), rect);
                expect(centers.last, center);
                await t.pumpWidget(const SizedBox());
              },
            );
          }
        }
      }
    }
  }
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final source in ['keyboard', 'reader', 'reduce']) {
        testWidgets(
          '$suite light=$light $source has no visual tail while showing real value',
          (t) async {
            final semantics = t.ensureSemantics();
            var value = .4, reduce = false;
            late StateSetter update;
            final frame = GlobalKey();
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, state) {
                  update = state;
                  return scopedApp(
                    Center(
                      child: RepaintBoundary(
                        key: frame,
                        child: ColoredBox(
                          color: light
                              ? const Color(0xffedf4f7)
                              : const Color(0xff0c151c),
                          child: SizedBox(
                            width: 320,
                            height: 56,
                            child: StarBridgeSlider(
                              controlKey: const Key('control'),
                              semanticLabel: 'Value',
                              divisions: 100,
                              value: value,
                              valueLabel: (v) => '${(v * 100).round()}%',
                              onChanged: (v) => state(() => value = v),
                            ),
                          ),
                        ),
                      ),
                    ),
                    suite,
                    reduce: reduce,
                    light: light,
                  );
                },
              ),
            );
            await t.pumpAndSettle();
            if (source == 'keyboard') {
              focus(t).requestFocus();
              await t.pump();
              await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
            } else if (source == 'reader') {
              final node = sliderNode(
                t.getSemantics(find.byType(StarBridgeSlider)),
              );
              t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
                node.id,
                ui.SemanticsAction.increase,
              );
            } else {
              final rect = t.getRect(find.byKey(const Key('control')));
              await t.tapAt(Offset(rect.right - 60, rect.center.dy));
              await t.pump(const Duration(milliseconds: 20));
              update(() => reduce = true);
            }
            for (var i = 0; i < 3; i++) {
              await t.pump();
            }
            expect(value, greaterThan(.4));
            final root = sliderNode(
              t.getSemantics(find.byType(StarBridgeSlider)),
            );
            expect(root.getSemanticsData().value, '${(value * 100).round()}%');
            final first = await render.pixels(t, find.byKey(frame));
            await t.pump(const Duration(milliseconds: 90));
            final next = await render.pixels(t, find.byKey(frame));
            expect(next, first);
            final name = '${suite.name}-${light ? 'light' : 'dark'}-$source';
            final directory = Directory('build/reviews/interaction-batch3cr')
              ..createSync(recursive: true);
            File('${directory.path}/$name.png').writeAsBytesSync(next);
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
  }
}
