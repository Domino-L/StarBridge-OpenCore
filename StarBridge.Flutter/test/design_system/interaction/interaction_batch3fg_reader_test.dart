import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_checkbox_tile.dart';
import 'package:starbridge_flutter/features/account/account_module.dart';
import 'package:starbridge_flutter/features/account/in_memory_account_adapter.dart';
import 'package:starbridge_flutter/features/hangar/hangar_browser_viewport.dart';
import 'package:starbridge_flutter/features/hangar/hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_copy.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_port.dart';
import 'package:starbridge_flutter/features/hangar/hangar_reader_waiting.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_status.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_panel.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/hangar/hangar_reader_test.dart'
    show BrowserFake, PreviewFake, result;
import 'interaction_batch3fb_hangar_test.dart' show HangarProbePort;
import 'interaction_batch3i_test.dart' show scopedApp;

InteractionSource _source(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;
Finder _key(String value) => find.byKey(Key(value));

/// Controlled browser/Host seams only. The real Page creates its own sole
/// ReaderController; these ports never navigate or save on the Page's behalf.
class _Browser extends BrowserFake {
  Completer<void>? pendingOpen;
  final openingSources = <InteractionSource>[];
  final captureSources = <InteractionSource>[];
  @override
  Future<void> open({required String profileKey}) async {
    openingSources.add(currentStarBridgeActivationSource);
    await super.open(profileKey: profileKey);
    await pendingOpen?.future;
  }

  @override
  Future<Map<String, Object?>> capture() async {
    captureSources.add(currentStarBridgeActivationSource);
    // Port callbacks can run from a semantics handler's registration zone
    // during pump. Keep the original lock assertion without a test API guard.
    expectSync(locked, true);
    events.add('capture');
    if (captureDelay > Duration.zero) {
      await Future<void>.delayed(captureDelay);
    }
    if (loadingCount-- > 0) throw const HangarReaderFailure('loading');
    if (captureQueue.isNotEmpty) return captureQueue.removeAt(0)?.future ?? {};
    return pendingCapture?.future ?? {};
  }

  @override
  Future<void> page(int page) async {
    expectSync(locked, true);
    events.add('page:$page');
    pages.add(page);
  }

  void release() {
    if (pendingOpen case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    if (pendingCapture case final gate? when !gate.isCompleted) {
      gate.complete({});
    }
  }
}

class _Preview extends PreviewFake {
  final beginSources = <InteractionSource>[];
  @override
  Future<Map<String, Object?>> begin() {
    beginSources.add(currentStarBridgeActivationSource);
    return super.begin();
  }

  void release() {
    if (pendingBegin case final gate? when !gate.isCompleted) {
      gate.complete(result('ready'));
    }
    if (pendingVerify case final gate? when !gate.isCompleted) {
      gate.complete(result('reading'));
    }
  }
}

class _CompletionPort extends HangarProbePort {
  final receipt = Completer<LocalHangarSnapshot>();
  final commands = <(String, int, bool, InteractionSource)>[];
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    saves++;
    commands.add((
      operationId,
      expectedRevision,
      confirmEmpty,
      currentStarBridgeActivationSource,
    ));
    final accepted = await receipt.future;
    snapshot = accepted;
    return accepted;
  }
}

class _Host {
  _Host(this.suite, this.account, this.browser, this.preview, this.local);
  InteractionSuite suite;
  final AccountModule account;
  final _Browser browser;
  final _Preview preview;
  final HangarProbePort? local;
  bool reduce = false, light = false, visible = true;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        visible
            ? HangarPage(
                key: const Key('reader-real-page'),
                account: account,
                browserFactory: () => browser,
                previewFactory: () => preview,
                localFactory: local == null ? null : () => local!,
              )
            : const Text('reader departed'),
        suite,
        reduce: reduce,
        light: light,
      );
    },
  );
}

Future<void> _frames(WidgetTester t, [int count = 3]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> _tail(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _withSemantics(
  WidgetTester t,
  Future<void> Function() body,
) async {
  final handle = t.ensureSemantics();
  try {
    await body();
  } finally {
    // addTearDown is later than the widget binding's handle verification.
    handle.dispose();
  }
}

/// All commands go through actual pointer/Tab-Enter/exposed semantic input.
/// Public focus nodes are observed only, never requestFocus or callbacks.
Future<void> _act(WidgetTester t, String key, String input) async {
  final target = _key(key);
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _tail(t);
  if (input == 'pointer') {
    await t.tap(target);
  } else if (input == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else {
    final widget = t.widget(target);
    final focus = switch (widget) {
      ButtonStyleButton button => button.focusNode!,
      IconButton button => button.focusNode!,
      SuitePressable pressable =>
        pressable.focusNode ??
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
      _ => throw StateError('Unsupported actual input target $widget'),
    };
    var tabs = 0;
    while (!focus.hasPrimaryFocus && tabs < 100) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(t, 2);
      tabs++;
    }
    expect(focus.canRequestFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  }
  await _frames(t);
}

HangarReaderCopy _copy(WidgetTester t) =>
    HangarReaderCopy(t.element(find.byType(HangarPage)));
void _phase(WidgetTester t, String phase) {
  expect(
    find.descendant(
      of: _key('hangar-reader-status'),
      matching: find.text(_copy(t).status(phase)),
    ),
    findsOneWidget,
  );
}

void _wait(
  WidgetTester t,
  InteractionSuite suite,
  String input, {
  bool reduce = false,
}) {
  final region = find.byType(HangarReaderWaiting);
  expect(region, findsOneWidget);
  final waiting = t.widget<HangarReaderWaiting>(region);
  expect(waiting.source, _source(input));
  expect(waiting.height, 3);
  final native = find.descendant(
    of: region,
    matching: find.byType(LinearProgressIndicator),
  );
  final progress = find.descendant(
    of: region,
    matching: find.byType(SuiteProgressBar),
  );
  final isStatic = input != 'pointer' || reduce;
  if (suite == InteractionSuite.standard) {
    expect(progress, findsNothing);
    expect(native, findsOneWidget);
    expect(t.getSize(native).height, 3);
    expect(
      t.widget<LinearProgressIndicator>(native).value,
      isStatic ? .5 : isNull,
    );
  } else {
    expect(native, findsNothing);
    expect(progress, isStatic ? findsNothing : findsOneWidget);
  }
}

Future<_Host> _mount(
  WidgetTester t,
  InteractionSuite suite, {
  HangarProbePort? local,
  _Browser? browser,
  _Preview? preview,
}) async {
  size(t, const Size(1250, 1150));
  final account = createAccountModule(
    InMemoryAccountAdapter.forReview(AccountReviewState.signedIn),
  );
  await account.initialize();
  final host = _Host(
    suite,
    account,
    browser ?? _Browser(),
    preview ?? _Preview(),
    local,
  );
  await t.pumpWidget(host.app());
  await _frames(t);
  await _tail(t);
  expect(host.browser.opens, 0);
  expect(host.preview.begins, 0);
  return host;
}

Future<void> _close(WidgetTester t, _Host host) async {
  host.browser.release();
  host.preview.release();
  if (host.local?.pendingRead case final gate? when !gate.isCompleted) {
    gate.complete(host.local!.snapshot);
  }
  await _frames(t);
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t);
  host.account.dispose();
  expect(t.takeException(), isNull);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input actual entry/read/resume retain input phases',
        (t) => _withSemantics(t, () async {
          final browser = _Browser()..pendingOpen = Completer<void>();
          final preview = _Preview()
            ..results = [result('awaitingIdentity'), result('complete')];
          final host = await _mount(
            t,
            suite,
            browser: browser,
            preview: preview,
          );
          await _act(t, 'hangar-open-reader', input);
          _phase(t, 'opening');
          _wait(t, suite, input);
          expect(browser.opens, 1);
          expect(browser.openingSources, [_source(input)]);
          expect(preview.begins, 0);
          host.update(() {
            host.reduce = true;
            host.light = true;
          });
          await _frames(t);
          _wait(t, suite, input, reduce: true);
          host.update(() => host.reduce = false);
          await _frames(t);
          _wait(t, suite, input);
          browser.pendingOpen!.complete();
          browser.pendingOpen = null;
          await _frames(t, 6);
          _phase(t, 'ready');
          expect(browser.shown, isTrue);
          expect(find.byType(HangarReaderWaiting), findsNothing);
          expect(
            t
                .widget<HangarBrowserViewport>(
                  find.byType(HangarBrowserViewport),
                )
                .interactive,
            isTrue,
          );

          preview.pendingBegin = Completer<Map<String, Object?>>();
          await _act(t, 'hangar-reader-action', input);
          _phase(t, 'starting');
          _wait(t, suite, input);
          expect(browser.locked, isTrue);
          expect(preview.begins, 1);
          expect(preview.beginSources, [_source(input)]);
          expect(_key('hangar-reader-action'), findsNothing);
          expect(_key('hangar-reader-reopen'), findsNothing);
          expect(
            t
                .widget<HangarBrowserViewport>(
                  find.byType(HangarBrowserViewport),
                )
                .interactive,
            isFalse,
          );
          preview.pendingBegin!.complete(result('ready'));
          preview.pendingBegin = null;
          await _frames(t, 6);
          _phase(t, 'awaitingIdentity');
          expect(browser.locked, isFalse);
          expect(browser.shown, isTrue);
          expect(browser.pages, isEmpty);
          expect(preview.observations, 0);
          expect(find.text(_copy(t).resume), findsOneWidget);

          final resumed = input == 'pointer' ? 'keyboard' : 'pointer';
          browser.pendingCapture = Completer<Map<String, Object?>>();
          await _act(t, 'hangar-reader-action', resumed);
          _phase(t, 'reading');
          _wait(t, suite, resumed);
          expect(preview.begins, 2);
          expect(preview.beginSources, [_source(input), _source(resumed)]);
          expect(browser.pages, [1]);
          expect(browser.locked, isTrue);
          browser.pendingCapture!.complete({});
          browser.pendingCapture = null;
          await _frames(t, 7);
          _phase(t, 'complete');
          expect(preview.observations, 1);
          expect(browser.captureSources, [_source(resumed)]);
          expect(browser.locked, isFalse);
          expect(browser.shown, isFalse);
          expect(_key('hangar-reader-preview'), findsOneWidget);
          expect(find.text('Test Ship'), findsOneWidget);
          expect(find.byType(LocalHangarSavePanel), findsNothing);
          expect(find.text(_copy(t).notSaved), findsWidgets);
          await _act(t, 'hangar-reader-back', input);
          expect(_key('hangar-open-reader'), findsOneWidget);
          expect(browser.shown, isFalse);
          expect(browser.locked, isFalse);
          await _close(t, host);
        }),
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite $input cancel held scan then explicit reopen/back',
        (t) => _withSemantics(t, () async {
          final browser = _Browser();
          final host = await _mount(t, suite, browser: browser);
          await _act(t, 'hangar-open-reader', input);
          _phase(t, 'ready');
          await _act(t, 'hangar-reader-reopen', input);
          _phase(t, 'ready');
          expect(browser.opens, 2);
          expect(browser.profileKeys, ['A' * 64, 'A' * 64]);
          browser.pendingCapture = Completer<Map<String, Object?>>();
          await _act(t, 'hangar-reader-action', input);
          _wait(t, suite, input);
          expect(browser.locked, isTrue);
          final cancels = host.preview.cancels;
          await _act(t, 'hangar-reader-cancel', input);
          _phase(t, 'cancelled');
          expect(browser.shown, isFalse);
          expect(browser.locked, isFalse);
          expect(host.preview.cancels, greaterThan(cancels));
          expect(host.preview.observations, 0);
          expect(_key('hangar-reader-preview'), findsNothing);
          // The original Controller refuses restart until the held capture drains.
          final restart = _key('hangar-reader-action');
          expect(restart, findsOneWidget);
          expect(
            t
                .getSemantics(restart)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse,
          );
          browser.pendingCapture!.complete({});
          browser.pendingCapture = null;
          await _frames(t, 6);
          _phase(t, 'cancelled');
          expect(host.preview.observations, 0);
          await _act(t, 'hangar-reader-action', input);
          _phase(t, 'ready');
          expect(browser.opens, 3);
          expect(browser.shown, isTrue);
          await _act(t, 'hangar-reader-back', input);
          expect(_key('hangar-open-reader'), findsOneWidget);
          expect(browser.shown, isFalse);
          expect(browser.locked, isFalse);
          expect(find.byType(HangarReaderWaiting), findsNothing);
          await _close(t, host);
        }),
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite $input completed read lends save-panel initial source',
        (t) => _withSemantics(t, () async {
          final local = HangarProbePort();
          final preview = _Preview()
            ..results = [
              {...result('complete'), 'canSave': true},
            ];
          final host = await _mount(t, suite, local: local, preview: preview);
          expect(local.reads, 1);
          await _act(t, 'local-hangar-read', 'pointer');
          _phase(t, 'ready');
          local.pendingRead = Completer<LocalHangarSnapshot>();
          await _act(t, 'hangar-reader-action', input);
          await _frames(t, 5);
          _phase(t, 'complete');
          expect(find.byType(LocalHangarSavePanel), findsOneWidget);
          final panel = t.widget<LocalHangarSavePanel>(
            find.byType(LocalHangarSavePanel),
          );
          expect(panel.port, same(local));
          expect(panel.initialSource, _source(input));
          expect(local.reads, 2);
          expect(local.saves, 0);
          final wait = find.descendant(
            of: find.byType(LocalHangarSavePanel),
            matching: find.byType(HangarReaderWaiting),
          );
          expect(wait, findsOneWidget);
          expect(t.widget<HangarReaderWaiting>(wait).source, _source(input));
          expect(t.widget<HangarReaderWaiting>(wait).height, 4);
          final progress = find.descendant(
            of: wait,
            matching: find.byType(SuiteProgressBar),
          );
          if (suite == InteractionSuite.standard) {
            final native = find.descendant(
              of: wait,
              matching: find.byType(LinearProgressIndicator),
            );
            expect(native, findsOneWidget);
            expect(
              t.widget<LinearProgressIndicator>(native).value,
              input == 'pointer' ? isNull : .5,
            );
            expect(progress, findsNothing);
          } else {
            expect(
              progress,
              input == 'pointer' ? findsOneWidget : findsNothing,
            );
          }
          expect(host.browser.locked, isFalse);
          final cancels = preview.cancels;
          await _act(t, 'hangar-reader-back', input);
          expect(find.byType(LocalHangarSavePanel), findsNothing);
          expect(preview.cancels, greaterThan(cancels));
          local.pendingRead!.complete(local.snapshot);
          local.pendingRead = null;
          await _frames(t, 6);
          expect(local.saves, 0);
          expect(_key('local-hangar-read'), findsOneWidget);
          await _close(t, host);
        }),
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite actual keyboard save returns to a static initial read',
      (t) async {
        final local = _CompletionPort();
        final original = local.snapshot;
        final preview = _Preview()
          ..results = [
            {...result('complete'), 'canSave': true},
          ];
        final host = await _mount(t, suite, local: local, preview: preview);
        final pageState = t.state(find.byType(HangarPage));
        expect(local.reads, 1);
        await _act(t, 'local-hangar-read', 'pointer');
        _phase(t, 'ready');
        await _act(t, 'hangar-reader-action', 'pointer');
        await _frames(t, 5);
        _phase(t, 'complete');
        expect(local.reads, 2);
        expect(local.saves, 0);
        expect(
          t
              .widget<LocalHangarSavePanel>(find.byType(LocalHangarSavePanel))
              .port,
          same(local),
        );

        // The keyed checkbox is decorative/IgnorePointer. Hit the actual
        // accessible row, not the original raw Checkbox hidden inside it.
        final confirmation = find.ancestor(
          of: _key('local-hangar-confirm'),
          matching: find.byType(StarBridgeCheckboxTile),
        );
        expect(confirmation, findsOneWidget);
        expect(t.widget<StarBridgeCheckboxTile>(confirmation).value, isFalse);
        await t.ensureVisible(confirmation);
        await t.tap(confirmation);
        await _frames(t);
        expect(t.widget<StarBridgeCheckboxTile>(confirmation).value, isTrue);
        await _act(t, 'local-hangar-save', 'keyboard');
        expect(local.commands, [
          (
            'synthetic-operation',
            original.revision,
            false,
            InteractionSource.keyboard,
          ),
        ]);
        expect(local.saves, 1);
        expect(local.reads, 2);
        expect(local.receipt.isCompleted, isFalse);
        expect(local.snapshot, same(original));
        expect(find.byType(LocalHangarSavePanel), findsOneWidget);
        expect(_key('local-hangar-save'), findsNothing);
        expect(find.byType(LocalHangarPage), findsNothing);
        await _tail(t);
        expect(local.saves, 1);
        expect(local.reads, 2);

        final committed = LocalHangarSnapshot(
          revision: original.revision + 1,
          operationId: 'synthetic-operation',
          ships: const [LocalHangarShip(id: 'read-ship', title: 'Test Ship')],
        );
        local.pendingRead = Completer<LocalHangarSnapshot>();
        local.receipt.complete(committed);
        await _frames(t, 7);
        expect(t.state(find.byType(HangarPage)), same(pageState));
        expect(find.byType(LocalHangarSavePanel), findsNothing);
        expect(
          t.widget<LocalHangarPage>(find.byType(LocalHangarPage)).port,
          same(local),
        );
        expect(local.reads, 3);
        expect(local.saves, 1);
        expect(local.snapshot, same(committed));
        expect(host.browser.locked, isFalse);
        expect(host.browser.shown, isFalse);
        final status = find.byType(LocalHangarReadStatus);
        expect(t.widget<LocalHangarReadStatus>(status).loading, isTrue);
        expect(t.widget<LocalHangarReadStatus>(status).snapshot, isNull);
        final waits = find.descendant(
          of: status,
          matching: find.byType(HelpSupportWaiting),
        );
        if (suite == InteractionSuite.standard) {
          expect(waits, findsNothing);
          expect(
            find.descendant(
              of: status,
              matching: find.byType(LinearProgressIndicator),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: status,
              matching: find.byWidgetPredicate(
                (w) => w is SizedBox && w.height == 4,
              ),
            ),
            findsOneWidget,
          );
        } else {
          expect(waits, findsOneWidget);
          expect(
            t.widget<HelpSupportWaiting>(waits).source,
            InteractionSource.keyboard,
          );
          expect(
            find.descendant(of: waits, matching: find.byType(SuiteProgressBar)),
            findsNothing,
          );
        }
        await _tail(t);
        expect(local.reads, 3);
        expect(local.saves, 1);
        local.pendingRead!.complete(committed);
        local.pendingRead = null;
        await _frames(t, 5);
        await _tail(t);
        expect(t.widget<LocalHangarReadStatus>(status).loading, isFalse);
        expect(
          t.widget<LocalHangarReadStatus>(status).snapshot,
          same(committed),
        );
        expect(local.reads, 3);
        expect(local.saves, 1);
        expect(local.commands.length, 1);
        expect(t.state(find.byType(HangarPage)), same(pageState));
        await _close(t, host);
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets('$suite failed open explicit keyboard retry is static', (
      t,
    ) async {
      final browser = _Browser()..failOpen = true;
      final host = await _mount(t, suite, browser: browser);
      await _act(t, 'hangar-open-reader', 'pointer');
      _phase(t, 'runtime');
      expect(browser.shown, isFalse);
      expect(host.preview.begins, 0);
      browser.failOpen = false;
      browser.pendingOpen = Completer<void>();
      await _act(t, 'hangar-reader-action', 'keyboard');
      _phase(t, 'opening');
      _wait(t, suite, 'keyboard');
      expect(browser.opens, 2);
      expect(browser.openingSources, [
        InteractionSource.pointer,
        InteractionSource.keyboard,
      ]);
      browser.pendingOpen!.complete();
      browser.pendingOpen = null;
      await _frames(t, 6);
      _phase(t, 'ready');
      expect(browser.shown, isTrue);
      expect(browser.locked, isFalse);
      await _close(t, host);
    }, timeout: const Timeout(Duration(seconds: 45)));
  }

  for (final departure in ['cancel', 'account', 'leave']) {
    testWidgets(
      'scan $departure rejects late capture without local-save read',
      (t) async {
        final local = HangarProbePort();
        final browser = _Browser()
          ..pendingCapture = Completer<Map<String, Object?>>();
        final preview = _Preview()
          ..results = [
            {...result('complete'), 'canSave': true},
          ];
        final host = await _mount(
          t,
          InteractionSuite.scan,
          local: local,
          browser: browser,
          preview: preview,
        );
        await _act(t, 'local-hangar-read', 'pointer');
        await _act(t, 'hangar-reader-action', 'keyboard');
        _phase(t, 'reading');
        expect(browser.locked, isTrue);
        expect(local.reads, 1);
        if (departure == 'cancel') {
          await _act(t, 'hangar-reader-cancel', 'pointer');
          _phase(t, 'cancelled');
        } else if (departure == 'account') {
          await host.account.logout();
          await _frames(t, 5);
          _phase(t, 'accountChanged');
        } else {
          host.update(() => host.visible = false);
          await _frames(t, 5);
          expect(find.byType(HangarPage), findsNothing);
        }
        expect(browser.shown, isFalse);
        expect(browser.locked, isFalse);
        browser.pendingCapture!.complete({});
        browser.pendingCapture = null;
        await _frames(t, 7);
        expect(preview.observations, 0);
        expect(local.reads, 1);
        expect(local.saves, 0);
        expect(find.byType(LocalHangarSavePanel), findsNothing);
        expect(_key('hangar-reader-preview'), findsNothing);
        expect(browser.shown, isFalse);
        expect(browser.locked, isFalse);
        await _close(t, host);
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
