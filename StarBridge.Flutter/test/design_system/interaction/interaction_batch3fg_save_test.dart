import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_waiting.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_reconciliation.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_removal_dialog.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_panel.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3fc_visibility_test.dart' show visibilityFrames;
import 'interaction_batch3i_test.dart' show scopedApp;

const saveOperation = 'verified-scan';
const saveBaseline = LocalHangarSnapshot(revision: 7, ships: []);
const saveShips = [
  LocalHangarShip(id: 'a', title: 'Carrack A'),
  LocalHangarShip(id: 'b', title: 'Carrack B', isFavorite: true),
  LocalHangarShip(id: 'c', title: 'Vulture C'),
  LocalHangarShip(id: 'd', title: 'Vulture D'),
  LocalHangarShip(id: 'e', title: 'Vulture E'),
];
const saveGroups = [
  LocalHangarRemovalGroup(id: 'a', requiredCount: 1, shipIds: ['a', 'b']),
  LocalHangarRemovalGroup(id: 'c', requiredCount: 2, shipIds: ['c', 'd', 'e']),
];

class SaveIntent {
  SaveIntent(
    this.operation,
    this.revision,
    this.empty,
    this.removed,
    this.resolved,
  ) : source = currentStarBridgeActivationSource;
  final String operation;
  final int revision;
  final bool empty, resolved;
  final List<String> removed;
  final InteractionSource source;
  final gate = Completer<LocalHangarSnapshot>();
}

/// Gates only real Port boundaries; LocalHangarSaveModule owns all admission,
/// selected IDs, revisions and uncertainty. No synthetic saved state is injected.
class SaveMotionPort implements LocalHangarPort, LocalHangarReconciliationPort {
  final reads = <Completer<LocalHangarSnapshot>>[];
  final readSources = <InteractionSource>[];
  final previews = <(String, int)>[];
  final writes = <SaveIntent>[];
  List<LocalHangarRemovalGroup> groups = const [];
  @override
  bool get reconciliationAvailable => true;
  @override
  Future<LocalHangarSnapshot> read() {
    final request = Completer<LocalHangarSnapshot>();
    reads.add(request);
    readSources.add(currentStarBridgeActivationSource);
    return request.future;
  }

  @override
  Future<List<LocalHangarRemovalGroup>> previewRemovals(
    String operationId,
    int expectedRevision,
  ) async {
    previews.add((operationId, expectedRevision));
    return groups;
  }

  @override
  Future<LocalHangarSnapshot> saveResolved(
    String operationId,
    int expectedRevision, {
    required List<String> removedShipIds,
    bool confirmEmpty = false,
  }) {
    final intent = SaveIntent(operationId, expectedRevision, confirmEmpty, [
      ...removedShipIds,
    ], true);
    writes.add(intent);
    return intent.gate.future;
  }

  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) => throw StateError('The real reconciliation capability must be used');
}

class SaveProbe {
  SaveProbe(this.suite);
  final InteractionSuite suite;
  final port = SaveMotionPort();
  bool shown = true, reduce = false, light = false;
  int saved = 0;
  final savedSources = <InteractionSource>[];
  int shipCount = 1;
  String scanPhase = 'complete';
  InteractionSource initialSource = InteractionSource.programmatic;
  late StateSetter update;
  late BuildContext pageContext;
  Map<String, Object?> get view => {
    'operationId': saveOperation,
    'shipCount': shipCount,
    'phase': scanPhase,
  };
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Builder(
          builder: (context) {
            pageContext = context;
            return Semantics(
              explicitChildNodes: true,
              child: SizedBox(
                width: 850,
                child: SingleChildScrollView(
                  child: shown
                      ? LocalHangarSavePanel(
                          port: port,
                          view: view,
                          initialSource: initialSource,
                          onSaved: () {
                            saved++;
                            savedSources.add(currentStarBridgeActivationSource);
                          },
                        )
                      : const Text('Reader left'),
                ),
              ),
            );
          },
        ),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Finder saveKey(String key) => find.byKey(Key(key));
Finder saveAction(String suffix) => saveKey('local-hangar-$suffix');
Finder removalAction(String suffix) => saveKey('hangar-removal-$suffix');

Finder saveTileFinder(WidgetTester t, Finder target) =>
    t.widget(target) is StarBridgeCheckboxTile
    ? target
    : find
          .ancestor(of: target, matching: find.byType(StarBridgeCheckboxTile))
          .first;

StarBridgeCheckboxTile saveTile(WidgetTester t, Finder target) =>
    t.widget<StarBridgeCheckboxTile>(saveTileFinder(t, target));

StarBridgeActionButton saveButton(WidgetTester t, Finder target) =>
    t.widget<StarBridgeActionButton>(
      t.widget(target) is StarBridgeActionButton
          ? target
          : find
                .ancestor(
                  of: target,
                  matching: find.byType(StarBridgeActionButton),
                )
                .first,
    );

/// Real pointer, Tab/Enter and SemanticsAction.tap. The semantic row owns the
/// decorative checkbox, so tests do not tap an ignored native child callback.
Future<void> saveActivate(WidgetTester t, Finder target, String input) async {
  await t.ensureVisible(target);
  await visibilityFrames(t);
  final matches = find
      .ancestor(of: target, matching: find.byType(StarBridgeCheckboxTile))
      .evaluate();
  final isTile =
      t.widget(target) is StarBridgeCheckboxTile || matches.isNotEmpty;
  final row = isTile ? saveTileFinder(t, target) : target;
  if (input == 'reader') {
    final semanticTarget = isTile
        ? find.bySemanticsLabel(
            RegExp('^${RegExp.escape(saveTile(t, target).label)}\$'),
          )
        : target;
    expect(semanticTarget, findsOneWidget);
    final node = t.getSemantics(semanticTarget);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  } else if (input == 'keyboard') {
    var focusTarget = target;
    if (isTile && t.widget(target) is StarBridgeCheckboxTile) {
      focusTarget = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (w) => w is Checkbox || w is SuiteCheckbox,
        ),
      );
    }
    final node = switch (t.widget(focusTarget)) {
      ButtonStyleButton button => button.focusNode!,
      Checkbox checkbox => checkbox.focusNode!,
      SuiteCheckbox checkbox => checkbox.focusNode!,
      SuitePressable pressable => pressable.focusNode!,
      _ => throw StateError('Unsupported save focus target'),
    };
    expect(node.canRequestFocus, isTrue);
    FocusScope.of(t.element(row)).unfocus();
    await t.pump();
    await t.pump();
    for (var i = 0; !node.hasPrimaryFocus && i < 100; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.pump();
    }
    expect(
      node.hasPrimaryFocus,
      isTrue,
      reason: 'target=$node\n${FocusManager.instance.toStringDeep()}',
    );
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    await t.tap(row);
  }
  await visibilityFrames(t);
}

Future<SaveProbe> mountSave(
  WidgetTester t,
  InteractionSuite suite, {
  bool duplicates = false,
  int count = 1,
  bool partial = false,
}) async {
  size(t, const Size(1100, 1100));
  final p = SaveProbe(suite)
    ..shipCount = count
    ..scanPhase = partial ? 'needsReview' : 'complete';
  if (duplicates) p.port.groups = saveGroups;
  await t.pumpWidget(p.app());
  await visibilityFrames(t);
  expect(p.port.reads, hasLength(1));
  expect(p.port.writes, isEmpty);
  return p;
}

Future<void> readySave(WidgetTester t, SaveProbe p) async {
  p.port.reads.last.complete(
    p.port.groups.isEmpty
        ? saveBaseline
        : const LocalHangarSnapshot(revision: 7, ships: saveShips),
  );
  await visibilityFrames(t);
  expect(p.port.previews, [(saveOperation, 7)]);
  expect(saveAction('confirm'), findsOneWidget);
}

InteractionSource saveSource(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

void expectSaveWaiting(
  WidgetTester t,
  InteractionSuite suite,
  String input, {
  bool reduced = false,
}) {
  expect(find.byType(HangarReaderWaiting), findsOneWidget);
  if (suite == InteractionSuite.standard) {
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      t
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      reduced || input != 'pointer' ? .5 : null,
    );
    expect(find.byType(SuiteProgressBar), findsNothing);
  } else if (reduced || input != 'pointer') {
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SuiteProgressBar), findsNothing);
  } else {
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(SuiteProgressBar), findsOneWidget);
  }
}

StarBridgeDialogRoute<Set<String>> saveReviewRoute(WidgetTester t) =>
    ModalRoute.of(t.element(find.byType(LocalHangarRemovalDialog)))!
        as StarBridgeDialogRoute<Set<String>>;

Future<void> chooseRemoval(WidgetTester t, String id, String input) async {
  final target = saveKey('hangar-remove-$id');
  await t.scrollUntilVisible(
    target,
    80,
    scrollable: find.descendant(
      of: saveKey('hangar-removal-list'),
      matching: find.byType(Scrollable),
    ),
  );
  await saveActivate(t, target, input);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets('$suite save $input inherits initial opening source', (
        t,
      ) async {
        size(t, const Size(1100, 1100));
        final semantics = t.ensureSemantics();
        final port = SaveMotionPort();
        StarBridgeDialogRoute<void>? owned;
        var saved = 0;
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) => StarBridgeActionButton(
                  controlKey: const Key('save-open'),
                  onActivate: (source) => unawaited(
                    showStarBridgeDialog<void>(
                      context,
                      source: source,
                      onRouteCreated: (route) => owned = route,
                      builder: (_) => Semantics(
                        scopesRoute: true,
                        explicitChildNodes: true,
                        child: Dialog(
                          child: SizedBox(
                            width: 850,
                            child: SingleChildScrollView(
                              child: LocalHangarSavePanel(
                                port: port,
                                view: const {
                                  'operationId': saveOperation,
                                  'shipCount': 1,
                                  'phase': 'complete',
                                },
                                onSaved: () => saved++,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open scan confirmation'),
                ),
              ),
              suite,
              reduce: false,
            ),
          );
          await visibilityFrames(t);
          await saveActivate(t, saveKey('save-open'), input);
          expect(owned!.instant, input != 'pointer');
          expect(port.reads, hasLength(1));
          expectSaveWaiting(t, suite, input);
          owned!.navigator!.removeRoute(owned!);
          await visibilityFrames(t);
          port.reads.single.complete(saveBaseline);
          await visibilityFrames(t);
          expect(port.writes, isEmpty);
          expect(saved, 0);
          expect(find.byType(LocalHangarSavePanel), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });

      testWidgets(
        '$suite save $input refusal rereads revision and uncertain checks GET only',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountSave(t, suite);
            expectSaveWaiting(t, suite, 'pointer');
            await readySave(t, p);
            expect(saveTile(t, saveAction('confirm')).value, isFalse);
            expect(saveButton(t, saveAction('save')).onActivate, isNull);
            await saveActivate(t, saveAction('confirm'), input);
            expect(p.port.writes, isEmpty);
            expect(saveTile(t, saveAction('confirm')).value, isTrue);
            await saveActivate(t, saveAction('save'), input);
            expect(p.port.writes, hasLength(1));
            final first = p.port.writes.single;
            expect(
              (first.operation, first.revision, first.empty, first.resolved),
              (saveOperation, 7, false, true),
            );
            expect(first.removed, isEmpty);
            expect(first.source, saveSource(input));
            expectSaveWaiting(t, suite, input);
            expect(saveAction('save'), findsNothing);
            first.gate.completeError(
              const LocalHangarFailure('hangar.revision_conflict'),
            );
            await visibilityFrames(t);
            expect(find.textContaining('机库已有更新'), findsOneWidget);
            expect(p.port.reads, hasLength(1));
            expect(p.saved, 0);
            await saveActivate(t, saveAction('save-retry'), input);
            expect(p.port.reads, hasLength(2));
            expect(p.port.readSources.last, saveSource(input));
            expect(p.port.writes, hasLength(1));
            expectSaveWaiting(t, suite, input);
            p.port.reads.last.complete(
              const LocalHangarSnapshot(revision: 9, ships: []),
            );
            await visibilityFrames(t);
            expect(saveTile(t, saveAction('confirm')).value, isFalse);
            expect(saveButton(t, saveAction('save')).onActivate, isNull);
            await saveActivate(t, saveAction('confirm'), input);
            await saveActivate(t, saveAction('save'), input);
            expect(p.port.writes, hasLength(2));
            final second = p.port.writes.last;
            expect(
              (second.operation, second.revision, second.empty),
              (saveOperation, 9, false),
            );
            expect(second.source, saveSource(input));
            second.gate.completeError(
              TimeoutException('Synthetic lost receipt'),
            );
            await visibilityFrames(t);
            expect(find.textContaining('尚未确认保存结果'), findsOneWidget);
            expect(saveAction('save'), findsNothing);
            expect(p.saved, 0);
            await saveActivate(t, saveAction('save-retry'), input);
            expect(p.port.reads, hasLength(3));
            expect(p.port.writes, hasLength(2));
            p.port.reads.last.complete(
              const LocalHangarSnapshot(
                revision: 10,
                operationId: saveOperation,
                ships: [],
              ),
            );
            await visibilityFrames(t);
            expect(p.saved, 1);
            expect(p.savedSources, [saveSource(input)]);
            expect(p.port.writes, hasLength(2));
            expect(p.port.previews, [(saveOperation, 7), (saveOperation, 9)]);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );

      for (final partial in [false, true]) {
        testWidgets(
          '$suite save $input ${partial ? 'partial keeps existing' : 'empty'} explicit confirmation',
          (t) async {
            final semantics = t.ensureSemantics();
            try {
              final p = await mountSave(
                t,
                suite,
                count: partial ? 2 : 0,
                partial: partial,
              );
              await readySave(t, p);
              expect(
                find.text(partial ? '确认保留已有舰船并保存' : '确认清空本机机库'),
                findsOneWidget,
              );
              if (partial) {
                expect(find.textContaining('暂不同步到组织'), findsOneWidget);
              }
              expect(saveButton(t, saveAction('save')).onActivate, isNull);
              await saveActivate(t, saveAction('confirm'), input);
              expect(p.port.writes, isEmpty);
              await saveActivate(t, saveAction('save'), input);
              expect(p.port.writes, hasLength(1));
              final request = p.port.writes.single;
              expect(
                (request.operation, request.revision, request.empty),
                (saveOperation, 7, !partial),
              );
              expect(request.removed, isEmpty);
              expect(request.source, saveSource(input));
              request.gate.complete(
                LocalHangarSnapshot(
                  revision: 8,
                  operationId: saveOperation,
                  partial: partial,
                  ships: partial ? saveShips : const [],
                ),
              );
              await visibilityFrames(t);
              expect(p.saved, 1);
              expect(p.savedSources, [saveSource(input)]);
              expect(p.port.reads, hasLength(1));
              expect(t.takeException(), isNull);
            } finally {
              await t.pumpWidget(const SizedBox());
              semantics.dispose();
            }
          },
        );
      }

      testWidgets(
        '$suite save $input removal cancel, exclusive choice, upper bound and final consent',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            final p = await mountSave(t, suite, duplicates: true, count: 2);
            await readySave(t, p);
            await saveActivate(t, saveAction('review-removals'), input);
            final route = saveReviewRoute(t);
            expect(route.instant, input != 'pointer');
            expect(route.barrierDismissible, isTrue);
            expect(
              route.traversalEdgeBehavior,
              TraversalEdgeBehavior.closedLoop,
            );
            expect(
              route.navigator,
              same(Navigator.of(p.pageContext, rootNavigator: true)),
            );
            await chooseRemoval(t, 'a', input);
            await chooseRemoval(t, 'c', input);
            expect(saveButton(t, removalAction('confirm')).onActivate, isNull);
            await saveActivate(t, removalAction('cancel'), input);
            expect(p.port.writes, isEmpty);
            await saveActivate(t, saveAction('review-removals'), input);
            expect(saveTile(t, saveKey('hangar-remove-a')).value, isFalse);
            expect(saveTile(t, saveKey('hangar-remove-c')).value, isFalse);
            await chooseRemoval(t, 'a', input);
            await chooseRemoval(t, 'b', input);
            expect(saveTile(t, saveKey('hangar-remove-a')).value, isFalse);
            expect(saveTile(t, saveKey('hangar-remove-b')).value, isTrue);
            await chooseRemoval(t, 'c', input);
            await chooseRemoval(t, 'd', input);
            final disabled = saveTile(t, saveKey('hangar-remove-e'));
            expect(disabled.value, isFalse);
            expect(disabled.onChanged, isNull);
            final disabledNode = t.getSemantics(
              find.bySemanticsLabel(
                RegExp('^${RegExp.escape(disabled.label)}\$'),
              ),
            );
            expect(
              disabledNode.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isFalse,
            );
            await chooseRemoval(t, 'c', input);
            expect(
              saveTile(t, saveKey('hangar-remove-e')).onChanged,
              isNotNull,
            );
            await chooseRemoval(t, 'e', input);
            expect(
              saveButton(t, removalAction('confirm')).onActivate,
              isNotNull,
            );
            await saveActivate(t, removalAction('confirm'), input);
            expect(find.byType(LocalHangarRemovalDialog), findsNothing);
            expect(p.port.writes, isEmpty);
            expect(saveTile(t, saveAction('confirm')).value, isFalse);
            expect(saveButton(t, saveAction('save')).onActivate, isNull);
            await saveActivate(t, saveAction('confirm'), input);
            await saveActivate(t, saveAction('save'), input);
            expect(p.port.writes, hasLength(1));
            final request = p.port.writes.single;
            expect(request.removed, unorderedEquals(['b', 'd', 'e']));
            expect(
              (request.operation, request.revision, request.empty),
              (saveOperation, 7, false),
            );
            request.gate.complete(
              LocalHangarSnapshot(
                revision: 8,
                operationId: saveOperation,
                ships: saveShips
                    .where((s) => !request.removed.contains(s.id))
                    .toList(),
                formerShips: saveShips
                    .where((s) => request.removed.contains(s.id))
                    .toList(),
              ),
            );
            await visibilityFrames(t);
            expect(p.saved, 1);
            expect(p.savedSources, [saveSource(input)]);
            expect(p.port.previews, [(saveOperation, 7)]);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite save each wait phase uses the actual command source, not the initial field',
      (t) async {
        size(t, const Size(1100, 1100));
        final p = SaveProbe(suite)..initialSource = InteractionSource.keyboard;
        await t.pumpWidget(p.app());
        await visibilityFrames(t);
        expectSaveWaiting(t, suite, 'keyboard');
        final first = t.state(find.byType(HangarReaderWaiting));
        await readySave(t, p);
        await saveActivate(t, saveAction('confirm'), 'pointer');
        await saveActivate(t, saveAction('save'), 'pointer');
        expectSaveWaiting(t, suite, 'pointer');
        expect(t.state(find.byType(HangarReaderWaiting)), isNot(same(first)));
        p.port.writes.single.gate.completeError(
          const LocalHangarFailure('hangar.storage_write_failed'),
        );
        await visibilityFrames(t);
        await saveActivate(t, saveAction('save-retry'), 'keyboard');
        expect(p.port.readSources.last, InteractionSource.keyboard);
        expectSaveWaiting(t, suite, 'keyboard');
        final retry = t.state(find.byType(HangarReaderWaiting));
        p.update(() {
          p.initialSource = InteractionSource.pointer;
          p.light = true;
        });
        await visibilityFrames(t);
        expect(t.state(find.byType(HangarReaderWaiting)), same(retry));
        expectSaveWaiting(t, suite, 'keyboard');
        p.port.reads.last.complete(
          const LocalHangarSnapshot(revision: 8, ships: []),
        );
        await visibilityFrames(t);
        expect(p.port.writes, hasLength(1));
        expect(p.saved, 0);
        expect(saveTile(t, saveAction('confirm')).value, isFalse);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite save live theme and reduce settle pending read and preserve review selection',
      (t) async {
        final p = await mountSave(t, suite, duplicates: true);
        expectSaveWaiting(t, suite, 'pointer');
        p.update(() {
          p.reduce = true;
          p.light = true;
        });
        await t.pump();
        await t.pump();
        expectSaveWaiting(t, suite, 'pointer', reduced: true);
        expect(p.port.reads, hasLength(1));
        await readySave(t, p);
        await saveActivate(t, saveAction('review-removals'), 'pointer');
        await chooseRemoval(t, 'b', 'pointer');
        final route = saveReviewRoute(t);
        final body = t.state(find.byType(LocalHangarRemovalDialog));
        p.update(() {
          p.reduce = false;
          p.light = false;
        });
        await t.pump();
        await t.pump();
        expect(saveReviewRoute(t), same(route));
        expect(t.state(find.byType(LocalHangarRemovalDialog)), same(body));
        expect(saveTile(t, saveKey('hangar-remove-b')).value, isTrue);
        expect(
          Theme.of(t.element(find.byType(LocalHangarRemovalDialog))).brightness,
          Brightness.dark,
        );
        await t.sendKeyEvent(LogicalKeyboardKey.escape);
        await t.pump();
        expect(find.byType(LocalHangarRemovalDialog), findsNothing);
        expect(p.port.writes, isEmpty);
        expect(p.port.reads, hasLength(1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite save reader disposal during review exit retires only its exact route',
      (t) async {
        final p = await mountSave(t, suite, duplicates: true);
        await readySave(t, p);
        await saveActivate(t, saveAction('review-removals'), 'pointer');
        final owned = saveReviewRoute(t);
        var retired = false;
        unawaited(owned.completed.then((_) => retired = true));
        await t.tap(removalAction('cancel'));
        await t.pump();
        if (suite != InteractionSuite.standard) {
          expect(owned.animation!.status, AnimationStatus.reverse);
        }
        final navigator = Navigator.of(p.pageContext, rootNavigator: true);
        final foreign = DialogRoute<void>(
          context: p.pageContext,
          builder: (_) => const AlertDialog(content: Text('Foreign route')),
        );
        unawaited(navigator.push(foreign));
        p.update(() => p.shown = false);
        await visibilityFrames(t);
        expect(foreign.isActive, isTrue);
        expect(foreign.isCurrent, isTrue);
        expect(retired, isTrue);
        expect(
          find.byType(LocalHangarRemovalDialog, skipOffstage: false),
          findsNothing,
        );
        expect(find.text('Foreign route'), findsOneWidget);
        expect(p.port.writes, isEmpty);
        navigator.removeRoute(foreign);
        await visibilityFrames(t);
        expect(find.text('Reader left'), findsOneWidget);
        expect(p.saved, 0);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      '$suite save late read and late commit cannot complete a retired reader',
      (t) async {
        final p = await mountSave(t, suite);
        p.update(() => p.shown = false);
        await visibilityFrames(t);
        p.port.reads.single.complete(saveBaseline);
        await visibilityFrames(t);
        expect(p.saved, 0);
        expect(p.port.previews, isEmpty);
        p.update(() => p.shown = true);
        await visibilityFrames(t);
        expect(p.port.reads, hasLength(2));
        p.port.reads.last.complete(saveBaseline);
        await visibilityFrames(t);
        await saveActivate(t, saveAction('confirm'), 'pointer');
        await saveActivate(t, saveAction('save'), 'pointer');
        p.update(() => p.shown = false);
        await visibilityFrames(t);
        p.port.writes.single.gate.complete(
          const LocalHangarSnapshot(
            revision: 8,
            operationId: saveOperation,
            ships: [],
          ),
        );
        await visibilityFrames(t);
        expect(p.saved, 0);
        expect(p.port.writes, hasLength(1));
        expect(find.text('Reader left'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
}
