import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_page.dart';
import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'interaction_batch3h_test.dart' show fleetApp;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/party_rooms/party_rooms_test.dart'
    show ready, room, wire;
import '../../features/party_rooms/room_management_test.dart'
    show ManagementPort;

Widget scopedApp(
  Widget child,
  InteractionSuite suite, {
  bool reduce = false,
  bool light = false,
}) {
  final base = fleetApp(
    child,
    suite: suite,
    reduce: reduce,
    light: light,
  ) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: base.theme,
    themeAnimationDuration: Duration.zero,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    builder: (context, child) => StarBridgeInteractionConfiguration(
      suite: suite,
      reduceMotion: reduce,
      child: child!,
    ),
    home: base.home,
  );
}

class RoomHarness extends StatefulWidget {
  const RoomHarness(this.module, this.suite, {super.key});
  final PartyRoomsModule module;
  final InteractionSuite suite;
  @override
  State<RoomHarness> createState() => RoomHarnessState();
}

class RoomHarnessState extends State<RoomHarness> {
  late var suite = widget.suite;
  var reduce = false, light = false;
  void change(VoidCallback update) => setState(update);
  @override
  Widget build(BuildContext context) => scopedApp(
    PartyRoomsPage(module: widget.module),
    suite,
    reduce: reduce,
    light: light,
  );
}

class MotionRoomPort extends ManagementPort {
  final commands = <RoomCommand>[];
  Completer<RoomCommandResult> next = Completer();
  @override
  Future<RoomCommandResult> execute(RoomCommand command) {
    calls++;
    commands.add(command);
    return next.future;
  }
}

Future<RoomHarnessState> mount(
  WidgetTester t,
  PartyRoomsModule module,
  InteractionSuite suite, {
  GlobalKey? frame,
}) async {
  size(t, const Size(1280, 1000));
  addTearDown(module.dispose);
  await module.refresh();
  final key = GlobalKey<RoomHarnessState>();
  final harness = RoomHarness(module, suite, key: key);
  await t.pumpWidget(
    frame == null ? harness : RepaintBoundary(key: frame, child: harness),
  );
  await t.pumpAndSettle();
  return key.currentState!;
}

Finder action(String label) =>
    find.widgetWithText(StarBridgeActionButton, label);
Finder dialogAction(String label) =>
    find.descendant(of: find.byType(AlertDialog).last, matching: action(label));
StarBridgeDialogRoute<Object?> route(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(AlertDialog).last))!
        as StarBridgeDialogRoute<Object?>;

Future<void> keyPress(WidgetTester t, Finder target) async {
  final content = find
      .descendant(of: target, matching: find.byType(Text))
      .first;
  Focus.of(t.element(content)).requestFocus();
  await t.pumpAndSettle();
  await t.sendKeyEvent(LogicalKeyboardKey.enter);
  await t.pump();
  await t.pump();
}

Future<void> capture(WidgetTester t, GlobalKey frame, String name) async {
  if (Platform.environment['STARBRIDGE_CAPTURE_MOTION_3I'] != '1') return;
  await t.runAsync(() async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/reviews/interaction-batch3i');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite actual pointer leave entry and settled review frames', (
      t,
    ) async {
      final port = MotionRoomPort()
        ..result = ready(wire(current: 'a', rooms: [room('a')]));
      final module = PartyRoomsModule(port);
      final frame = GlobalKey();
      await mount(t, module, suite, frame: frame);
      await t.tap(find.byKey(const Key('room-leave-open')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 60));
      expect(route(t).animation!.value, greaterThan(0));
      if (suite != InteractionSuite.standard) {
        expect(route(t).animation!.value, lessThan(1));
      }
      await capture(t, frame, '${suite.name}-leave-enter');
      await t.pumpAndSettle();
      await capture(t, frame, '${suite.name}-leave-settled');
      await keyPress(t, dialogAction('取消'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(port.calls, 0);
      expect(module.directory!.currentRoomId, 'a');
      expect(t.takeException(), isNull);
      module.stopSession();
    });
    testWidgets(
      '$suite nested navigator selection, nondismissible barrier, typed result',
      (t) async {
        final local = GlobalKey<NavigatorState>();
        bool? result;
        for (final root in [false, true]) {
          await t.pumpWidget(
            scopedApp(
              SizedBox(
                width: 500,
                height: 600,
                child: Navigator(
                  key: local,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      body: Center(
                        child: StarBridgeActionButton(
                          controlKey: const Key('open'),
                          onActivate: (source) async {
                            result = await showStarBridgeDialog<bool>(
                              context,
                              useRootNavigator: root,
                              barrierDismissible: false,
                              source: source,
                              builder: (context) => AlertDialog(
                                title: const Text('Dialog'),
                                actions: [
                                  StarBridgeActionButton(
                                    kind: StarBridgeActionKind.quiet,
                                    onActivate: (source) =>
                                        dismissStarBridgeDialog(
                                          context,
                                          source: source,
                                          result: true,
                                        ),
                                    child: const Text('Confirm'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: const Text('Open'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await keyPress(t, find.byKey(const Key('open')));
          final opened = route(t);
          expect(opened.navigator == local.currentState, !root);
          expect(opened.barrierDismissible, false);
          expect(opened.animation!.value, 1);
          await t.tapAt(const Offset(1, 1));
          await t.sendKeyEvent(LogicalKeyboardKey.escape);
          await t.pump();
          await t.pump();
          expect(find.byType(AlertDialog), findsOneWidget);
          await keyPress(t, dialogAction('Confirm'));
          expect(find.byType(AlertDialog), findsNothing);
          expect(result, true);
          result = null;
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
        }
      },
    );

    testWidgets(
      '$suite dismissible Esc closes instantly; local PopScope still guards',
      (t) async {
        var blocked = true;
        late StateSetter update;
        await t.pumpWidget(
          scopedApp(
            Builder(
              builder: (context) => StarBridgeActionButton(
                controlKey: const Key('open'),
                onActivate: (source) => showStarBridgeDialog<void>(
                  context,
                  source: source,
                  builder: (context) => StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return PopScope(
                        canPop: !blocked,
                        child: const AlertDialog(title: Text('Guarded')),
                      );
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('open')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 60));
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        update(() => blocked = false);
        await t.pump();
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        await t.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite semantic action colors preserved for each emphasis and disabled',
      (t) async {
        for (final tone in ActionTone.values) {
          for (final kind in [
            StarBridgeActionKind.primary,
            StarBridgeActionKind.secondary,
            StarBridgeActionKind.quiet,
          ]) {
            for (final enabled in [true, false]) {
              await t.pumpWidget(
                scopedApp(
                  StarBridgeActionButton(
                    controlKey: const Key('tone'),
                    tone: tone,
                    kind: kind,
                    onActivate: enabled ? (_) {} : null,
                    child: const Text('Tone'),
                  ),
                  suite,
                ),
              );
              await t.pumpAndSettle();
              final context = t.element(find.byKey(const Key('tone')));
              final colors = context.tokens.colors;
              final expected = switch (tone) {
                ActionTone.danger => colors.danger,
                ActionTone.warning => colors.warning,
                ActionTone.success => colors.success,
                ActionTone.info => colors.info,
              };
              if (suite == InteractionSuite.standard) {
                final style = t
                    .widget<ButtonStyleButton>(find.byKey(const Key('tone')))
                    .style!;
                expect(
                  style.foregroundColor!.resolve(
                    enabled ? {} : {WidgetState.disabled},
                  ),
                  !enabled
                      ? colors.textDisabled
                      : kind == StarBridgeActionKind.primary
                      ? colors.onAccent
                      : expected,
                );
              } else {
                final data = InteractionScope.of(context);
                expect(data.palette.accent, expected);
                expect(data.palette.focusRing, expected);
                expect(data.palette.textDisabled, colors.textDisabled);
                expect(
                  data.palette.border,
                  enabled ? expected : context.tokens.surfaces.panel.border,
                );
              }
            }
          }
        }
      },
    );

    testWidgets(
      '$suite actual create validates, retains tags, keyboard enters and succeeds',
      (t) async {
        final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
        await mount(t, module, suite);
        await keyPress(t, find.byKey(const Key('room-create-open')));
        expect(route(t).animation!.value, 1);
        expect(route(t).barrierDismissible, false);
        await t.tap(dialogAction('创建房间'));
        await t.pumpAndSettle();
        expect(module.directory!.currentRoomId, isNull);
        expect(find.text('名称需要 2–32 个字符。'), findsOneWidget);
        await t.enterText(find.byKey(const Key('room-create-title')), '动效回归房间');
        final tags = find.byKey(const Key('room-choose-tags'));
        await t.ensureVisible(tags);
        await t.tap(tags);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('tag-catalog-search')), '不知道玩啥');
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('search-tag-undecided')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('room-tags-confirm')));
        await t.pumpAndSettle();
        await keyPress(t, dialogAction('创建房间'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(module.directory!.currentRoomId, 'example-created');
        expect(module.selectedRoom!.tags.single.id, 'undecided');
        expect(module.selectedRoom!.title, '动效回归房间');
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );

    testWidgets(
      '$suite actual join keeps rejected code, blocks busy exit, resolves before join',
      (t) async {
        final r = room('a')..['admissionMode'] = 'direct';
        final port = MotionRoomPort()..result = ready(wire(rooms: [r]));
        final module = PartyRoomsModule(port);
        final h = await mount(t, module, suite);
        await keyPress(t, find.byKey(const Key('room-code-join-open')));
        final code = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        );
        await t.enterText(code, 'ABC123');
        await keyPress(t, dialogAction('查找房间'));
        expect(port.commands.single.operation, RoomOperation.resolve);
        expect(
          t.widget<StarBridgeActionButton>(dialogAction('取消')).onActivate,
          isNull,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.tapAt(const Offset(1, 1));
        await t.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        h.change(() {
          h.reduce = true;
          h.light = true;
        });
        await t.pump();
        await t.pump();
        expect(route(t).animation!.value, 1);
        port.next.complete(
          const RoomCommandResult('rejected', error: 'unavailable'),
        );
        await t.pumpAndSettle();
        expect(t.widget<TextField>(code).controller!.text, 'ABC123');
        expect(module.directory!.currentRoomId, isNull);
        port.next = Completer();
        await keyPress(t, dialogAction('查找房间'));
        final preview = module.directory!.rooms.single;
        port.next.complete(RoomCommandResult('resolved', preview: preview));
        await t.pumpAndSettle();
        expect(module.directory!.currentRoomId, isNull);
        expect(dialogAction('加入房间'), findsOneWidget);
        port.next = Completer();
        await keyPress(t, dialogAction('加入房间'));
        final joined = ready(wire(current: 'a', rooms: [r]));
        port.result = joined;
        port.next.complete(
          RoomCommandResult('joined', directory: joined.directory),
        );
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(module.directory!.currentRoomId, 'a');
        expect(port.calls, 3);
        expect(port.commands.last.data['roomId'], 'a');
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );

    testWidgets(
      '$suite actual disband cancel, lost ownership and explicit success',
      (t) async {
        final r = room('a')..['viewerIsHost'] = true;
        final port = MotionRoomPort()
          ..result = ready(wire(current: 'a', rooms: [r]));
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await t.tap(find.byKey(const Key('room-close-open')));
        await t.pumpAndSettle();
        await keyPress(t, dialogAction('取消'));
        expect(port.calls, 0);
        await keyPress(t, find.byKey(const Key('room-close-open')));
        port.result = ready(wire(current: 'a', rooms: [room('a')]));
        await module.refresh();
        await t.pumpAndSettle();
        await keyPress(t, dialogAction('解散房间'));
        await t.pumpAndSettle();
        expect(port.calls, 0);
        expect(module.directory!.currentRoomId, 'a');
        port.result = ready(wire(current: 'a', rooms: [r]));
        await module.refresh();
        await t.pumpAndSettle();
        await keyPress(t, find.byKey(const Key('room-close-open')));
        await keyPress(t, dialogAction('解散房间'));
        expect(port.calls, 1);
        final closed = ready(wire());
        port.result = closed;
        port.next.complete(
          RoomCommandResult('closed', directory: closed.directory),
        );
        await t.pumpAndSettle();
        expect(module.directory!.currentRoomId, isNull);
        expect(port.commands.single.operation, RoomOperation.close);
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );

    testWidgets(
      '$suite applications reject, retry and ignore earlier session reply',
      (t) async {
        final r = room('a')
          ..['viewerIsHost'] = true
          ..['pendingApplications'] = [
            {
              'applicationId': 'request-1',
              'callsign': '申请者',
              'gameId': 'Fixture',
              'createdAt': '2026-09-05T12:00:00Z',
            },
          ];
        final port = MotionRoomPort()
          ..result = ready(wire(current: 'a', rooms: [r]));
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await keyPress(t, find.byKey(const Key('room-applications-open')));
        expect(route(t).animation!.value, 1);
        expect(route(t).barrierDismissible, false);
        final approve = find.byKey(const ValueKey('approve-request-1'));
        await keyPress(t, approve);
        expect(port.calls, 1);
        expect(
          t.widget<StarBridgeActionButton>(dialogAction('完成')).onActivate,
          isNull,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        port.next.complete(
          const RoomCommandResult('rejected', error: 'unavailable'),
        );
        await t.pumpAndSettle();
        expect(module.selectedRoom!.pendingApplications, hasLength(1));
        port.next = Completer();
        await keyPress(t, approve);
        final old = port.result.directory;
        module.stopSession();
        final nextRoom = room('b')..['viewerIsHost'] = true;
        port.result = ready(wire(current: 'b', rooms: [nextRoom]));
        await module.refresh();
        await t.pumpAndSettle();
        port.next.complete(RoomCommandResult('approved', directory: old));
        await t.pumpAndSettle();
        expect(module.directory!.currentRoomId, 'b');
        expect(port.calls, 2);
        expect(port.commands.every((c) => c.data['roomId'] == 'a'), true);
        await keyPress(t, dialogAction('完成'));
        expect(find.byType(AlertDialog), findsNothing);
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );

    testWidgets(
      '$suite actual leave cancellation then confirmation dispatches once',
      (t) async {
        final port = MotionRoomPort()
          ..result = ready(wire(current: 'a', rooms: [room('a')]));
        final module = PartyRoomsModule(port);
        await mount(t, module, suite);
        await keyPress(t, find.byKey(const Key('room-leave-open')));
        expect(route(t).animation!.value, 1);
        await keyPress(t, dialogAction('取消'));
        expect(port.calls, 0);
        await t.tap(find.byKey(const Key('room-leave-open')));
        await t.pumpAndSettle();
        await keyPress(t, dialogAction('退出房间'));
        expect(port.calls, 1);
        final left = ready(wire());
        port.result = left;
        port.next.complete(
          RoomCommandResult('left', directory: left.directory),
        );
        await t.pumpAndSettle();
        expect(module.directory!.currentRoomId, isNull);
        expect(port.commands.single.operation, RoomOperation.leave);
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );
  }
}
