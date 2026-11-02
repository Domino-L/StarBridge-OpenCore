import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_icon_action.dart';
import 'package:starbridge_flutter/features/account/account_models.dart';
import 'package:starbridge_flutter/features/hangar/cached_local_hangar.dart';
import 'package:starbridge_flutter/features/hangar/hangar_display_session.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_copy.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_page.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_scope.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_read_status.dart';
import 'package:starbridge_flutter/features/settings/help_support_waiting.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import '../../features/hangar/hangar_display_session_test.dart' show projection;
import 'interaction_batch3fb_hangar_test.dart'
    show HangarProbePort, hangarInventory;
import 'interaction_batch3i_test.dart' show scopedApp;

const _pageKey = Key('wait-real-hangar');
InteractionSource _origin(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

class _Port extends HangarProbePort implements LocalHangarReadScopeSource {
  final readOrigins = <InteractionSource>[];
  final favoriteOrigins = <InteractionSource>[];
  @override
  LocalHangarReadScope? readScope;
  @override
  Future<LocalHangarSnapshot> read() {
    readOrigins.add(currentStarBridgeActivationSource);
    return super.read();
  }

  @override
  Future<LocalHangarSnapshot> setFavorite(String id, bool value, int revision) {
    favoriteOrigins.add(currentStarBridgeActivationSource);
    return super.setFavorite(id, value, revision);
  }

  void release() {
    if (pendingRead case final gate? when !gate.isCompleted) {
      gate.complete(snapshot);
    }
    if (pendingFavorite case final gate? when !gate.isCompleted) {
      gate.complete(snapshot);
    }
  }
}

class _Probe {
  _Probe(this.suite, this.port, {this.opening});
  InteractionSuite suite;
  LocalHangarPort port;
  InteractionSource? opening;
  bool reduce = false, light = false, visible = true;
  int scanOpens = 0;
  late StateSetter update;
  Widget app() => StatefulBuilder(
    builder: (_, setState) {
      update = setState;
      return scopedApp(
        Builder(
          builder: (context) {
            if (!visible) {
              return const Text('Hangar left');
            }
            final page = LocalHangarPage(
              key: _pageKey,
              port: port,
              onRead: () => scanOpens++,
            );
            return opening == null
                ? page
                : starBridgeInitialReadViewport(
                    context,
                    source: opening!,
                    child: page,
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

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> _tail(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Finder _key(String value) => find.byKey(Key(value));
Finder _statusFinder() => find.byType(LocalHangarReadStatus);
LocalHangarReadStatus _status(WidgetTester t) =>
    t.widget<LocalHangarReadStatus>(_statusFinder());
bool _enabled(WidgetTester t, String value) {
  final target = _key(value);
  expect(target, findsOneWidget);
  final buttons = find.ancestor(
    of: target,
    matching: find.byType(StarBridgeActionButton),
  );
  if (buttons.evaluate().isNotEmpty) {
    return t.widget<StarBridgeActionButton>(buttons.first).onActivate != null;
  }
  final icon = find.ancestor(
    of: target,
    matching: find.byType(StarBridgeIconAction),
  );
  expect(icon, findsOneWidget);
  return t.widget<StarBridgeIconAction>(icon).onActivate != null;
}

/// Real pointer/Tab-Enter/exposed semantics action. Never invoke an owner
/// refresh/favorite callback to manufacture input provenance.
Future<void> _act(WidgetTester t, String value, String input) async {
  final target = _key(value);
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _tail(t);
  if (input == 'keyboard') {
    final widget = t.widget(target);
    final focus = switch (widget) {
      IconButton b => b.focusNode!,
      ButtonStyleButton b => b.focusNode!,
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
      _ => throw StateError('Unsupported actual target $widget'),
    };
    var tabs = 0;
    while (!focus.hasPrimaryFocus && tabs < 100) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(t);
      tabs++;
    }
    expect(focus.canRequestFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else if (input == 'reader') {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  } else {
    await t.tap(target);
  }
  await _frames(t);
}

void _waiting(
  WidgetTester t,
  InteractionSuite suite, {
  required bool favorite,
  required InteractionSource source,
  bool reduce = false,
  bool openingKeyboard = false,
}) {
  final status = _status(t);
  expect(favorite ? status.favoriteBusy : status.loading, isTrue);
  expect(favorite ? status.favoriteSource : status.readSource, source);
  final effective = openingKeyboard ? InteractionSource.keyboard : source;
  final isStatic = effective == InteractionSource.keyboard || reduce;
  final region = _statusFinder();
  final native = find.descendant(
    of: region,
    matching: find.byType(LinearProgressIndicator),
  );
  final waits = find.descendant(
    of: region,
    matching: find.byType(HelpSupportWaiting),
  );
  final progress = find.descendant(
    of: region,
    matching: find.byType(SuiteProgressBar),
  );
  if (suite == InteractionSuite.standard) {
    expect(waits, findsNothing);
    expect(progress, findsNothing);
    if (isStatic) {
      expect(native, findsNothing);
      expect(
        find.descendant(
          of: region,
          matching: find.byWidgetPredicate(
            (w) => w is SizedBox && w.height == 4,
          ),
        ),
        findsOneWidget,
      );
    } else {
      expect(native, findsOneWidget);
      expect(t.getSize(native).height, 4);
      expect(t.widget<LinearProgressIndicator>(native).value, isNull);
    }
  } else {
    expect(native, findsNothing);
    expect(waits, findsOneWidget);
    final wait = t.widget<HelpSupportWaiting>(waits);
    expect(wait.source, effective);
    expect(wait.label, isNotEmpty);
    expect(
      find.descendant(of: waits, matching: find.text(wait.label)),
      findsOneWidget,
    );
    expect(progress, isStatic ? findsNothing : findsOneWidget);
  }
}

Future<_Probe> _mount(
  WidgetTester t,
  InteractionSuite suite,
  LocalHangarPort port, {
  InteractionSource? opening,
}) async {
  size(t, const Size(1120, 1200));
  final p = _Probe(suite, port, opening: opening);
  await t.pumpWidget(p.app());
  await _frames(t);
  await _tail(t);
  expect(t.widget<LocalHangarPage>(find.byKey(_pageKey)).port, same(port));
  return p;
}

Future<void> _close(WidgetTester t, Iterable<_Port> ports) async {
  for (final port in ports) {
    port.release();
  }
  await _frames(t);
  await t.pumpWidget(const SizedBox.shrink());
  await _frames(t);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input refresh failure and actual retry retain rows and independent wait phases',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = _Port();
          try {
            final p = await _mount(t, suite, port);
            final before = _status(t).snapshot!;
            expect(port.reads, 1);
            port.pendingRead = Completer<LocalHangarSnapshot>();
            await _act(t, 'local-hangar-refresh', input);
            expect(port.reads, 2);
            expect(port.readOrigins.last, _origin(input));
            expect(_status(t).snapshot, same(before));
            _waiting(t, suite, favorite: false, source: _origin(input));
            expect(_key('local-hangar-ship-alpha'), findsOneWidget);
            expect(_enabled(t, 'local-hangar-refresh'), isFalse);
            expect(_enabled(t, 'local-hangar-read'), isTrue);
            // Physical presses at an intentionally disabled target, not a fake
            // semantics activation or a call to its null command.
            final position = t.getCenter(_key('local-hangar-refresh'));
            await t.tapAt(position);
            await t.tapAt(position);
            await _frames(t);
            expect(port.reads, 2);
            expect(p.scanOpens, 0);
            p.update(() {
              p.reduce = true;
              p.light = true;
            });
            await _frames(t);
            _waiting(
              t,
              suite,
              favorite: false,
              source: _origin(input),
              reduce: true,
            );
            p.update(() => p.reduce = false);
            await _frames(t);
            _waiting(t, suite, favorite: false, source: _origin(input));
            final otherSuite = suite == InteractionSuite.standard
                ? InteractionSuite.scan
                : InteractionSuite.standard;
            p.update(() => p.suite = otherSuite);
            await _frames(t);
            _waiting(t, otherSuite, favorite: false, source: _origin(input));
            p.update(() => p.suite = suite);
            await _frames(t);
            _waiting(t, suite, favorite: false, source: _origin(input));
            expect(_status(t).snapshot, same(before));
            expect(port.reads, 2);
            port.pendingRead!.completeError(
              const LocalHangarFailure('hangar.read_unavailable'),
            );
            await _frames(t);
            await _tail(t);
            expect(_status(t).loading, isFalse);
            expect(_status(t).failed, isTrue);
            expect(_status(t).snapshot, same(before));
            expect(
              find.text(
                LocalHangarCopy(t.element(_statusFinder())).readFailure,
              ),
              findsOneWidget,
            );
            expect(_enabled(t, 'local-hangar-retry'), isTrue);
            final retry = input == 'pointer' ? 'keyboard' : 'pointer';
            port.pendingRead = Completer<LocalHangarSnapshot>();
            await _act(t, 'local-hangar-retry', retry);
            expect(port.reads, 3);
            expect(port.readOrigins.last, _origin(retry));
            _waiting(t, suite, favorite: false, source: _origin(retry));
            expect(_status(t).snapshot, same(before));
            final next = hangarInventory(revision: 2);
            port.snapshot = next;
            port.pendingRead!.complete(next);
            await _frames(t);
            await _tail(t);
            expect(_status(t).snapshot, same(next));
            expect(_status(t).failed, isFalse);
            port.pendingRead = Completer<LocalHangarSnapshot>();
            await _act(t, 'local-hangar-refresh', 'pointer');
            expect(port.reads, 4);
            _waiting(
              t,
              suite,
              favorite: false,
              source: InteractionSource.pointer,
            );
            port.pendingRead!.complete(next);
            await _frames(t);
            expect(port.saves, 0);
            expect(port.favorites, isEmpty);
            expect(p.scanOpens, 0);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, [port]);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite $input favorite holds confirmed bookmark then retries with current source',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = _Port();
          try {
            final p = await _mount(t, suite, port);
            final before = _status(t).snapshot!;
            port.pendingFavorite = Completer<LocalHangarSnapshot>();
            await _act(t, 'hangar-favorite-alpha', input);
            expect(port.favorites, [('alpha', true, 1)]);
            expect(port.favoriteOrigins, [_origin(input)]);
            _waiting(t, suite, favorite: true, source: _origin(input));
            expect(_status(t).snapshot, same(before));
            expect(_status(t).snapshot!.ships.first.isFavorite, isFalse);
            for (final id in [
              'hangar-favorite-alpha',
              'local-hangar-refresh',
              'local-hangar-read',
            ]) {
              expect(_enabled(t, id), isFalse);
            }
            expect(
              t
                  .getSemantics(_key('hangar-favorite-alpha'))
                  .getSemanticsData()
                  .hasAction(SemanticsAction.tap),
              isFalse,
            );
            final position = t.getCenter(_key('local-hangar-refresh'));
            await t.tapAt(position);
            await t.tapAt(position);
            await _frames(t);
            expect(port.favorites, hasLength(1));
            expect(port.reads, 1);
            expect(p.scanOpens, 0);
            p.update(() => p.reduce = true);
            await _frames(t);
            _waiting(
              t,
              suite,
              favorite: true,
              source: _origin(input),
              reduce: true,
            );
            p.update(() => p.reduce = false);
            await _frames(t);
            _waiting(t, suite, favorite: true, source: _origin(input));
            port.pendingFavorite!.completeError(
              const LocalHangarFailure('hangar.save_failed'),
            );
            await _frames(t);
            await _tail(t);
            expect(_status(t).favoriteBusy, isFalse);
            expect(_status(t).favoriteFailed, isTrue);
            expect(_status(t).snapshot, same(before));
            expect(
              find.text(
                LocalHangarCopy(t.element(_statusFinder())).favoriteFailure,
              ),
              findsOneWidget,
            );
            expect(_enabled(t, 'hangar-favorite-alpha'), isTrue);
            final retry = input == 'pointer' ? 'keyboard' : 'pointer';
            port.pendingFavorite = Completer<LocalHangarSnapshot>();
            await _act(t, 'hangar-favorite-alpha', retry);
            expect(port.favorites, [('alpha', true, 1), ('alpha', true, 1)]);
            expect(port.favoriteOrigins, [_origin(input), _origin(retry)]);
            _waiting(t, suite, favorite: true, source: _origin(retry));
            expect(_status(t).snapshot, same(before));
            final receipt = hangarInventory(revision: 2, favorite: true);
            port.snapshot = receipt;
            port.pendingFavorite!.complete(receipt);
            await _frames(t);
            await _tail(t);
            expect(_status(t).snapshot, same(receipt));
            expect(_status(t).snapshot!.ships.first.isFavorite, isTrue);
            expect(_status(t).favoriteBusy, isFalse);
            expect(_status(t).favoriteFailed, isFalse);
            expect(port.reads, 1);
            expect(port.saves, 0);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, [port]);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );

      testWidgets(
        '$suite $input actual empty-result clear restores query and original inventory without IO',
        (t) async {
          final semantics = t.ensureSemantics();
          final port = _Port();
          try {
            await _mount(t, suite, port);
            final before = _status(t).snapshot;
            final search = _key('local-hangar-search');
            final controller = t.widget<TextField>(search).controller!;
            await t.enterText(search, 'synthetic-no-match-xyz');
            await _frames(t);
            expect(controller.text, 'synthetic-no-match-xyz');
            expect(_key('local-hangar-ship-alpha'), findsNothing);
            expect(_key('hangar-clear-filters'), findsOneWidget);
            await _act(t, 'hangar-clear-filters', input);
            await _tail(t);
            expect(t.widget<TextField>(search).controller, same(controller));
            expect(controller.text, isEmpty);
            for (final id in ['alpha', 'beta', 'gamma']) {
              expect(
                find.byKey(ValueKey('local-hangar-ship-$id')),
                findsOneWidget,
              );
            }
            expect(_status(t).snapshot, same(before));
            expect(port.reads, 1);
            expect(port.saves, 0);
            expect(port.favorites, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, [port]);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    for (final opening in ['viewport', 'route']) {
      testWidgets(
        '$suite keyboard $opening initial held read is locally static',
        (t) async {
          size(t, const Size(1120, 1200));
          final semantics = t.ensureSemantics();
          final port = _Port()..pendingRead = Completer<LocalHangarSnapshot>();
          var opened = false;
          var initialSource = InteractionSource.programmatic;
          late StateSetter update;
          try {
            await t.pumpWidget(
              StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return scopedApp(
                    Builder(
                      builder: (context) {
                        Widget page() => LocalHangarPage(
                          key: _pageKey,
                          port: port,
                          onRead: () {},
                        );
                        if (opened) {
                          return starBridgeInitialReadViewport(
                            context,
                            source: initialSource,
                            child: page(),
                          );
                        }
                        return StarBridgeActionButton(
                          controlKey: const Key('wait-open-hangar'),
                          onActivate: (source) {
                            if (opening == 'route') {
                              unawaited(
                                showStarBridgeDialog<void>(
                                  context,
                                  source: source,
                                  builder: (_) => Dialog(
                                    child: SizedBox(
                                      width: 1000,
                                      height: 1000,
                                      child: page(),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              update(() {
                                initialSource = source;
                                opened = true;
                              });
                            }
                          },
                          child: const Text('Open actual hangar'),
                        );
                      },
                    ),
                    suite,
                  );
                },
              ),
            );
            await _frames(t);
            await _act(t, 'wait-open-hangar', 'keyboard');
            expect(port.reads, 1);
            expect(_status(t).snapshot, isNull);
            _waiting(
              t,
              suite,
              favorite: false,
              source: InteractionSource.programmatic,
              openingKeyboard: true,
            );
            final receipt = hangarInventory();
            port.pendingRead!.complete(receipt);
            await _frames(t);
            await _tail(t);
            expect(_status(t).snapshot, same(receipt));
            expect(_status(t).loading, isFalse);
            expect(port.reads, 1);
            expect(port.saves, 0);
            expect(port.favorites, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await _close(t, [port]);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite actual CachedLocalHangar keeps confirmed rows during failed explicit refresh',
      (t) async {
        final semantics = t.ensureSemantics();
        final port = _Port();
        final cached = CachedLocalHangar(port, isCurrent: () => true);
        try {
          final receipt = await cached.read();
          await _mount(t, suite, cached);
          expect(port.reads, 1);
          expect(_status(t).snapshot, same(receipt));
          expect(_status(t).loading, isFalse);
          port.pendingRead = Completer<LocalHangarSnapshot>();
          await _act(t, 'local-hangar-refresh', 'keyboard');
          expect(port.reads, 2);
          _waiting(
            t,
            suite,
            favorite: false,
            source: InteractionSource.keyboard,
          );
          expect(_status(t).snapshot, same(receipt));
          expect(cached.snapshot, same(receipt));
          expect(_key('local-hangar-ship-alpha'), findsOneWidget);
          port.pendingRead!.completeError(
            const LocalHangarFailure(
              'hangar.read_unavailable',
              retryable: true,
            ),
          );
          await _frames(t);
          await _tail(t);
          expect(_status(t).failed, isTrue);
          expect(_status(t).snapshot, same(receipt));
          expect(cached.snapshot, same(receipt));
          expect(port.saves, 0);
          expect(port.favorites, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await _close(t, [port]);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }

  for (final operation in ['read', 'favorite']) {
    for (final retirement in ['leave', 'replacement']) {
      for (final failed in [false, true]) {
        testWidgets(
          'Scan $operation $retirement ignores late failed=$failed receipt',
          (t) async {
            final semantics = t.ensureSemantics();
            final original = _Port();
            final next = _Port()
              ..snapshot = const LocalHangarSnapshot(
                revision: 99,
                ships: [
                  LocalHangarShip(id: 'replacement', title: 'Replacement'),
                ],
              );
            try {
              final p = await _mount(t, InteractionSuite.scan, original);
              late Completer<LocalHangarSnapshot> held;
              if (operation == 'read') {
                held = original.pendingRead = Completer<LocalHangarSnapshot>();
                await _act(t, 'local-hangar-refresh', 'keyboard');
              } else {
                held = original.pendingFavorite =
                    Completer<LocalHangarSnapshot>();
                await _act(t, 'hangar-favorite-alpha', 'keyboard');
              }
              p.update(() {
                if (retirement == 'leave') {
                  p.visible = false;
                } else {
                  p.port = next;
                }
              });
              await _frames(t);
              await _tail(t);
              if (failed) {
                held.completeError(
                  const LocalHangarFailure('hangar.read_unavailable'),
                );
              } else {
                held.complete(hangarInventory(revision: 777, favorite: true));
              }
              await _frames(t);
              await _tail(t);
              if (retirement == 'leave') {
                expect(find.text('Hangar left'), findsOneWidget);
                expect(_statusFinder(), findsNothing);
              } else {
                expect(
                  t.widget<LocalHangarPage>(find.byKey(_pageKey)).port,
                  same(next),
                );
                expect(_status(t).snapshot, same(next.snapshot));
                expect(_status(t).snapshot!.revision, 99);
                expect(_status(t).loading, isFalse);
                expect(_status(t).failed, isFalse);
                expect(_status(t).favoriteBusy, isFalse);
                expect(_status(t).favoriteFailed, isFalse);
                expect(_key('local-hangar-ship-replacement'), findsOneWidget);
                expect(_key('local-hangar-ship-alpha'), findsNothing);
                expect(next.reads, 1);
              }
              expect(original.reads, operation == 'read' ? 2 : 1);
              if (operation == 'favorite') {
                expect(original.favorites, [('alpha', true, 1)]);
              } else {
                expect(original.favorites, isEmpty);
              }
              expect(next.favorites, isEmpty);
              expect(original.saves + next.saves, 0);
              expect(t.takeException(), isNull);
            } finally {
              await _close(t, [original, next]);
              semantics.dispose();
            }
          },
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
    }
  }

  testWidgets(
    'Scan initial failure remains unknown until actual reader retry succeeds',
    (t) async {
      final semantics = t.ensureSemantics();
      final port = _Port()..pendingRead = Completer<LocalHangarSnapshot>();
      try {
        await _mount(t, InteractionSuite.scan, port);
        expect(_status(t).snapshot, isNull);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.programmatic,
        );
        port.pendingRead!.completeError(
          const LocalHangarFailure('hangar.read_unavailable'),
        );
        await _frames(t);
        await _tail(t);
        expect(_status(t).snapshot, isNull);
        expect(_status(t).failed, isTrue);
        port.pendingRead = Completer<LocalHangarSnapshot>();
        await _act(t, 'local-hangar-retry', 'reader');
        expect(port.reads, 2);
        expect(_status(t).snapshot, isNull);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.keyboard,
        );
        final receipt = hangarInventory();
        port.pendingRead!.complete(receipt);
        await _frames(t);
        expect(_status(t).snapshot, same(receipt));
        expect(_status(t).failed, isFalse);
        expect(port.saves, 0);
        expect(t.takeException(), isNull);
      } finally {
        await _close(t, [port]);
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Scan real display passive fresh read ignores earlier keyboard opening and refresh source',
    (t) async {
      const id = '0123456789abcdef0123456789abcdef';
      const route = AccountRoute(
        environment: 'integration',
        authority: 'synthetic',
        subject: 'owner',
      );
      const proof = AccountDisplayHandoff(
        displayKey: id,
        sourceGeneration: 0,
        route: route,
      );
      final semantics = t.ensureSemantics();
      final account = ValueNotifier(projection(id: id));
      final retained = _Port()..pendingRead = Completer<LocalHangarSnapshot>();
      final fresh = _Port()..pendingRead = Completer<LocalHangarSnapshot>();
      final display = HangarDisplaySession(
        account: account,
        retainedFactory: (_) => retained,
        localFactory: () => fresh,
      );
      try {
        final p = await _mount(
          t,
          InteractionSuite.scan,
          display,
          opening: InteractionSource.keyboard,
        );
        expect(retained.reads, 1);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.programmatic,
          openingKeyboard: true,
        );
        retained.pendingRead!.complete(hangarInventory(revision: 7));
        await _frames(t);
        await _tail(t);
        retained.pendingRead = Completer<LocalHangarSnapshot>();
        await _act(t, 'local-hangar-refresh', 'pointer');
        expect(retained.reads, 2);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.pointer,
        );
        retained.pendingRead!.complete(hangarInventory(revision: 8));
        await _frames(t);
        await _tail(t);
        retained.pendingRead = Completer<LocalHangarSnapshot>();
        await _act(t, 'local-hangar-refresh', 'keyboard');
        expect(retained.reads, 3);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.keyboard,
        );
        retained.pendingRead!.complete(hangarInventory(revision: 9));
        await _frames(t);
        await _tail(t);
        expect(_status(t).loading, isFalse);

        // The real account/display lifecycle autonomously starts the next read.
        // No direct read/favorite callback manufactures a passive UI operation.
        account.value = projection(proof: proof);
        account.value = projection(generation: 1, proof: proof);
        account.value = projection(generation: 1, signedIn: true, proof: proof);
        await _frames(t);
        expect(fresh.reads, 1);
        expect(display.refreshing, isTrue);
        expect(display.snapshot!.revision, 9);
        _waiting(
          t,
          InteractionSuite.scan,
          favorite: false,
          source: InteractionSource.programmatic,
        );
        p.update(() => p.suite = InteractionSuite.standard);
        await _frames(t);
        _waiting(
          t,
          InteractionSuite.standard,
          favorite: false,
          source: InteractionSource.programmatic,
        );
        p.update(() => p.suite = InteractionSuite.glow);
        await _frames(t);
        _waiting(
          t,
          InteractionSuite.glow,
          favorite: false,
          source: InteractionSource.programmatic,
        );
        fresh.readScope = const LocalHangarReadScope(
          generation: 1,
          route: route,
        );
        fresh.pendingRead!.complete(hangarInventory(revision: 1));
        await _frames(t);
        await _tail(t);
        expect(display.confirmed, isTrue);
        expect(display.refreshing, isFalse);
        expect(_status(t).snapshot!.revision, 1);
        expect(_status(t).loading, isFalse);
        expect(retained.reads, 3);
        expect(fresh.reads, 1);
        expect(retained.saves + fresh.saves, 0);
        expect(retained.favorites, isEmpty);
        expect(fresh.favorites, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await _close(t, [retained, fresh]);
        display.dispose();
        account.dispose();
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
