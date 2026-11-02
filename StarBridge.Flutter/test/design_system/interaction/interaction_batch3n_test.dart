import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/features/communities/community_chat_panel.dart';
import 'package:starbridge_flutter/features/communities/community_preset_dialog.dart';
import 'package:starbridge_flutter/features/communities/example_communities.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_inspection_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';

import '../../features/communities/community_preset_test.dart'
    show PresetFake, card;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, route, dialogAction;
import 'interaction_batch3m_test.dart' show keyPress, activate;
import 'interaction_batch3b_test.dart' show semanticTap;

class InspectingPort extends PresetFake implements OverlayPresetInspectionPort {
  int inspections = 0;
  bool inspectionFails = false;
  Completer<OverlayPresetTransfer>? inspecting;
  Completer<String>? importing;
  Completer<Map<String, Object?>>? exporting;
  @override
  Future<OverlayPresetTransfer> inspectPreset(
    String package,
    int revision,
  ) async {
    inspections++;
    if (inspectionFails) throw const FormatException();
    return inspecting?.future ?? preview;
  }

  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int version,
  ) async {
    final value = await super.importCommunityPreset(attachment, version);
    return importing?.future ?? value;
  }

  @override
  Future<Map<String, Object?>> exportCommunityPreset(
    String id,
    int version,
  ) async {
    final value = await super.exportCommunityPreset(id, version);
    return exporting?.future ?? value;
  }
}

OverlayPresetTransfer get preview =>
    OverlayPresetTransfer(name: '检查样例', settings: settings(), layout: layout);
Finder action(String name) => find.widgetWithText(StarBridgeActionButton, name);
Finder get choice => find.byType(StarBridgeActionRow).last;
const target = '00000000000000000000000000000002';

class Harness extends StatefulWidget {
  const Harness(this.port, this.suite, {super.key, this.onResult});
  final InspectingPort port;
  final InteractionSuite suite;
  final ValueChanged<Object?>? onResult;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  bool reduce = false;
  void reduced() => setState(() => reduce = true);
  @override
  Widget build(BuildContext context) => scopedApp(
    Builder(
      builder: (context) => Row(
        children: [
          for (final importing in [false, true])
            StarBridgeActionButton(
              onActivate: (source) async {
                final result = await showCommunityPresetDialog(
                  context,
                  port: widget.port,
                  attachment: importing ? card : null,
                  source: source,
                );
                widget.onResult?.call(result);
              },
              child: Text(importing ? '打开导入' : '打开分享'),
            ),
        ],
      ),
    ),
    widget.suite,
    reduce: reduce,
  );
}

Future<HarnessState> mount(
  WidgetTester t,
  InspectingPort port,
  InteractionSuite suite, {
  ValueChanged<Object?>? onResult,
  GlobalKey? frame,
}) async {
  size(t, const Size(1200, 1000));
  addTearDown(port.changes.close);
  final key = GlobalKey<HarnessState>();
  final app = Harness(port, suite, key: key, onResult: onResult);
  await t.pumpWidget(
    frame == null ? app : RepaintBoundary(key: frame, child: app),
  );
  await t.pumpAndSettle();
  return key.currentState!;
}

Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3N'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3n');
      await dir.create(recursive: true);
      await File('${dir.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite real community $source shares without sending and imports through card',
        (t) async {
          final semantics = t.ensureSemantics();
          final example = ExampleCommunities();
          addTearDown(example.close);
          try {
            size(t, const Size(1200, 1000));
            await t.pumpWidget(
              scopedApp(
                CommunityChatPanel(
                  port: example,
                  targetRef: target,
                  name: '样例组织',
                  onBack: () {},
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            final input = find.byKey(const Key('community-chat-input'));
            await t.enterText(input, '保留组织聊天草稿');
            await activate(t, action('分享浮层方案'), source);
            if (source != 'pointer') expect(route(t).animation!.value, 1);
            await t.pumpAndSettle();
            await keyPress(t, dialogAction('关闭'));
            expect(t.widget<TextField>(input).controller!.text, '保留组织聊天草稿');
            await activate(t, action('分享浮层方案'), source);
            await t.pumpAndSettle();
            await activate(t, choice, source);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              (await example.readChat(target, after: 56)).messages,
              isEmpty,
            );
            await t.tap(find.widgetWithText(StarBridgeActionButton, '发送'));
            await t.pumpAndSettle();
            expect(
              (await example.readChat(
                target,
                after: 56,
              )).messages.single.hasAttachment,
              isTrue,
            );
            if (source == 'reader') {
              // Card semantics intentionally include the title and preview
              // description in the one actionable node.
              await semanticTap(
                t,
                find.bySemanticsLabel(RegExp('查看详情并导入\$')).last,
              );
              await t.pump();
              await t.pump();
            } else {
              await activate(t, action('查看详情并导入'), source);
            }
            if (source != 'pointer') expect(route(t).animation!.value, 1);
            await t.pumpAndSettle();
            expect(
              (await example.readCommunityPresets()).presets,
              hasLength(1),
            );
            await keyPress(t, dialogAction('导入为新方案'));
            expect(
              (await example.readCommunityPresets()).presets,
              hasLength(2),
            );
            expect(action('导入为新方案'), findsNothing);
            await keyPress(t, dialogAction('关闭'));
            await finish(t);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite inspection cancel retry confirm retains success and reduced motion',
      (t) async {
        final port = InspectingPort()..importing = Completer();
        final frame = GlobalKey();
        final harness = await mount(t, port, suite, frame: frame);
        await keyPress(t, action('打开导入'));
        await keyPress(t, dialogAction('导入为新方案'));
        expect(port.imports, 0);
        expect(route(t).animation!.value, 1);
        await capture(t, frame, '${suite.name}-inspection');
        await keyPress(t, dialogAction('取消'));
        expect(port.imports, 0);
        await keyPress(t, dialogAction('导入为新方案'));
        harness.reduced();
        await t.pump();
        await t.pump();
        await keyPress(t, find.byKey(const Key('overlay-import-confirm')));
        expect(port.imports, 1);
        expect(
          t.widget<StarBridgeActionButton>(dialogAction('关闭')).onActivate,
          isNull,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(CommunityPresetDialog), findsOneWidget);
        port.importing!.complete('Fixture');
        await t.pumpAndSettle();
        expect(find.text('已新增方案: Fixture'), findsOneWidget);
        expect(action('导入为新方案'), findsNothing);
        await capture(t, frame, '${suite.name}-success');
        await keyPress(t, dialogAction('关闭'));
        await finish(t);
      },
    );
    testWidgets(
      '$suite invalidation removes owned inspection but keeps unrelated route and identity notice',
      (t) async {
        final port = InspectingPort();
        await mount(t, port, suite);
        await keyPress(t, action('打开导入'));
        await keyPress(t, dialogAction('导入为新方案'));
        unawaited(
          showDialog<void>(
            context: t.element(find.byType(OverlayPresetImportPreview)),
            builder: (_) => const AlertDialog(content: Text('独立窗口')),
          ),
        );
        await t.pump();
        port.changes.add(null);
        await t.pumpAndSettle();
        expect(find.text('独立窗口'), findsOneWidget);
        expect(
          find.byType(OverlayPresetImportPreview, skipOffstage: false),
          findsNothing,
        );
        expect(port.imports, 0);
        Navigator.of(t.element(find.text('独立窗口'))).pop();
        await t.pumpAndSettle();
        expect(find.textContaining('账号状态'), findsOneWidget);
        await keyPress(t, dialogAction('关闭'));
        await finish(t);
      },
    );
    for (final stage in ['export', 'inspection', 'import']) {
      testWidgets(
        '$suite invalidation rejects late $stage without success or draft',
        (t) async {
          final port = InspectingPort();
          Object? result;
          if (stage == 'export') port.exporting = Completer();
          if (stage == 'inspection') port.inspecting = Completer();
          if (stage == 'import') port.importing = Completer();
          await mount(t, port, suite, onResult: (value) => result = value);
          await keyPress(t, action(stage == 'export' ? '打开分享' : '打开导入'));
          await keyPress(
            t,
            stage == 'export' ? choice : dialogAction('导入为新方案'),
          );
          if (stage == 'import') {
            await keyPress(t, find.byKey(const Key('overlay-import-confirm')));
          }
          port.changes.add(null);
          if (stage == 'export') port.exporting!.complete(card);
          if (stage == 'inspection') port.inspecting!.complete(preview);
          if (stage == 'import') port.importing!.complete('Late');
          await t.pumpAndSettle();
          expect(result, isNull);
          expect(find.textContaining('已新增方案:'), findsNothing);
          expect(find.textContaining('账号状态'), findsOneWidget);
          expect(port.imports, stage == 'import' ? 1 : 0);
          await keyPress(t, dialogAction('关闭'));
          await finish(t);
        },
      );
    }
    for (final failure in ['presetImportUnknown', 'presetChanged']) {
      testWidgets(
        '$suite $failure preserves uncertainty versus reread contract',
        (t) async {
          final port = InspectingPort()..failure = failure;
          await mount(t, port, suite);
          await keyPress(t, action('打开导入'));
          await keyPress(t, dialogAction('导入为新方案'));
          await keyPress(t, find.byKey(const Key('overlay-import-confirm')));
          await t.pump();
          await t.pump();
          expect(port.imports, 1);
          expect(action('导入为新方案'), findsNothing);
          if (failure == 'presetImportUnknown') {
            expect(action('重试'), findsNothing);
            expect(find.textContaining('避免重复导入'), findsOneWidget);
          } else {
            await keyPress(t, action('重试'));
            expect(port.reads, 2);
            expect(port.imports, 1);
            expect(action('导入为新方案'), findsOneWidget);
          }
          await keyPress(t, dialogAction('关闭'));
          await finish(t);
        },
      );
    }
  }
}
