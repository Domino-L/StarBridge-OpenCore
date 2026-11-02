import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/features/settings/help_support_action.dart';
import 'package:starbridge_flutter/features/settings/help_support_live_content.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3dh_test.dart' show HelpPendingPort;
import 'interaction_batch3i_test.dart' show scopedApp;

Future<List<int>?> capture(WidgetTester t, GlobalKey key, String? name) =>
    t.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      try {
        if (name != null) {
          final file = File('build/reviews/interaction-batch3dh/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                .asUint8List(),
          );
        }
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
            .buffer
            .asUint8List()
            .toList();
      } finally {
        image.dispose();
      }
    });

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final name =
            '${suite.name}-${light ? 'light' : 'dark'}-${scale.toInt()}';
        testWidgets(
          '$name primary native bounds, active press and static reduced wait',
          (t) async {
            size(t, const Size(1200, 800));
            final controls = GlobalKey(), wait = GlobalKey();
            final state = ValueNotifier((false, true));
            var calls = 0;
            try {
              await t.pumpWidget(
                ValueListenableBuilder<(bool, bool)>(
                  valueListenable: state,
                  builder: (_, value, _) => scopedApp(
                    MediaQuery(
                      data: MediaQueryData(
                        textScaler: TextScaler.linear(scale),
                      ),
                      child: Material(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RepaintBoundary(
                              key: controls,
                              child: SizedBox(
                                width: 1000,
                                child: Column(
                                  children: [
                                    for (final icon in [false, true])
                                      SizedBox(
                                        height: 110,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceEvenly,
                                          children: [
                                            if (icon)
                                              FilledButton.icon(
                                                key: const Key('native-icon'),
                                                onPressed: value.$2
                                                    ? () {}
                                                    : null,
                                                icon: const StarBridgeIcon(
                                                  StarBridgeIconSemantic
                                                      .notifications,
                                                ),
                                                label: const Text('复制群号'),
                                              )
                                            else
                                              FilledButton(
                                                key: const Key('native-plain'),
                                                onPressed: value.$2
                                                    ? () {}
                                                    : null,
                                                child: const Text('发送反馈'),
                                              ),
                                            HelpSupportAction(
                                              controlKey: Key(
                                                'suite-${icon ? 'icon' : 'plain'}',
                                              ),
                                              kind:
                                                  StarBridgeActionKind.primary,
                                              icon: icon
                                                  ? StarBridgeIconSemantic
                                                        .notifications
                                                  : null,
                                              onActivate: value.$2
                                                  ? (_) => calls++
                                                  : null,
                                              child: Text(
                                                icon ? '复制群号' : '发送反馈',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            RepaintBoundary(
                              key: wait,
                              child: const SizedBox(
                                width: 600,
                                child: HelpSupportWaiting(
                                  label: '正在读取…',
                                  source: InteractionSource.pointer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    suite,
                    light: light,
                    reduce: value.$1,
                  ),
                ),
              );
              await t.pump();
              await t.pump();
              void geometry() {
                for (final variant in ['plain', 'icon']) {
                  expect(
                    t.getSize(find.byKey(Key('suite-$variant'))),
                    t.getSize(find.byKey(Key('native-$variant'))),
                  );
                }
              }

              geometry();
              final rest = await capture(t, controls, '$name-controls');
              final waiting = await capture(t, wait, '$name-wait');
              final gesture = await t.startGesture(
                t.getCenter(find.byKey(const Key('suite-plain'))),
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 120));
              expect(await capture(t, controls, '$name-press'), isNot(rest));
              expect(
                await capture(t, wait, '$name-wait-moving'),
                isNot(waiting),
              );
              await gesture.cancel();
              await t.pump(const Duration(milliseconds: 600));
              expect(calls, 0);
              state.value = (true, false);
              await t.pump();
              await t.pump();
              await t.pump(const Duration(milliseconds: 500));
              geometry();
              expect(find.byType(SuiteProgressBar), findsNothing);
              final reduced = await capture(t, wait, '$name-static');
              await t.pump(const Duration(milliseconds: 200));
              expect(await capture(t, wait, null), reduced);
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              state.dispose();
            }
          },
        );
        testWidgets(
          '$name actual feedback narrow form pending and failure preserve draft',
          (t) async {
            size(t, const Size(390, 1100));
            final form = GlobalKey();
            final port = HelpPendingPort();
            final message = TextEditingController(),
                contact = TextEditingController();
            try {
              await t.pumpWidget(
                scopedApp(
                  MediaQuery(
                    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                    child: Builder(
                      builder: (context) => RepaintBoundary(
                        key: form,
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: SingleChildScrollView(
                            child: HelpSupportFeedbackForm(
                              port: port,
                              message: message,
                              contact: contact,
                            ),
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
              await t.enterText(
                find.byKey(const Key('help-feedback-message')),
                'Synthetic draft',
              );
              await t.pumpAndSettle();
              await t.ensureVisible(
                find.byKey(const Key('help-feedback-send')),
              );
              await t.pumpAndSettle();
              await capture(t, form, '$name-form');
              await t.tap(find.byKey(const Key('help-feedback-send')));
              await t.pump();
              await t.pump(const Duration(milliseconds: 160));
              expect(port.sends, hasLength(1));
              expect(message.text, 'Synthetic draft');
              await capture(t, form, '$name-form-pending');
              port.sends.single.$3.completeError(StateError('fixture failure'));
              await t.pumpAndSettle();
              expect(message.text, 'Synthetic draft');
              expect(find.textContaining('内容已保留'), findsOneWidget);
              await capture(t, form, '$name-form-failed');
              expect(t.takeException(), isNull);
            } finally {
              for (final call in port.sends) {
                if (!call.$3.isCompleted) call.$3.complete();
              }
              await t.pumpWidget(const SizedBox());
              await t.pump();
              message.dispose();
              contact.dispose();
            }
          },
        );
      }
    }
  }
}
