import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_draft.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_visibility_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/personal_profile/profile_refresh_retention_test.dart'
    show HeldRefreshProfile;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder visibilityKey(String suffix) =>
    find.byKey(Key('profile-visibility-$suffix'));

class VisibilityAccess implements ProfileVisibilityAccess {
  ProfileVisibilityState state = const ProfileVisibilityState(
    7,
    PersonalProfileVisibility.onlyMe,
    availableVisibilities: [
      PersonalProfileVisibility.everyone,
      PersonalProfileVisibility.friendsAndMainFleet,
      PersonalProfileVisibility.friendsOnly,
      PersonalProfileVisibility.onlyMe,
    ],
  );
  int reads = 0;
  bool readFailure = false;
  Completer<ProfileVisibilityState>? readGate, saveGate;
  final writes =
      <
        (ProfileVisibilityState, PersonalProfileVisibility, InteractionSource)
      >[];
  @override
  Future<ProfileVisibilityState> readVisibility() {
    reads++;
    if (readFailure) return Future.error(StateError('test read refusal'));
    return readGate?.future ?? Future.value(state);
  }

  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility selection,
  ) {
    writes.add((expected, selection, currentStarBridgeActivationSource));
    return saveGate?.future ?? Future.value(state);
  }
}

class VisibilityPort extends HeldRefreshProfile
    implements ProfileVisibilityAccess {
  final visibility = VisibilityAccess();
  @override
  Future<ProfileVisibilityState> readVisibility() =>
      visibility.readVisibility();
  @override
  Future<ProfileVisibilityState> saveVisibility(
    ProfileVisibilityState expected,
    PersonalProfileVisibility selection,
  ) => visibility.saveVisibility(expected, selection);
}

class VisibilityProbe {
  VisibilityProbe(this.suite);
  InteractionSuite suite;
  bool reduce = false, light = false;
  final access = VisibilityAccess();
  late StateSetter update;
  final frame = GlobalKey();
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return RepaintBoundary(
        key: frame,
        child: scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('visibility-open'),
              onActivate: (source) => unawaited(
                showStarBridgeDialog<void>(
                  context,
                  source: source,
                  barrierDismissible: false,
                  traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
                  builder: (_) => Semantics(
                    scopesRoute: true,
                    explicitChildNodes: true,
                    child: SafeArea(
                      child: ProfileVisibilityDialog(access: access),
                    ),
                  ),
                ),
              ),
              child: const Text('Open visibility'),
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        ),
      );
    },
  );
}

Future<void> visibilityFrames(WidgetTester t) async {
  await t.pump();
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> activateVisibility(
  WidgetTester t,
  Finder target,
  String input,
) async {
  await t.ensureVisible(target);
  await visibilityFrames(t);
  if (input == 'keyboard') {
    final w = t.widget(target);
    final node = switch (w) {
      ButtonStyleButton b => b.focusNode!,
      Checkbox c => c.focusNode!,
      SuiteCheckbox c => c.focusNode!,
      SuitePressable p =>
        p.focusNode ??
            t
                .widget<FocusableActionDetector>(
                  find
                      .descendant(
                        of: target,
                        matching: find.byType(FocusableActionDetector),
                      )
                      .first,
                )
                .focusNode!,
      _ => throw StateError('Unsupported focus target $w'),
    };
    for (var i = 0; !node.hasPrimaryFocus && i < 64; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(node.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (input == 'reader') {
    final node = t.getSemantics(target);
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      isTrue,
      reason: '$target ${node.getSemanticsData()}',
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else {
    // Checkbox keys identify the decorative control. Its enclosing row owns
    // pointer activation; hit that actual target rather than IgnorePointer.
    final row =
        (t.widget(target) is Checkbox || t.widget(target) is SuiteCheckbox)
        ? find
              .ancestor(of: target, matching: find.byType(GestureDetector))
              .first
        : target;
    await t.tap(row);
  }
  await visibilityFrames(t);
}

bool visibilityEnabled(WidgetTester t, String action) =>
    t
        .widget<StarBridgeActionButton>(
          find
              .ancestor(
                of: visibilityKey(action),
                matching: find.byType(StarBridgeActionButton),
              )
              .first,
        )
        .onActivate !=
    null;

Future<VisibilityProbe> openVisibility(
  WidgetTester t,
  InteractionSuite suite, {
  String input = 'pointer',
  bool holdRead = false,
}) async {
  size(t, const Size(900, 1000));
  final p = VisibilityProbe(suite);
  if (holdRead) p.access.readGate = Completer();
  await t.pumpWidget(p.app());
  await visibilityFrames(t);
  await activateVisibility(t, find.byKey(const Key('visibility-open')), input);
  return p;
}

Future<
  ({VisibilityPort port, PersonalProfileModule module, StateSetter update})
>
openVisibilityPage(
  WidgetTester t,
  InteractionSuite suite, {
  required ValueNotifier<PersonalProfileModule?> current,
  String input = 'pointer',
}) async {
  size(t, const Size(1100, 1100));
  final port = VisibilityPort();
  // Construct the real module over the observed port, never a fake Page owner.
  final actual = createPersonalProfileModule(port);
  await actual.initialize();
  current.value = actual;
  late StateSetter update;
  await t.pumpWidget(
    StatefulBuilder(
      builder: (_, setState) {
        update = setState;
        return scopedApp(
          current.value == null
              ? const Text('away')
              : PersonalProfilePage(module: current.value!),
          suite,
        );
      },
    ),
  );
  await t.pumpAndSettle();
  await activateVisibility(
    t,
    find.byKey(const Key('profile-visibility')),
    input,
  );
  expect((actual as PersonalProfileDraftSession).editingLeaseActive, isTrue);
  return (port: port, module: actual, update: update);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input choices remain controlled; cancel/read/failure/reload/save keep separate owner',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await openVisibility(
              t,
              suite,
              input: input,
              holdRead: true,
            );
            final route =
                ModalRoute.of(t.element(find.byType(ProfileVisibilityDialog)))!
                    as StarBridgeDialogRoute;
            expect(route.instant, input != 'pointer');
            expect(route.barrierDismissible, isFalse);
            expect(visibilityEnabled(t, 'cancel'), isFalse);
            expect(
              find.byType(SuiteProgressBar).evaluate().isNotEmpty,
              input == 'pointer',
            );
            p.access.readGate!.complete(p.access.state);
            await visibilityFrames(t);
            expect(find.byType(StarBridgeCheckboxTile), findsNWidgets(4));
            expect(visibilityKey('friendsFleetAndOrganizations'), findsNothing);
            await activateVisibility(
              t,
              visibilityKey('friendsAndMainFleet'),
              input,
            );
            expect(p.access.writes, isEmpty);
            await activateVisibility(t, visibilityKey('cancel'), input);
            expect(find.byType(ProfileVisibilityDialog), findsNothing);
            await activateVisibility(
              t,
              find.byKey(const Key('visibility-open')),
              input,
            );
            await activateVisibility(t, visibilityKey('friendsOnly'), input);
            p.access.saveGate = Completer();
            await activateVisibility(t, visibilityKey('save'), input);
            expect(p.access.writes.length, 1);
            expect(p.access.writes.single.$1, same(p.access.state));
            expect(
              p.access.writes.single.$2,
              PersonalProfileVisibility.friendsOnly,
            );
            expect(
              p.access.writes.single.$3,
              input == 'pointer'
                  ? InteractionSource.pointer
                  : InteractionSource.keyboard,
            );
            expect(visibilityEnabled(t, 'cancel'), isFalse);
            expect(visibilityEnabled(t, 'save'), isFalse);
            for (final row in t.widgetList<StarBridgeCheckboxTile>(
              find.byType(StarBridgeCheckboxTile),
            )) {
              expect(row.onChanged, isNull);
            }
            await t.sendKeyEvent(LogicalKeyboardKey.escape);
            await t.pump();
            expect(find.byType(ProfileVisibilityDialog), findsOneWidget);
            p.access.saveGate!.completeError(StateError('refused'));
            await visibilityFrames(t);
            expect(find.byType(StarBridgeCheckboxTile), findsNothing);
            expect(visibilityEnabled(t, 'save'), isFalse);
            expect(p.access.state.visibility, PersonalProfileVisibility.onlyMe);
            await activateVisibility(t, visibilityKey('reload'), input);
            expect(p.access.reads, 3);
            expect(
              t
                  .widget<StarBridgeCheckboxTile>(
                    find
                        .ancestor(
                          of: visibilityKey(
                            PersonalProfileVisibility.onlyMe.bridgeValue,
                          ),
                          matching: find.byType(StarBridgeCheckboxTile),
                        )
                        .first,
                  )
                  .value,
              isTrue,
            );
            await activateVisibility(
              t,
              visibilityKey(PersonalProfileVisibility.everyone.bridgeValue),
              input,
            );
            p.access.saveGate = Completer();
            await activateVisibility(t, visibilityKey('save'), input);
            p.access.saveGate!.complete(
              const ProfileVisibilityState(
                8,
                PersonalProfileVisibility.everyone,
              ),
            );
            await visibilityFrames(t);
            expect(find.byType(ProfileVisibilityDialog), findsNothing);
            expect(p.access.writes.length, 2);
            expect(t.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite read failure only retries explicit reload; live reduce stops pending decoration',
      (t) async {
        final p = await openVisibility(t, suite, holdRead: true);
        p.update(() {
          p.reduce = true;
          p.suite = InteractionSuite.glow;
        });
        await t.pump();
        await t.pump();
        expect(find.byType(SuiteProgressBar), findsNothing);
        p.access.readGate!.completeError(StateError('read refused'));
        await visibilityFrames(t);
        expect(visibilityEnabled(t, 'save'), isFalse);
        expect(visibilityEnabled(t, 'cancel'), isTrue);
        expect(p.access.reads, 1);
        p.access.readGate = null;
        await activateVisibility(t, visibilityKey('reload'), 'pointer');
        expect(p.access.reads, 2);
        expect(visibilityEnabled(t, 'save'), isTrue);
        await activateVisibility(t, visibilityKey('cancel'), 'pointer');
        expect(p.access.writes, isEmpty);
      },
    );

    for (final input in ['keyboard', 'reader']) {
      testWidgets(
        '$suite actual Page $input opens instantly and preserves closed loop',
        (t) async {
          final semantics = t.ensureSemantics();
          final current = ValueNotifier<PersonalProfileModule?>(null);
          try {
            final h = await openVisibilityPage(
              t,
              suite,
              current: current,
              input: input,
            );
            addTearDown(h.module.dispose);
            final route =
                ModalRoute.of(t.element(find.byType(ProfileVisibilityDialog)))!
                    as StarBridgeDialogRoute;
            expect(route.instant, isTrue);
            expect(route.animation!.value, 1);
            expect(
              route.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            expect(find.byType(SafeArea), findsWidgets);
            await activateVisibility(t, visibilityKey('cancel'), input);
            expect(find.byType(ProfileVisibilityDialog), findsNothing);
            expect(
              (h.module as PersonalProfileDraftSession).editingLeaseActive,
              isFalse,
            );
            expect(h.port.visibility.writes, isEmpty);
            await t.pumpWidget(const SizedBox());
          } finally {
            semantics.dispose();
            current.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite Page retirement also owns the already-reversing route',
      (t) async {
        final current = ValueNotifier<PersonalProfileModule?>(null);
        final h = await openVisibilityPage(t, suite, current: current);
        addTearDown(h.module.dispose);
        final route =
            ModalRoute.of(t.element(find.byType(ProfileVisibilityDialog)))!
                as StarBridgeDialogRoute;
        await t.tap(visibilityKey('cancel'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 20));
        expect(route.animation!.status, AnimationStatus.reverse);
        h.update(() => current.value = null);
        await t.pump();
        await t.pump();
        expect(route.animation!.value, 0);
        await visibilityFrames(t);
        expect(find.byType(ProfileVisibilityDialog), findsNothing);
        expect(h.port.visibility.writes, isEmpty);
        await t.pumpWidget(const SizedBox());
        current.dispose();
        expect(t.takeException(), isNull);
      },
    );

    for (final replace in [false, true]) {
      for (final lateFailure in [false, true]) {
        testWidgets(
          '$suite actual Page ${replace ? 'module replacement' : 'unmount'} retires own busy route, not unrelated top; ignores late ${lateFailure ? 'failure' : 'success'}',
          (t) async {
            final current = ValueNotifier<PersonalProfileModule?>(null);
            final h = await openVisibilityPage(t, suite, current: current);
            addTearDown(h.module.dispose);
            await activateVisibility(
              t,
              visibilityKey('friendsOnly'),
              'pointer',
            );
            h.port.visibility.saveGate = Completer();
            await activateVisibility(t, visibilityKey('save'), 'pointer');
            final ctx = t.element(find.byType(ProfileVisibilityDialog));
            unawaited(
              showDialog<void>(
                context: ctx,
                builder: (_) =>
                    const AlertDialog(content: Text('unrelated top')),
              ),
            );
            await visibilityFrames(t);
            PersonalProfileModule? replacement;
            if (replace) {
              replacement = createPersonalProfileModule(VisibilityPort());
              await replacement.initialize();
              addTearDown(replacement.dispose);
            }
            h.update(() => current.value = replacement);
            await visibilityFrames(t);
            expect(find.byType(ProfileVisibilityDialog), findsNothing);
            expect(find.text('unrelated top'), findsOneWidget);
            expect(
              (h.module as PersonalProfileDraftSession).editingLeaseActive,
              isFalse,
            );
            if (lateFailure) {
              h.port.visibility.saveGate!.completeError(
                StateError('late refusal'),
              );
            } else {
              h.port.visibility.saveGate!.complete(
                const ProfileVisibilityState(
                  8,
                  PersonalProfileVisibility.friendsOnly,
                ),
              );
            }
            await visibilityFrames(t);
            expect(find.text('unrelated top'), findsOneWidget);
            if (replacement != null) {
              expect(
                (replacement as PersonalProfileDraftSession).editingLeaseActive,
                isFalse,
              );
            }
            expect(h.port.saves, 0);
            expect(h.port.visibility.writes.length, 1);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            current.dispose();
          },
        );
      }
    }

    testWidgets(
      '$suite actual Page defers soft refresh until cancel and retires hard invalidation',
      (t) async {
        final current = ValueNotifier<PersonalProfileModule?>(null);
        final h = await openVisibilityPage(t, suite, current: current);
        addTearDown(h.module.dispose);
        h.port.soft.add(null);
        await h.module.refresh();
        expect(h.port.reads, 1);
        await activateVisibility(t, visibilityKey('cancel'), 'pointer');
        expect(
          (h.module as PersonalProfileDraftSession).editingLeaseActive,
          isFalse,
        );
        expect(h.port.reads, 2);
        await activateVisibility(
          t,
          find.byKey(const Key('profile-visibility')),
          'pointer',
        );
        h.port.readGate = Completer();
        h.port.hard.add(null);
        await visibilityFrames(t);
        expect(find.byType(ProfileVisibilityDialog), findsNothing);
        h.port.readGate!.complete(await h.port.delegate.read());
        await visibilityFrames(t);
        expect(h.port.visibility.writes, isEmpty);
        expect(h.port.saves, 0);
        await t.pumpWidget(const SizedBox());
        current.dispose();
        expect(t.takeException(), isNull);
      },
    );
  }
}
