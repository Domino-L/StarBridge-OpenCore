import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_feature_view.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_panel.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_rooms_session.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_module.dart';
import 'package:starbridge_flutter/features/party_rooms/room_chat_panel.dart';
import 'package:starbridge_flutter/features/party_rooms/room_preset_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_inspection_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/party_rooms/room_preset_test.dart' show PresetPort;
import '../../app/menu_overlay/menu_room_preset_test.dart' as menu;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp, route, dialogAction;
import 'interaction_batch3b_test.dart' show semanticTap;

class MotionPresetPort extends PresetPort
    implements OverlayPresetInspectionPort {
  int exports = 0, inspections = 0;
  int? importedRevision;
  String? importedPackage;
  bool failInspection = false;
  Completer<OverlayPresetTransfer>? inspecting;
  Completer<String>? importing;
  Completer<RoomPresetCatalog>? catalog;
  @override
  Future<RoomPresetCatalog> readPresets() =>
      catalog?.future ?? super.readPresets();
  @override
  Future<Map<String, Object?>> exportPreset(String id, int revision) {
    exports++;
    return super.exportPreset(id, revision);
  }

  @override
  Future<String> importPreset(String package, int revision) {
    imports++;
    importedPackage = package;
    importedRevision = revision;
    return importing?.future ?? Future.value('新增测试预设');
  }

  @override
  Future<OverlayPresetTransfer> inspectPreset(
    String package,
    int revision,
  ) async {
    inspections++;
    if (failInspection) throw const FormatException();
    return inspecting?.future ??
        OverlayPresetTransfer(
          name: '检查测试预设',
          settings: settings(),
          layout: layout,
        );
  }
}

Finder action(String label) =>
    find.widgetWithText(StarBridgeActionButton, label);
Finder get choice => find.byType(StarBridgeActionRow).last;

Future<void> keyPress(WidgetTester t, Finder target) async {
  final visualOnly = find.descendant(
    of: target,
    matching: find.byType(ExcludeFocus),
  );
  final anchor = visualOnly.evaluate().isNotEmpty
      ? visualOnly.first
      : find.descendant(of: target, matching: find.byType(Text)).first;
  final detectors = find.descendant(
    of: target,
    matching: find.byType(FocusableActionDetector),
  );
  final owner = detectors.evaluate().isEmpty
      ? null
      : t.widget<FocusableActionDetector>(detectors.first).focusNode;
  (owner ?? Focus.of(t.element(anchor))).requestFocus();
  await t.pump();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<void> activate(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  if (source == 'keyboard') {
    await keyPress(t, target);
  } else if (source == 'reader') {
    final label = t
        .widget<Text>(
          find.descendant(of: target, matching: find.byType(Text)).first,
        )
        .data!;
    await semanticTap(
      t,
      find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}\$')).last,
    );
    await t.pump();
    await t.pump();
  } else {
    await t.tap(target);
    await t.pump();
  }
}

class ChatHarness extends StatefulWidget {
  const ChatHarness(this.module, this.suite, {super.key});
  final RoomChatModule module;
  final InteractionSuite suite;
  @override
  State<ChatHarness> createState() => ChatHarnessState();
}

class ChatHarnessState extends State<ChatHarness> {
  bool reduce = false;
  void reduced() => setState(() => reduce = true);
  @override
  Widget build(BuildContext context) => scopedApp(
    RoomChatPanel(module: widget.module),
    widget.suite,
    reduce: reduce,
  );
}

Future<(RoomChatModule, ChatHarnessState)> mountChat(
  WidgetTester t,
  MotionPresetPort port,
  InteractionSuite suite, {
  GlobalKey? frame,
}) async {
  size(t, const Size(1280, 1000));
  final card = await port.example.exportPreset('example-preset', 1);
  final message = RoomChatMessage(
    sequence: 1,
    id: 'shared-message',
    sender: '合成用户',
    text: '',
    time: DateTime.utc(2026),
    attachment: card,
  );
  port.reading = (_, _) async => RoomChatPage([message], 1, false);
  final module = RoomChatModule(port)..setRoom('one');
  addTearDown(module.dispose);
  await t.pump();
  final key = GlobalKey<ChatHarnessState>();
  final app = ChatHarness(module, suite, key: key);
  await t.pumpWidget(
    frame == null ? app : RepaintBoundary(key: frame, child: app),
  );
  await t.pumpAndSettle();
  return (module, key.currentState!);
}

Future<void> clean(WidgetTester t, RoomChatModule module) async {
  await t.pumpWidget(const SizedBox());
  module.setRoom(null);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3M'] != '1') return;
  await t.runAsync(() async {
    final image =
        await (frame.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    try {
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      final dir = Directory('build/reviews/interaction-batch3m');
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
    testWidgets(
      '$suite real menu picker retains keyboard source and text through export',
      (t) async {
        size(t, const Size(1440, 1000));
        final port = menu.PresetPort();
        final frame = ValueNotifier(const MenuFeatureView('loading'));
        final session = MenuRoomsSession(
          port,
          (raw) => frame.value = MenuFeatureView.parse(raw),
        )..show(true);
        await t.pump();
        await t.pumpWidget(
          scopedApp(
            ValueListenableBuilder<MenuFeatureView>(
              valueListenable: frame,
              builder: (_, view, _) => MenuRoomsPanel(
                view: view,
                onAction: session.act,
                active: true,
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('menu-channel-draft')),
          '菜单文字草稿',
        );
        await keyPress(t, action('分享浮层方案'));
        expect(route(t).animation!.value, 1);
        await keyPress(t, dialogAction('取消'));
        expect(port.roomChat.exports, 0);
        expect(find.text('菜单文字草稿'), findsOneWidget);
        await keyPress(t, action('分享浮层方案'));
        final picker = route(t);
        port.roomChat.heldExport = Completer();
        await keyPress(t, choice);
        expect(port.roomChat.exports, 1);
        expect(t.widget<StarBridgeActionRow>(choice).onActivate, isNull);
        expect(port.roomChat.sends, 0);
        port.roomChat.heldExport!.complete(menu.PresetChat.attachment);
        await t.pump();
        await t.pump();
        await t.pump();
        expect(picker.animation?.value ?? 0, 0);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('菜单文字草稿'), findsOneWidget);
        await t.tap(find.byKey(const Key('menu-room-clear-preset')));
        await t.pumpAndSettle();
        expect(frame.value.chat!.preset!.draftName, isNull);
        expect(port.roomChat.sends, 0);
        await keyPress(t, action('分享浮层方案'));
        unawaited(
          showDialog<void>(
            context: t.element(find.byType(AlertDialog)),
            builder: (_) => const AlertDialog(content: Text('菜单上的独立窗口')),
          ),
        );
        await t.pump();
        port.changes.add(null);
        await t.pumpAndSettle();
        expect(find.text('菜单上的独立窗口'), findsOneWidget);
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        session.dispose();
        frame.dispose();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      },
    );

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source preset selection prepares only and retains text',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final port = MotionPresetPort();
            final frame = GlobalKey();
            final (module, _) = await mountChat(t, port, suite, frame: frame);
            await t.enterText(
              find.byKey(const Key('room-chat-draft')),
              '保留文字草稿',
            );
            await activate(t, action('分享浮层方案'), source);
            if (source != 'pointer') expect(route(t).animation!.value, 1);
            await t.pumpAndSettle();
            if (source == 'pointer') {
              await capture(t, frame, '${suite.name}-picker');
            }
            await keyPress(t, dialogAction('取消'));
            expect(port.exports, 0);
            expect(module.draft, '保留文字草稿');
            await activate(t, action('分享浮层方案'), source);
            await t.pumpAndSettle();
            await activate(t, choice, source);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            expect(port.exports, 1);
            expect(port.sends, 0);
            expect(module.attachmentDraft, isNotNull);
            expect(module.draft, '保留文字草稿');
            final clear = find.byType(StarBridgeIconAction).last;
            await t.tap(clear);
            await t.pumpAndSettle();
            expect(module.attachmentDraft, isNull);
            expect(module.draft, '保留文字草稿');
            await clean(t, module);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite inspection cancel then confirm imports once after authoritative completion',
      (t) async {
        final port = MotionPresetPort()..importing = Completer<String>();
        final frame = GlobalKey();
        final (module, harness) = await mountChat(t, port, suite, frame: frame);
        await keyPress(t, action('导入为新方案'));
        final outer = route(t);
        for (final confirm in [false, true]) {
          await keyPress(t, dialogAction('导入为新方案'));
          expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
          expect(route(t).animation!.value, 1);
          expect(port.imports, 0);
          await capture(t, frame, '${suite.name}-inspection');
          if (!confirm) {
            await keyPress(t, dialogAction('取消'));
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(port.imports, 0);
          } else {
            harness.reduced();
            await t.pump();
            await t.pump();
            await keyPress(t, find.byKey(const Key('overlay-import-confirm')));
            expect(port.imports, 1);
            expect(port.importedRevision, 1);
            expect(
              port.importedPackage,
              module.messages.single.attachment!['overlayPresetPackage'],
            );
            expect(
              t.widget<StarBridgeActionButton>(dialogAction('取消')).onActivate,
              isNull,
            );
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(AlertDialog), findsOneWidget);
            port.importing!.complete('新增测试预设');
            await t.pump();
            await t.pump();
            expect(outer.animation?.value ?? 0, 0);
            expect(find.byType(AlertDialog), findsNothing);
            expect(port.imports, 1);
            expect(port.sends, 0);
          }
        }
        await clean(t, module);
      },
    );

    testWidgets(
      '$suite context loss while inspection is open removes owned dialogs without import',
      (t) async {
        final port = MotionPresetPort();
        final (module, _) = await mountChat(t, port, suite);
        await keyPress(t, action('导入为新方案'));
        await keyPress(t, dialogAction('导入为新方案'));
        expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
        module.setRoom(null);
        await t.pump();
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await t.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.imports, 0);
        await clean(t, module);
      },
    );

    testWidgets(
      '$suite context loss never closes an unrelated route above inspection',
      (t) async {
        final port = MotionPresetPort();
        final (module, _) = await mountChat(t, port, suite);
        await keyPress(t, action('导入为新方案'));
        await keyPress(t, dialogAction('导入为新方案'));
        unawaited(
          showDialog<void>(
            context: t.element(find.byType(OverlayPresetImportPreview)),
            builder: (_) => const AlertDialog(content: Text('独立窗口')),
          ),
        );
        await t.pump();
        module.setRoom(null);
        await t.pumpAndSettle();
        expect(find.text('独立窗口'), findsOneWidget);
        expect(find.byType(AlertDialog, skipOffstage: false), findsOneWidget);
        expect(port.imports, 0);
        await clean(t, module);
      },
    );

    testWidgets(
      '$suite late export and late inspection cannot mutate a new room',
      (t) async {
        final port = MotionPresetPort()..exporting = Completer();
        final (module, _) = await mountChat(t, port, suite);
        await keyPress(t, action('分享浮层方案'));
        await keyPress(t, choice);
        expect(port.exports, 1);
        module.setRoom('two');
        port.exporting!.complete(
          await port.example.exportPreset('example-preset', 1),
        );
        await t.pumpAndSettle();
        expect(module.attachmentDraft, isNull);
        expect(find.byType(AlertDialog), findsNothing);
        port.inspecting = Completer();
        await keyPress(t, action('导入为新方案'));
        await keyPress(t, dialogAction('导入为新方案'));
        module.setRoom(null);
        port.inspecting!.complete(
          OverlayPresetTransfer(
            name: '迟到检查',
            settings: settings(),
            layout: layout,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(port.imports, 0);
        await clean(t, module);
      },
    );

    for (final failure in ['inspection', 'unknownImport']) {
      testWidgets('$suite $failure does not import again or claim success', (
        t,
      ) async {
        final port = MotionPresetPort()
          ..failInspection = failure == 'inspection'
          ..importing = Completer();
        final (module, _) = await mountChat(t, port, suite);
        await keyPress(t, action('导入为新方案'));
        await keyPress(t, dialogAction('导入为新方案'));
        if (failure == 'unknownImport') {
          await keyPress(t, find.byKey(const Key('overlay-import-confirm')));
          port.importing!.completeError(
            const RoomChatFailure('outcomeUnknown'),
          );
          await t.pump();
          await t.pump();
        }
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          t.widget<StarBridgeActionButton>(dialogAction('导入为新方案')).onActivate,
          isNull,
        );
        expect(port.imports, failure == 'inspection' ? 0 : 1);
        expect(find.byType(SnackBar), findsNothing);
        await keyPress(t, dialogAction('取消'));
        await clean(t, module);
      });
    }
  }
}
