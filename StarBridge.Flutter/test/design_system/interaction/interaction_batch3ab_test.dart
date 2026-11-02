import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_select_form_field.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_compact_select.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/features/party_rooms/example_party_rooms_adapter.dart';
import 'package:starbridge_flutter/features/party_rooms/party_rooms_module.dart';
import 'package:starbridge_flutter/features/communities/community_creation_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_editor.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_schedule_editor.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3i_test.dart'
    as rooms
    show mount, keyPress, dialogAction;
import 'interaction_batch3aa_test.dart' show open, select;
import 'interaction_batch3b_test.dart' show exposedNodes;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/communities/community_creation_controller_test.dart'
    show CreationPort;
import '../../features/personal_profile/personal_profile_collaboration_test.dart'
    show schedule;
import '../../features/party_rooms/room_commands_test.dart' show CommandPort;

import 'package:starbridge_flutter/features/party_rooms/room_commands.dart';

const trigger = Key('form-trigger');
const items = [
  DropdownMenuItem(value: 'a', child: Text('Alpha')),
  DropdownMenuItem(value: 'blocked', enabled: false, child: Text('Disabled')),
  DropdownMenuItem(value: 'b', child: Text('Bravo')),
];

class Harness extends StatefulWidget {
  const Harness(this.suite, {super.key});
  final InteractionSuite suite;
  @override
  State<Harness> createState() => HarnessState();
}

class HarnessState extends State<Harness> {
  final field = GlobalKey<FormFieldState<String>>();
  final form = GlobalKey<FormState>();
  late var suite = widget.suite;
  bool enabled = true, reduce = false, light = false;
  String? initial = 'a', forceError;
  var auto = AutovalidateMode.disabled;
  final calls = <String>[];
  final sources = <InteractionSource>[];
  void change(VoidCallback action) => setState(action);
  @override
  Widget build(BuildContext context) => scopedApp(
    Center(
      child: SizedBox(
        width: 350,
        child: Form(
          key: form,
          onChanged: () => calls.add('form:${field.currentState!.value}'),
          child: StarBridgeSelectFormField<String>(
            key: field,
            identity: 'field',
            controlKey: trigger,
            initialValue: initial,
            items: items,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '字段',
              helperText: '原说明',
            ),
            forceErrorText: forceError,
            autovalidateMode: auto,
            validator: (value) => value == 'b' ? '不允许此选择' : null,
            onChanged: enabled
                ? (value) {
                    calls.add('change:$value');
                    sources.add(currentStarBridgeActivationSource);
                  }
                : null,
            onSaved: (value) => calls.add('save:$value'),
          ),
        ),
      ),
    ),
    suite,
    reduce: reduce,
    light: light,
  );
}

Future<HarnessState> harness(WidgetTester t, InteractionSuite suite) async {
  final key = GlobalKey<HarnessState>();
  await t.pumpWidget(Harness(suite, key: key));
  await t.pumpAndSettle();
  return key.currentState!;
}

void main() {
  setUpAll(loadFonts);
  testWidgets('minimal menu return under reduce has no lingering feedback', (
    t,
  ) async {
    await t.pumpWidget(
      scopedApp(
        Center(
          child: StarBridgeCompactSelect<String>(
            identity: 'field',
            controlKey: trigger,
            semanticLabel: '字段',
            value: 'a',
            options: const [
              StarBridgeSelectOption(value: 'a', label: 'Alpha'),
              StarBridgeSelectOption(value: 'b', label: 'Bravo'),
            ],
            onSelected: (_, _) {},
          ),
        ),
        InteractionSuite.standard,
        reduce: true,
      ),
    );
    await t.pumpAndSettle();
    await open(t, trigger, 'keyboard');
    await select(t, 'field', 'b', 'keyboard');
    await t.pump();
    await t.pump();
    expect(find.byType(SuiteSurfaceTransition), findsNothing);
    expect(t.hasRunningAnimations, isFalse);
  });
  testWidgets(
    'native builder seam retains SDK state and Form callback ordering',
    (t) async {
      final form = GlobalKey<FormState>();
      final field = GlobalKey<FormFieldState<String>>();
      final calls = <String>[];
      final original = DropdownButtonFormField<String>(
        items: const [DropdownMenuItem(value: 'a', child: Text('Alpha'))],
        initialValue: 'a',
        onChanged: (_) {},
      ).createState();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              onChanged: () => calls.add('form:${field.currentState!.value}'),
              child: StarBridgeSelectFormField<String>(
                key: field,
                identity: 'probe',
                initialValue: 'a',
                items: items,
                onChanged: (value) => calls.add('change:$value'),
                onSaved: (value) => calls.add('save:$value'),
                validator: (value) => value == 'a' ? 'invalid' : null,
              ),
            ),
          ),
        ),
      );
      expect(field.currentState.runtimeType, original.runtimeType);
      expect(field.currentState!.value, 'a');
      expect(form.currentState!.validate(), isFalse);
      field.currentState!.didChange('b');
      await t.pump();
      expect(calls.takeLast(2).toList(), ['form:b', 'change:b']);
      expect(form.currentState!.validate(), isTrue);
      form.currentState!.save();
      expect(calls.last, 'save:b');
      form.currentState!.reset();
      await t.pump();
      expect(field.currentState!.value, 'a');
      expect(calls.where((c) => c == 'change:a'), hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source actual FormField change/validation/save/reset',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final state = await harness(t, suite);
            final original = state.field.currentState!;
            await open(t, trigger, source);
            await t.pumpAndSettle();
            await select(t, 'field', 'b', source);
            await t.pumpAndSettle();
            expect(state.field.currentState, same(original));
            expect(original.hasInteractedByUser, isTrue);
            expect(state.calls.takeLast(2).toList(), ['form:b', 'change:b']);
            expect(state.sources, [
              source == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            ]);
            expect(state.form.currentState!.validate(), isFalse);
            await t.pumpAndSettle();
            expect(find.text('不允许此选择'), findsOneWidget);
            final node = exposedNodes(t)
                .singleWhere((n) => n.getSemanticsData().label == '字段 · Bravo');
            expect(node.getSemanticsData().hint, contains('不允许此选择'));
            state.form.currentState!.save();
            expect(state.calls.last, 'save:b');
            state.form.currentState!.reset();
            await t.pumpAndSettle();
            expect(state.field.currentState!.value, 'a');
            expect(original.hasInteractedByUser, isFalse);
            expect(find.text('不允许此选择'), findsNothing);
            expect(state.calls.where((c) => c == 'change:a'), hasLength(1));
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
    testWidgets(
      '$suite external initialValue updates native State without callback',
      (t) async {
        final state = await harness(t, suite),
            original = state.field.currentState!;
        state.change(() => state.initial = 'b');
        await t.pumpAndSettle();
        expect(state.field.currentState, same(original));
        expect(original.value, 'b');
        expect(state.calls, isEmpty);
        expect(original.hasInteractedByUser, isFalse);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite nullable value and keyboard focus keep native Form identity',
      (t) async {
        final state = await harness(t, suite),
            original = state.field.currentState!;
        state.change(() => state.initial = null);
        await t.pumpAndSettle();
        expect(original.value, isNull);
        await open(t, trigger, 'keyboard');
        await select(t, 'field', 'a', 'keyboard');
        await t.pumpAndSettle();
        expect(state.field.currentState, same(original));
        expect(original.value, 'a');
        expect(state.calls.takeLast(2).toList(), ['form:a', 'change:a']);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite autovalidation and server errors retain original draft',
      (t) async {
        final state = await harness(t, suite);
        state.change(() => state.auto = AutovalidateMode.onUserInteraction);
        await t.pumpAndSettle();
        expect(find.text('不允许此选择'), findsNothing);
        await open(t, trigger, 'keyboard');
        await select(t, 'field', 'b', 'keyboard');
        await t.pumpAndSettle();
        expect(state.field.currentState!.errorText, '不允许此选择');
        state.change(() {
          state.forceError = '服务器拒绝';
          state.enabled = false;
        });
        await t.pumpAndSettle();
        expect(state.field.currentState!.value, 'b');
        expect(find.text('服务器拒绝'), findsOneWidget);
        await t.tap(find.byKey(trigger), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(find.byType(SuiteSurfaceTransition), findsNothing);
        expect(state.calls.where((c) => c.startsWith('change:')), hasLength(1));
        state.change(() {
          state.forceError = null;
          state.enabled = true;
        });
        await t.pumpAndSettle();
        expect(state.field.currentState!.value, 'b');
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite live style/theme/reduce preserve native Form state', (
      t,
    ) async {
      final state = await harness(t, suite),
          original = state.field.currentState!;
      original.didChange('b');
      await t.pumpAndSettle();
      final count = state.calls.length;
      for (final next in InteractionSuite.values) {
        state.change(() {
          state.suite = next;
          state.light = !state.light;
          state.reduce = !state.reduce;
        });
        await t.pumpAndSettle();
        expect(state.field.currentState, same(original));
        expect(original.value, 'b');
        expect(original.hasInteractedByUser, isTrue);
        expect(state.calls, hasLength(count));
        expect(t.takeException(), isNull);
      }
    });
    testWidgets(
      '$suite reduce during entrance and keyboard clear selection land',
      (t) async {
        final state = await harness(t, suite);
        await open(t, trigger, 'pointer');
        await t.pump(const Duration(milliseconds: 35));
        state.change(() => state.reduce = true);
        await t.pump();
        await t.pump();
        expect(
          t
              .widget<SuiteSurfaceTransition>(
                find.byType(SuiteSurfaceTransition),
              )
              .animation
              .value,
          1,
        );
        await select(t, 'field', 'b', 'keyboard');
        await t.pump();
        await t.pump();
        expect(state.field.currentState!.value, 'b');
        expect(t.hasRunningAnimations, isFalse);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite disabled while open retires stale options', (t) async {
      final state = await harness(t, suite);
      await open(t, trigger, 'pointer');
      state.change(() => state.enabled = false);
      await t.pump();
      await t.pump();
      await t.pumpAndSettle();
      expect(find.byType(SuiteSurfaceTransition), findsNothing);
      expect(state.calls, isEmpty);
      expect(state.field.currentState!.value, 'a');
      expect(t.takeException(), isNull);
    });
    testWidgets(
      '$suite actual room seven choices reach original create payload',
      (t) async {
        final module = PartyRoomsModule(ExamplePartyRoomsAdapter());
        await rooms.mount(t, module, suite);
        await rooms.keyPress(t, find.byKey(const Key('room-create-open')));
        for (final choice in <(String, Object)>[
          ('room-capacity', 8),
          ('room-admission', 'approval'),
          ('room-eligibility', 'friends'),
          ('room-voice', 'required'),
          ('room-language', 'en'),
          ('room-disband', 4),
          ('room-recruitment-duration', 60),
        ]) {
          await open(t, Key(choice.$1), 'keyboard');
          await select(t, choice.$1, choice.$2, 'keyboard');
          await t.pumpAndSettle();
        }
        expect(module.directory!.currentRoomId, isNull);
        await t.enterText(
          find.byKey(const Key('room-create-title')),
          '表单接入验证房间',
        );
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
        await rooms.keyPress(t, rooms.dialogAction('创建房间'));
        await t.pumpAndSettle();
        expect(module.selectedRoom!.capacity, 8);
        expect(module.selectedRoom!.admissionMode, 'approval');
        expect(module.selectedRoom!.eligibility, 'friends');
        expect(module.selectedRoom!.voice, 'required');
        expect(module.selectedRoom!.language, 'en');
        expect(module.selectedRoom!.tags.single.id, 'undecided');
        expect(t.takeException(), isNull);
        module.stopSession();
      },
    );
    testWidgets(
      '$suite room submit freezes every choice and rejection retains it',
      (t) async {
        final port = CommandPort();
        final example = ExamplePartyRoomsAdapter();
        port.result = await example.read();
        await example.close();
        final owner = PartyRoomsModule(port);
        await rooms.mount(t, owner, suite);
        await rooms.keyPress(t, find.byKey(const Key('room-create-open')));
        await open(t, const Key('room-capacity'), 'keyboard');
        await select(t, 'room-capacity', 8, 'keyboard');
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('room-create-title')), '保留创建草稿');
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
        await rooms.keyPress(t, rooms.dialogAction('创建房间'));
        await t.pump();
        await t.pump();
        expect(port.calls, 1);
        final fields = t.widgetList(
          find.byWidgetPredicate((w) => w is StarBridgeSelectFormField),
        );
        expect(fields, hasLength(7));
        for (final field in fields) {
          expect((field as StarBridgeSelectFormField).onChanged, isNull);
        }
        port.pendingCommand.complete(
          const RoomCommandResult('rejected', error: 'rejected'),
        );
        await t.pumpAndSettle();
        expect(
          t
              .widget<StarBridgeSelectFormField<int>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is StarBridgeSelectFormField<int> &&
                      w.identity == 'room-capacity',
                ),
              )
              .initialValue,
          8,
        );
        expect(find.text('保留创建草稿'), findsWidgets);
        expect(owner.directory!.currentRoomId, isNull);
        expect(t.takeException(), isNull);
        owner.stopSession();
      },
    );
    testWidgets(
      '$suite actual community choices retain rejected draft and busy guard',
      (t) async {
        size(t, const Size(1280, 1100));
        final port = CreationPort();
        addTearDown(port.changes.close);
        await t.pumpWidget(
          scopedApp(
            CommunityCreationDialog(
              port: port,
              invalidations: port.changes.stream,
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await open(t, const Key('community-create-join-policy'), 'keyboard');
        await select(t, 'community-create-join-policy', 'Approval', 'keyboard');
        await t.pumpAndSettle();
        final zoneWidget = t.widget<StarBridgeSelectFormField<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is StarBridgeSelectFormField<String> &&
                w.identity == 'community-create-zone',
          ),
        );
        final zone = zoneWidget.items!.last.value!;
        await open(t, const Key('community-create-zone'), 'keyboard');
        await select(t, 'community-create-zone', zone, 'keyboard');
        await t.pumpAndSettle();
        expect(port.writes, isEmpty);
        await t.enterText(
          find.byKey(const ValueKey('create-name')),
          'Test Organization',
        );
        await t.enterText(find.byKey(const ValueKey('create-code')), 'TEST');
        port.pending = Completer<CommunityCreationOutcome>();
        final submit = find.byKey(const Key('community-create-submit'));
        await t.ensureVisible(submit);
        await t.tap(submit);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('community-create-confirm-save')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(port.writes, hasLength(1));
        expect(port.writes.single.$2['joinPolicy'], 'Approval');
        expect(port.writes.single.$2['timeZoneId'], zone);
        final blocked = t.widget<StarBridgeSelectFormField<String>>(
          find.byWidgetPredicate(
            (w) =>
                w is StarBridgeSelectFormField<String> &&
                w.identity == 'community-create-join-policy',
          ),
        );
        expect(blocked.onChanged, isNull);
        await t.tap(
          find.byKey(const Key('community-create-join-policy')),
          warnIfMissed: false,
        );
        await t.pump();
        await t.pump();
        // A pointer-confirmed dialog may still be exiting. Assert the guarded
        // join-policy menu stays closed, not that every UI surface is absent.
        for (final value in ['Open', 'Approval', 'Invite']) {
          expect(
            find.byKey(
              ValueKey<Object>(('community-create-join-policy', value)),
            ),
            findsNothing,
          );
        }
        port.pending!.complete(port.result);
        await t.pumpAndSettle();
        expect(
          t
              .widget<StarBridgeSelectFormField<String>>(
                find.byWidgetPredicate(
                  (w) =>
                      w is StarBridgeSelectFormField<String> &&
                      w.identity == 'community-create-join-policy',
                ),
              )
              .initialValue,
          'Approval',
        );
        expect(find.text('Test Organization'), findsWidgets);
        expect(port.writes, hasLength(1));
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      '$suite actual profile visibility remains private after rejected save',
      (t) async {
        size(t, const Size(1200, 1100));
        final adapter = InMemoryPersonalProfileAdapter.forReview(
          signedIn: true,
        );
        final projection = PersonalProfileProjection.fromSnapshot(
          await adapter.read(),
        );
        final edits = <PersonalProfileEdit>[];
        final reply = Completer<PersonalProfileActionResult>();
        var saved = 0;
        await t.pumpWidget(
          scopedApp(
            SingleChildScrollView(
              child: PersonalProfileEditorPanel(
                projection: projection,
                moduleLayout: const [],
                onCancel: () {},
                onSaved: () => saved++,
                onWallpaperChanged: (_) {},
                onSave: (edit) {
                  edits.add(edit);
                  return reply.future;
                },
              ),
            ),
            suite,
          ),
        );
        await t.pumpAndSettle();
        await open(t, const Key('profile-visibility-trigger'), 'keyboard');
        await select(
          t,
          'profile-visibility',
          PersonalProfileVisibility.onlyMe,
          'keyboard',
        );
        await t.pumpAndSettle();
        final save = find.byKey(const Key('profile-save'));
        await t.ensureVisible(save);
        await t.tap(save);
        await t.pump();
        await t.pump();
        expect(edits, hasLength(1));
        expect(edits.single.visibility, PersonalProfileVisibility.onlyMe);
        expect(
          t
              .widget<StarBridgeSelectFormField<PersonalProfileVisibility>>(
                find.byKey(const Key('profile-visibility-selector')),
              )
              .onChanged,
          isNull,
        );
        reply.complete(
          const PersonalProfileActionResult(
            PersonalProfileActionOutcome.rejected,
          ),
        );
        await t.pumpAndSettle();
        expect(saved, 0);
        expect(
          t
              .widget<StarBridgeSelectFormField<PersonalProfileVisibility>>(
                find.byKey(const Key('profile-visibility-selector')),
              )
              .initialValue,
          PersonalProfileVisibility.onlyMe,
        );
        await t.pumpWidget(const SizedBox());
        expect(t.takeException(), isNull);
      },
    );
    testWidgets('$suite actual schedule choices preserve overnight windows', (
      t,
    ) async {
      size(t, const Size(1200, 1100));
      final values = <PersonalProfileSchedule>[];
      await t.pumpWidget(
        scopedApp(
          SingleChildScrollView(
            child: PersonalProfileScheduleEditor(
              initial: schedule,
              timeZones: const {'America/Regina': 'Regina', 'UTC': 'UTC'},
              enabled: true,
              onChanged: values.add,
            ),
          ),
          suite,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profile-schedule-editor')));
      await t.pumpAndSettle();
      await open(t, const Key('profile-schedule-zone-trigger'), 'keyboard');
      await select(t, 'profile-schedule-zone', 'UTC', 'keyboard');
      await t.pumpAndSettle();
      await open(t, const Key('profile-schedule-rhythm-trigger'), 'keyboard');
      await select(
        t,
        'profile-schedule-rhythm',
        PersonalProfileActivityRhythm.regular,
        'keyboard',
      );
      await t.pumpAndSettle();
      expect(values, hasLength(2));
      expect(values.last.timeZoneId, 'UTC');
      expect(values.last.rhythm, PersonalProfileActivityRhythm.regular);
      expect(values.last.windows.first.startTime, '23:30');
      expect(values.last.windows.first.endTime, '02:15');
      expect(values.last.windows.first.days, [1, 3]);
      await t.pumpWidget(const SizedBox());
      expect(t.takeException(), isNull);
    });
    for (final scale in [1.0, 2.0]) {
      for (final dense in [false, true]) {
        testWidgets(
          '$suite native decorated dimensions text=$scale dense=$dense',
          (t) async {
            size(t, const Size(900, 700));
            await t.pumpWidget(
              scopedApp(
                MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 350,
                        child: StarBridgeSelectFormField<String>(
                          key: const Key('adapted'),
                          identity: 'dimensions',
                          items: items,
                          initialValue: 'a',
                          isDense: dense,
                          isExpanded: true,
                          onChanged: (_) {},
                          decoration: const InputDecoration(
                            labelText: '原标签',
                            helperText: '说明',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 350,
                        child: DropdownButtonFormField<String>(
                          key: const Key('native'),
                          items: items,
                          initialValue: 'a',
                          isDense: dense,
                          isExpanded: true,
                          onChanged: (_) {},
                          decoration: const InputDecoration(
                            labelText: '原标签',
                            helperText: '说明',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                suite,
              ),
            );
            await t.pumpAndSettle();
            expect(
              t.getSize(find.byKey(const Key('adapted'))),
              t.getSize(find.byKey(const Key('native'))),
            );
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
  for (final suite in [InteractionSuite.scan, InteractionSuite.glow]) {
    testWidgets('$suite 200 percent form error and menu visual review', (
      t,
    ) async {
      size(t, const Size(400, 700));
      final boundary = GlobalKey();
      await t.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: scopedApp(
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: Center(
                child: SizedBox(
                  width: 350,
                  child: StarBridgeSelectFormField<String>(
                    identity: 'review',
                    controlKey: trigger,
                    initialValue: 'b',
                    items: items,
                    onChanged: (_) {},
                    isExpanded: true,
                    forceErrorText: '服务器拒绝此选择',
                    decoration: const InputDecoration(
                      labelText: '原表单标签',
                      helperText: '原字段说明',
                      errorMaxLines: 3,
                    ),
                  ),
                ),
              ),
            ),
            suite,
          ),
        ),
      );
      await t.pumpAndSettle();
      await open(t, trigger, 'pointer');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        try {
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('build/reviews/interaction-batch3ab');
          await dir.create(recursive: true);
          await File('${dir.path}/${suite.name}-form-error-200.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}

extension LastItems<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
