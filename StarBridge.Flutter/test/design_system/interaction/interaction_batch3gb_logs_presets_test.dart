import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_row.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_logs_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_logs_copy.dart'
    show communityLogsCopy;
import 'package:starbridge_flutter/features/communities/community_logs_port.dart';
import 'package:starbridge_flutter/features/communities/community_preset_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_preset_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_inspection_port.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_import_preview.dart';
import 'package:starbridge_flutter/features/overlay_settings/overlay_preset_transfer.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_logs_test.dart'
    show LogsFake, logsPayload;
import '../../features/communities/community_preset_test.dart'
    show PresetFake, card, package, catalogPayload;
import '../../features/overlay_settings/overlay_settings_ux_a_test.dart'
    show settings;
import '../../features/overlay_settings/overlay_preset_transfer_test.dart'
    show layout;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fw_workspace_test.dart' show activate;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3am_test.dart' as governance show action;

final _review = visualOutputDir(
  'interaction_motion_batch3gb_20261017',
  legacySubdirectory: 'review',
);
const _target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _log = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _Logs implements CommunityLogsPort {
  final fake = LogsFake();
  final reads = <(String, String, String, int)>[];
  final writes = <(String, String)>[];
  @override
  bool get logsAvailable => fake.logsAvailable;
  @override
  bool get logDeletionAvailable => fake.logDeletionAvailable;
  @override
  Stream<void> get invalidations => fake.invalidations;
  @override
  Future<CommunityLogPage> readLogs(
    String target,
    String type,
    String query,
    int offset,
  ) {
    reads.add((target, type, query, offset));
    return fake.readLogs(target, type, query, offset);
  }

  @override
  Future<CommunityLogOutcome> deleteLog(String target, String ref) {
    writes.add((target, ref));
    return fake.deleteLog(target, ref);
  }

  void readDone({bool fail = false, bool empty = false}) {
    if (fail) {
      fake.pending!.completeError(const CommunityFailure('unavailable'));
      return;
    }
    final last = reads.last;
    final data = logsPayload()
      ..['targetRef'] = last.$1
      ..['type'] = last.$2
      ..['query'] = last.$3
      ..['offset'] = last.$4;
    if (empty) {
      data['items'] = [];
      data['totalCount'] = data['matchedCount'] = 0;
    }
    fake.pending!.complete(CommunityLogPage.parse(data));
  }
}

class _Preset extends PresetFake {
  Completer<Map<String, Object?>>? exporting;
  Completer<String>? importing;
  Map<String, Object?>? submitted;
  String? selected;
  @override
  Future<Map<String, Object?>> exportCommunityPreset(String id, int version) {
    exports++;
    revision = version;
    selected = id;
    return exporting?.future ?? Future.value(card);
  }

  @override
  Future<String> importCommunityPreset(
    Map<String, Object?> attachment,
    int version,
  ) {
    imports++;
    revision = version;
    submitted = attachment;
    return importing?.future ?? Future.value('Fixture');
  }
}

class _Inspector extends _Preset implements OverlayPresetInspectionPort {
  int inspections = 0;
  int? checkedRevision;
  String? checkedPackage;
  Completer<OverlayPresetTransfer>? checking;
  @override
  Future<OverlayPresetTransfer> inspectPreset(String value, int revision) {
    inspections++;
    checkedRevision = revision;
    checkedPackage = value;
    return checking?.future ?? Future.value(preview());
  }
}

OverlayPresetTransfer preview() => OverlayPresetTransfer(
  name: 'Fixture',
  settings: settings(),
  layout: layout,
);

class _Probe {
  _Probe(
    this.kind,
    this.suite, {
    this.light = false,
    this.large = false,
    this.embedded = false,
  });
  final String kind;
  final InteractionSuite suite;
  final logs = _Logs();
  final plain = _Preset();
  final inspector = _Inspector();
  _Preset get preset => kind == 'inspect' ? inspector : plain;
  bool light, large, embedded, reduce = false;
  final capture = GlobalKey();
  late StateSetter update;
  Object? result;
  dynamic state(WidgetTester t) =>
      t.state(find.byType(CommunityLogsDialog)) as dynamic;
  Widget dialog() => kind == 'logs'
      ? CommunityLogsDialog(port: logs, targetRef: _target, embedded: embedded)
      : CommunityPresetDialog(
          port: preset,
          attachment: kind == 'share' ? null : card,
        );
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-logs-preset'),
              onActivate: (_) async {
                result = await showStarBridgeDialog<Object?>(
                  context,
                  barrierDismissible: false,
                  builder: (_) =>
                      embedded ? Material(child: dialog()) : dialog(),
                );
              },
              child: const Text('Open read stage'),
            ),
          ),
          suite,
          light: light,
          reduce: reduce,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
          home: base.home,
        );
      },
    ),
  );
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await logs.fake.changes.close();
    await plain.changes.close();
    await inspector.changes.close();
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await activate(t, const Key('open-logs-preset'), source);
  await frames(t);
}

Finder marker(String phase) => find.byKey(ValueKey('$phase-activity'));
void waiting(WidgetTester t, String phase, {required bool animated}) {
  expect(marker(phase), findsOneWidget);
  final target = find.descendant(
    of: marker(phase),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(target, findsOneWidget);
  expect(InteractionScope.of(t.element(target)).reduceMotion, !animated);
}

Finder button(String label) => find.byWidgetPredicate(
  (w) =>
      w is StarBridgeActionButton &&
      w.child is Text &&
      (w.child as Text).data == label,
);
Future<void> press(WidgetTester t, String label, String source) async {
  await actTarget(t, button(label), source);
  await frames(t);
}

Future<void> actTarget(WidgetTester t, Finder target, String source) async {
  await t.ensureVisible(target);
  await t.pump();
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final focus = find.descendant(
      of: target,
      matching: find.byType(FocusableActionDetector),
    );
    final node = focus.evaluate().isNotEmpty
        ? t.widget<FocusableActionDetector>(focus.first).focusNode
        : t
              .widget<ButtonStyleButton>(
                find
                    .descendant(
                      of: target,
                      matching: find.byWidgetPredicate(
                        (w) => w is ButtonStyleButton,
                      ),
                    )
                    .first,
              )
              .focusNode;
    node!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final semantic = find.descendant(
      of: target,
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.onTap != null,
      ),
    );
    final node = t.getSemantics(semantic.first);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      ui.SemanticsAction.tap,
    );
  }
  await t.pump();
  await frames(t);
}

Future<void> flush(WidgetTester t) async {
  await t.runAsync(() => Future<void>.delayed(Duration.zero));
  await frames(t);
}

void main() {
  setUpAll(loadFonts);
  moreCases();
  for (final kind in ['logs', 'share']) {
    testWidgets('3gb $kind keyboard initial wait must not loop', (t) async {
      final p = _Probe(kind, InteractionSuite.standard);
      if (kind == 'logs') {
        p.logs.fake.pending = Completer();
      } else {
        p.preset.heldRead = Completer();
      }
      try {
        await open(t, p, 'keyboard');
        expect(
          t
              .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator),
              )
              .value,
          isNotNull,
        );
        if (kind == 'logs') {
          p.logs.readDone();
        } else {
          p.preset.heldRead!.complete(
            CommunityPresetCatalog.parse(catalogPayload()),
          );
        }
        await frames(t);
      } finally {
        await p.clean(t);
      }
    });
  }
}

// ignore: library_private_types_in_public_api
Future<void> catalogDone(_Probe p, {bool fail = false}) async {
  if (fail) {
    p.preset.heldRead!.completeError(const CommunityFailure('unavailable'));
  } else {
    p.preset.heldRead!.complete(CommunityPresetCatalog.parse(catalogPayload()));
  }
}

Future<void> exportChoice(WidgetTester t, String source) async {
  await actTarget(
    t,
    find.byWidgetPredicate(
      (w) =>
          w is StarBridgeActionRow &&
          w.controlKey == const ValueKey('community-preset-choice-preset-test'),
    ),
    source,
  );
}

Future<List<int>> pixels(
  WidgetTester t,
  // ignore: library_private_types_in_public_api
  _Probe p,
  Rect rect, {
  String? png,
}) async {
  final boundary =
      p.capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await t.runAsync(() async {
    final image = await boundary.toImage();
    try {
      if (png != null) {
        await Directory(_review).create(recursive: true);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('$_review/$png.png')
            .writeAsBytes(data!.buffer.asUint8List());
      }
      final raw = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
          .buffer
          .asUint8List();
      return [
        for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++)
          ...raw.sublist(
            (y * image.width + rect.left.ceil()) * 4,
            (y * image.width + rect.right.floor()) * 4,
          ),
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void moreCases() {
  for (final suite in InteractionSuite.values) {
    for (final kind in ['logs', 'share', 'inspect']) {
      testWidgets(
        '3gb $kind $suite read failure keyboard retry then invalidation',
        (t) async {
          final p = _Probe(kind, suite);
          try {
            if (kind == 'logs') {
              p.logs.fake.pending = Completer();
            } else {
              p.preset.heldRead = Completer();
            }
            await open(t, p, 'pointer');
            if (kind == 'logs') {
              p.logs.readDone(fail: true);
            } else {
              await catalogDone(p, fail: true);
            }
            await flush(t);
            if (kind == 'logs') {
              p.logs.fake.pending = Completer();
              await activate(t, const Key('log-reload'), 'keyboard');
              waiting(t, 'logs-read', animated: false);
              p.logs.fake.changes.add(null);
              await frames(t);
              p.logs.readDone();
            } else {
              p.preset.heldRead = Completer();
              await press(t, '重试', 'keyboard');
              waiting(t, 'preset-read', animated: false);
              p.preset.changes.add(null);
              await frames(t);
              await catalogDone(p);
            }
            await flush(t);
            expect(find.byType(SuiteBusyFrame), findsNothing);
            expect(p.logs.writes, isEmpty);
            expect(p.preset.exports, 0);
            expect(p.preset.imports, 0);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }
    testWidgets(
      '3gb logs $suite invalidated delete cannot reread or report late success',
      (t) async {
        final p = _Probe('logs', suite);
        try {
          await open(t, p, 'pointer');
          await activate(t, const ValueKey('log-delete-$_log'), 'pointer');
          p.logs.fake.writePending = Completer();
          await activate(t, const Key('log-confirm-delete'), 'pointer');
          p.logs.fake.changes.add(null);
          await frames(t);
          expect(marker('logs-delete'), findsNothing);
          p.logs.fake.writePending!.complete(
            const CommunityLogOutcome('accepted'),
          );
          await flush(t);
          expect(p.logs.writes.length, 1);
          expect(p.logs.reads.length, 1);
          expect(p.state(t).model.lastOutcome, isNull);
          expect(find.text('成员加入'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );
    testWidgets(
      '3gb logs $suite accepted delete survives independent reread failure',
      (t) async {
        final p = _Probe('logs', suite);
        try {
          await open(t, p, 'pointer');
          await activate(t, const ValueKey('log-delete-$_log'), 'pointer');
          p.logs.fake.writePending = Completer();
          await activate(t, const Key('log-confirm-delete'), 'keyboard');
          p.logs.fake.pending = Completer();
          p.logs.fake.writePending!.complete(
            const CommunityLogOutcome('accepted'),
          );
          await flush(t);
          waiting(t, 'logs-read', animated: false);
          p.logs.readDone(fail: true);
          await flush(t);
          expect(p.state(t).model.lastOutcome, 'accepted');
          expect(p.state(t).model.error, 'unavailable');
          expect(p.logs.writes.length, 1);
          expect(p.logs.reads.length, 2);
          expect(find.text(communityLogsCopy['deleted']!.$1), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );
    testWidgets(
      '3gb inspect $suite failure before preview remains read retry not uncertain write',
      (t) async {
        final p = _Probe('inspect', suite);
        try {
          await open(t, p, 'pointer');
          p.inspector.checking = Completer();
          await press(t, '导入为新方案', 'pointer');
          p.inspector.checking!.completeError(const FormatException());
          await flush(t);
          expect(marker('preset-inspect'), findsNothing);
          expect(p.inspector.imports, 0);
          expect(find.byType(OverlayPresetImportPreview), findsNothing);
          p.preset.heldRead = Completer();
          await press(t, '重试', 'keyboard');
          waiting(t, 'preset-read', animated: false);
          await catalogDone(p);
          await flush(t);
          expect(p.preset.reads, 2);
          expect(p.inspector.imports, 0);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );
    for (final phase in ['read', 'export', 'inspect', 'preview', 'import']) {
      testWidgets(
        '3gb preset $suite invalidate $phase ignores late work and retires only preview',
        (t) async {
          final kind = phase == 'inspect' || phase == 'preview'
              ? 'inspect'
              : phase == 'import'
              ? 'import'
              : 'share';
          final p = _Probe(kind, suite);
          try {
            if (phase == 'read') p.preset.heldRead = Completer();
            await open(t, p, 'pointer');
            if (phase == 'export') {
              p.preset.exporting = Completer();
              await exportChoice(t, 'pointer');
            }
            if (phase == 'inspect') {
              p.inspector.checking = Completer();
              await press(t, '导入为新方案', 'pointer');
            }
            if (phase == 'preview') {
              await press(t, '导入为新方案', 'pointer');
              await t.pumpAndSettle();
              expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
            }
            if (phase == 'import') {
              p.preset.importing = Completer();
              await press(t, '导入为新方案', 'pointer');
            }
            p.preset.changes.add(null);
            await frames(t);
            expect(find.byType(OverlayPresetImportPreview), findsNothing);
            expect(find.byType(SuiteBusyFrame), findsNothing);
            if (phase == 'read') await catalogDone(p);
            if (phase == 'export') p.preset.exporting!.complete(card);
            if (phase == 'inspect') p.inspector.checking!.complete(preview());
            if (phase == 'import') p.preset.importing!.complete('Fixture');
            await flush(t);
            expect(p.result, isNull);
            expect(find.text('已新增方案: Fixture'), findsNothing);
            expect(find.byType(CommunityPresetDialog), findsOneWidget);
            expect(p.preset.imports, phase == 'import' ? 1 : 0);
            expect(p.preset.exports, phase == 'export' ? 1 : 0);
            expect(button('重试'), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final kind in ['logs', 'share', 'import', 'inspect']) {
        testWidgets('3gb $kind $suite $source initial wait live reduce', (
          t,
        ) async {
          final p = _Probe(kind, suite);
          if (kind == 'logs') {
            p.logs.fake.pending = Completer();
          } else {
            p.preset.heldRead = Completer();
          }
          final phase = kind == 'logs' ? 'logs-read' : 'preset-read';
          try {
            await open(t, p, source);
            waiting(t, phase, animated: source == 'pointer');
            p.update(() => p.reduce = true);
            await t.pump();
            await t.pump();
            waiting(t, phase, animated: false);
            p.update(() => p.reduce = false);
            await t.pump();
            await t.pump();
            waiting(t, phase, animated: source == 'pointer');
            if (kind == 'logs') {
              p.logs.readDone();
            } else {
              await catalogDone(p);
            }
            await frames(t);
            expect(marker(phase), findsNothing);
            expect(p.logs.writes, isEmpty);
            expect(p.preset.imports, 0);
            expect(p.preset.exports, 0);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        });
      }
      testWidgets(
        '3gb logs $suite $source actual delete cancel then accepted reread',
        (t) async {
          final p = _Probe('logs', suite);
          try {
            await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
            await activate(t, const ValueKey('log-delete-$_log'), source);
            expect(p.logs.writes, isEmpty);
            await activate(t, const Key('log-keep'), source);
            expect(p.logs.writes, isEmpty);
            await activate(
              t,
              const ValueKey('log-delete-$_log'),
              source == 'pointer' ? 'keyboard' : 'pointer',
            );
            p.logs.fake.writePending = Completer();
            await activate(t, const Key('log-confirm-delete'), source);
            waiting(t, 'logs-delete', animated: source == 'pointer');
            expect(p.logs.writes, [(_target, _log)]);
            p.logs.fake.pending = Completer();
            p.logs.fake.writePending!.complete(
              const CommunityLogOutcome('accepted'),
            );
            await flush(t);
            expect(marker('logs-delete'), findsNothing);
            waiting(t, 'logs-read', animated: source == 'pointer');
            expect(p.state(t).model.lastOutcome, 'accepted');
            expect(p.logs.reads.length, 2);
            p.logs.readDone(empty: true);
            await flush(t);
            expect(marker('logs-read'), findsNothing);
            expect(find.text(communityLogsCopy['deleted']!.$1), findsOneWidget);
            expect(p.logs.writes.length, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );

      testWidgets('3gb logs $suite $source actual search and category phases', (
        t,
      ) async {
        final p = _Probe('logs', suite);
        try {
          await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
          await t.enterText(find.byKey(const Key('log-search')), 'pilot');
          p.logs.fake.pending = Completer();
          if (source == 'keyboard') {
            await t.testTextInput.receiveAction(TextInputAction.done);
            await frames(t);
          } else {
            await activate(t, const Key('log-search-submit'), source);
          }
          waiting(t, 'logs-read', animated: source == 'pointer');
          expect(p.logs.reads.last, (_target, 'All', 'pilot', 0));
          p.logs.readDone();
          await flush(t);
          p.logs.fake.pending = Completer();
          await governance.action(
            t,
            const ValueKey('log-filter-成员'),
            source,
            settle: false,
          );
          await frames(t);
          waiting(t, 'logs-read', animated: source == 'pointer');
          expect(p.logs.reads.last, (_target, '成员', 'pilot', 0));
          p.logs.readDone();
          await flush(t);
          expect(p.logs.reads.length, 3);
          expect(p.logs.writes, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });

      testWidgets(
        '3gb share $suite $source export waits exact attachment without sending',
        (t) async {
          final p = _Probe('share', suite);
          try {
            await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
            p.preset.exporting = Completer();
            await exportChoice(t, source);
            waiting(t, 'preset-export', animated: source == 'pointer');
            expect(p.preset.exports, 1);
            expect(p.preset.imports, 0);
            expect(p.result, isNull);
            expect(p.preset.selected, 'preset-test');
            expect(p.preset.revision, 9);
            p.preset.exporting!.complete(card);
            await flush(t);
            expect(p.result, card);
            expect(find.byType(CommunityPresetDialog), findsNothing);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
      testWidgets(
        '3gb import $suite $source legacy no-inspection additive write',
        (t) async {
          final p = _Probe('import', suite);
          try {
            await open(t, p, source == 'pointer' ? 'keyboard' : 'pointer');
            p.preset.importing = Completer();
            await press(t, '导入为新方案', source);
            waiting(t, 'preset-import', animated: source == 'pointer');
            expect(p.preset.imports, 1);
            expect(p.preset.exports, 0);
            expect(p.preset.submitted, card);
            expect(p.preset.revision, 9);
            p.preset.importing!.complete('Fixture');
            await flush(t);
            expect(marker('preset-import'), findsNothing);
            expect(find.text('已新增方案: Fixture'), findsOneWidget);
            expect(button('导入为新方案'), findsNothing);
            expect(p.preset.imports, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
      testWidgets(
        '3gb inspect $suite $source held inspect covered preview cancel final-source import',
        (t) async {
          final p = _Probe('inspect', suite);
          final first = source == 'pointer' ? 'keyboard' : 'pointer';
          try {
            await open(t, p, source);
            p.inspector.checking = Completer();
            await press(t, '导入为新方案', first);
            waiting(t, 'preset-inspect', animated: first == 'pointer');
            expect(p.inspector.imports, 0);
            expect(p.inspector.checkedRevision, 9);
            expect(p.inspector.checkedPackage, package);
            p.inspector.checking!.complete(preview());
            await flush(t);
            await t.pumpAndSettle();
            expect(find.byType(OverlayPresetImportPreview), findsOneWidget);
            expect(
              find.byKey(
                const ValueKey('preset-inspect-activity'),
                skipOffstage: false,
              ),
              findsNothing,
            );
            await press(t, '取消', source);
            expect(p.inspector.imports, 0);
            expect(p.inspector.reads, 1);
            p.inspector.checking = Completer();
            await press(t, '导入为新方案', first);
            p.inspector.checking!.complete(preview());
            await flush(t);
            await t.pumpAndSettle();
            p.inspector.importing = Completer();
            await activate(t, const Key('overlay-import-confirm'), source);
            waiting(t, 'preset-import', animated: source == 'pointer');
            expect(p.inspector.imports, 1);
            expect(p.inspector.inspections, 2);
            expect(p.inspector.submitted, card);
            expect(p.inspector.revision, 9);
            p.inspector.importing!.complete('Fixture');
            await flush(t);
            expect(marker('preset-import'), findsNothing);
            expect(find.text('已新增方案: Fixture'), findsOneWidget);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }

    testWidgets(
      '3gb logs $suite quiet read stays without new marker and retains page on failure',
      (t) async {
        final p = _Probe('logs', suite, embedded: true);
        try {
          await open(t, p, 'pointer');
          final page = p.state(t).model.snapshot;
          p.logs.fake.pending = Completer();
          final job = p.state(t).refreshVisibleCommunity() as Future<void>;
          await frames(t);
          expect(marker('logs-read'), findsNothing);
          expect(identical(page, p.state(t).model.snapshot), isTrue);
          p.logs.readDone(fail: true);
          await job;
          await frames(t);
          expect(identical(page, p.state(t).model.snapshot), isTrue);
          expect(p.logs.writes, isEmpty);
          expect(p.logs.reads.length, 2);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      },
    );
    for (final outcome in ['unknown', 'rejected']) {
      testWidgets(
        '3gb logs $suite $outcome consumes ref and requires reread and reselection',
        (t) async {
          final p = _Probe('logs', suite);
          try {
            await open(t, p, 'pointer');
            await activate(t, const ValueKey('log-delete-$_log'), 'pointer');
            p.logs.fake.writePending = Completer();
            await activate(t, const Key('log-confirm-delete'), 'keyboard');
            p.logs.fake.writePending!.complete(
              CommunityLogOutcome(outcome, error: 'outcomeUnknown'),
            );
            await flush(t);
            expect(marker('logs-delete'), findsNothing);
            expect(p.logs.reads.length, 1);
            expect(find.byKey(const Key('log-confirm-delete')), findsNothing);
            p.logs.fake.pending = Completer();
            await activate(t, const Key('log-reload'), 'keyboard');
            waiting(t, 'logs-read', animated: false);
            p.logs.readDone();
            await flush(t);
            expect(p.logs.writes.length, 1);
            await activate(t, const ValueKey('log-delete-$_log'), 'keyboard');
            await activate(t, const Key('log-keep'), 'pointer');
            expect(p.logs.writes.length, 1);
            expect(t.takeException(), isNull);
          } finally {
            await p.clean(t);
          }
        },
      );
    }
    for (final error in [
      'presetChanged',
      'presetInvalid',
      'presetImportUnknown',
    ]) {
      testWidgets('3gb import $suite $error preserves original retry lock', (
        t,
      ) async {
        final p = _Probe('import', suite);
        try {
          await open(t, p, 'pointer');
          p.preset.importing = Completer();
          await press(t, '导入为新方案', 'keyboard');
          p.preset.importing!.completeError(CommunityFailure(error));
          await flush(t);
          expect(marker('preset-import'), findsNothing);
          expect(p.preset.imports, 1);
          expect(button('导入为新方案'), findsNothing);
          if (error == 'presetImportUnknown') {
            expect(button('重试'), findsNothing);
          } else {
            p.preset.heldRead = Completer();
            await press(t, '重试', 'keyboard');
            waiting(t, 'preset-read', animated: false);
            await catalogDone(p);
            await flush(t);
            expect(p.preset.reads, 2);
            expect(p.preset.imports, 1);
          }
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });
    }
    for (final phase in [
      'logs-read',
      'logs-delete',
      'preset-read',
      'preset-export',
      'preset-inspect',
      'preset-import',
    ]) {
      testWidgets('3gb $suite $phase actual Chinese large wait visual', (
        t,
      ) async {
        final kind = phase.startsWith('logs')
            ? 'logs'
            : phase == 'preset-inspect'
            ? 'inspect'
            : phase == 'preset-import'
            ? 'import'
            : 'share';
        final p = _Probe(
          kind,
          suite,
          large: true,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
        try {
          if (phase == 'logs-read') p.logs.fake.pending = Completer();
          if (phase == 'preset-read') p.preset.heldRead = Completer();
          await open(t, p, 'pointer');
          if (phase == 'logs-delete') {
            await activate(t, const ValueKey('log-delete-$_log'), 'pointer');
            p.logs.fake.writePending = Completer();
            await activate(t, const Key('log-confirm-delete'), 'pointer');
          }
          if (phase == 'preset-export') {
            p.preset.exporting = Completer();
            await exportChoice(t, 'pointer');
          }
          if (phase == 'preset-inspect') {
            p.inspector.checking = Completer();
            await press(t, '导入为新方案', 'pointer');
          }
          if (phase == 'preset-import') {
            p.preset.importing = Completer();
            await press(t, '导入为新方案', 'pointer');
          }
          waiting(t, phase, animated: true);
          await frames(t);
          final rect = t.getRect(marker(phase));
          final a = await pixels(t, p, rect, png: '$phase-${suite.name}');
          await frames(t, 17);
          final b = await pixels(t, p, rect);
          final moving = changed(a, b);
          expect(moving, greaterThan(0));
          p.update(() => p.reduce = true);
          await t.pump();
          await t.pump();
          final c = await pixels(t, p, rect);
          await frames(t, 38);
          final d = await pixels(t, p, rect);
          final still = changed(c, d);
          expect(still, 0);
          expect(t.getRect(marker(phase)), rect);
          File('$_review/$phase-${suite.name}.json').writeAsStringSync(
            jsonEncode({
              'movingPixels': moving,
              'staticPixels': still,
              'rect': [rect.left, rect.top, rect.width, rect.height],
            }),
          );
          await t.pumpWidget(const SizedBox());
          if (phase == 'logs-read') p.logs.readDone();
          if (phase == 'logs-delete') {
            p.logs.fake.writePending!.complete(
              const CommunityLogOutcome('accepted'),
            );
          }
          if (phase == 'preset-read') await catalogDone(p);
          if (phase == 'preset-export') p.preset.exporting!.complete(card);
          if (phase == 'preset-inspect') {
            p.inspector.checking!.complete(preview());
          }
          if (phase == 'preset-import') p.preset.importing!.complete('Fixture');
          await flush(t);
          expect(t.takeException(), isNull);
        } finally {
          await p.clean(t);
        }
      });
    }
  }
}
