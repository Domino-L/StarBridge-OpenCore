import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/app/routing/exit_application_intent.dart';
import 'package:starbridge_flutter/platform/bridge/bridge_client_session.dart';
import 'package:starbridge_flutter/features/settings/data_location_dialog.dart';
import 'package:starbridge_flutter/features/settings/data_location_port.dart';

import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3bg_test.dart' show activate;

class LocationPort implements DataLocationMigrationPort {
  DataLocation location = const DataLocation(
    path: 'C:/synthetic/StarBridge/data',
    exists: true,
  );
  DataLocationMigrationChoice? choice = const DataLocationMigrationChoice(
    ticket: 'synthetic-ticket',
    source: 'C:/synthetic/StarBridge/data',
    destination: 'D:/synthetic/StarBridge/data',
  );
  Completer<DataLocation>? reading;
  Completer<void>? opening;
  Completer<DataLocationMigrationChoice?>? choosing;
  bool failRead = false, failOpen = false, failChoose = false, available = true;
  int reads = 0, opens = 0, choices = 0;
  final tickets = <String>[];
  Object? confirmationError;
  @override
  bool get migrationAvailable => available;
  @override
  Future<DataLocation> read() async {
    reads++;
    if (failRead) throw StateError('synthetic private detail');
    return reading?.future ?? location;
  }

  @override
  Future<void> open() async {
    opens++;
    if (failOpen) throw StateError('synthetic private detail');
    await opening?.future;
  }

  @override
  Future<DataLocationMigrationChoice?> chooseMigration() async {
    choices++;
    if (failChoose) throw StateError('synthetic private detail');
    return choosing?.future ?? choice;
  }

  @override
  Future<void> confirmMigration(String ticket) async {
    tickets.add(ticket);
    if (confirmationError case final error?) throw error;
  }
}

Widget factory(
  LocationPort port,
  InteractionSuite suite,
  void Function(ExitApplicationIntent) onExit, {
  bool reduce = false,
  bool light = false,
}) => scopedApp(
  Actions(
    actions: {
      ExitApplicationIntent: CallbackAction<ExitApplicationIntent>(
        onInvoke: (intent) {
          onExit(intent);
          return null;
        },
      ),
    },
    child: Builder(
      builder: (context) => StarBridgeActionButton(
        controlKey: const Key('open-location'),
        onActivate: (source) =>
            unawaited(showDataLocationDialog(context, port, source: source)),
        child: const Text('open'),
      ),
    ),
  ),
  suite,
  reduce: reduce,
  light: light,
);

Future<void> action(WidgetTester t, String source, String id) async {
  // The localized factory home needs its first delegate/rebuild frame before
  // locating a target. This is not waiting for a held domain operation.
  await t.pump();
  await t.ensureVisible(find.byKey(Key(id)));
  await t.pump();
  await activate(t, source, Key(id));
}

Future<void> shut(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Future<void> panel(
  WidgetTester t,
  LocationPort port,
  InteractionSuite suite,
) async {
  await t.pumpWidget(
    scopedApp(DataLocationDialog(port: port, exitAvailable: true), suite),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final suite in InteractionSuite.values) {
    testWidgets('$suite storage location uses approved action feedback', (
      t,
    ) async {
      final port = LocationPort();
      try {
        await panel(t, port, suite);
        expect(find.byType(StarBridgeActionButton), findsNWidgets(4));
      } finally {
        await t.pumpWidget(const SizedBox());
      }
    });
    testWidgets(
      '$suite replacing a storage port retires its old migration confirmation',
      (t) async {
        final old = LocationPort(), next = LocationPort();
        try {
          await panel(t, old, suite);
          await t.tap(find.byKey(const Key('data-location-move')));
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('data-location-confirm-dialog')),
            findsOneWidget,
          );
          await t.pumpWidget(
            scopedApp(
              DataLocationDialog(port: next, exitAvailable: true),
              suite,
            ),
          );
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('data-location-confirm-dialog')),
            findsNothing,
          );
          expect(old.tickets, isEmpty);
          expect(next.tickets, isEmpty);
        } finally {
          await t.pumpWidget(const SizedBox());
        }
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $source initial read is source-aware without fake location',
        (t) async {
          final p = LocationPort()..reading = Completer<DataLocation>();
          final semantics = t.ensureSemantics();
          try {
            await t.pumpWidget(factory(p, suite, (_) {}));
            await action(t, source, 'open-location');
            final route = ModalRoute.of(
              t.element(find.byType(DataLocationDialog)),
            ) as StarBridgeDialogRoute;
            expect(route.instant, source != 'pointer');
            expect(find.byKey(const Key('data-location-path')), findsNothing);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            p.reading!.complete(p.location);
            await t.pump();
            await t.pumpAndSettle();
            expect(find.text(p.location.path), findsOneWidget);
          } finally {
            await shut(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source open waits, disables duplicates and reports failure safely',
        (t) async {
          final p = LocationPort()..opening = Completer<void>();
          final semantics = t.ensureSemantics();
          try {
            await panel(t, p, suite);
            await action(t, source, 'data-location-open');
            expect(p.opens, 1);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            for (final button in t.widgetList<StarBridgeActionButton>(
              find.byType(StarBridgeActionButton),
            )) {
              if (button.controlKey != const Key('data-location-close')) {
                expect(button.onActivate, isNull);
              }
            }
            p.opening!.completeError(StateError('synthetic private details'));
            await t.pump();
            await t.pumpAndSettle();
            expect(find.textContaining('无法打开文件夹'), findsOneWidget);
            expect(find.textContaining('private details'), findsNothing);
            p.opening = null;
            await action(t, source, 'data-location-open');
            await t.pumpAndSettle();
            expect(p.opens, 2);
            expect(find.text('已打开文件夹'), findsOneWidget);
          } finally {
            await shut(t);
            semantics.dispose();
          }
        },
      );
      testWidgets(
        '$suite $source copy waits for clipboard acknowledgement and keeps exact path',
        (t) async {
          final p = LocationPort(), pending = Completer<Object?>();
          String? copied;
          final semantics = t.ensureSemantics();
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
                return pending.future;
              }
              return null;
            },
          );
          try {
            await panel(t, p, suite);
            await action(t, source, 'data-location-copy');
            expect(copied, p.location.path);
            expect(find.text('路径已复制'), findsNothing);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            pending.complete(null);
            await t.pump();
            await t.pumpAndSettle();
            expect(find.text('路径已复制'), findsOneWidget);
            expect(p.opens, 0);
          } finally {
            await shut(t);
            semantics.dispose();
            t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
          }
        },
      );
      testWidgets(
        '$suite $source choosing cancellation resumes controls without migration',
        (t) async {
          final p = LocationPort()
            ..choosing = Completer<DataLocationMigrationChoice?>();
          final semantics = t.ensureSemantics();
          try {
            await panel(t, p, suite);
            await action(t, source, 'data-location-move');
            expect(p.choices, 1);
            expect(
              InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
                  .reduceMotion,
              source != 'pointer',
            );
            p.choosing!.complete(null);
            await t.pump();
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('data-location-confirm-dialog')),
              findsNothing,
            );
            expect(p.tickets, isEmpty);
          } finally {
            await shut(t);
            semantics.dispose();
          }
        },
      );
      for (final confirmationSource in ['pointer', 'keyboard', 'reader']) {
        testWidgets(
          '$suite $source choose then $confirmationSource confirm hands off ticket only to beforeExit',
          (t) async {
            final p = LocationPort();
            ExitApplicationIntent? exit;
            final semantics = t.ensureSemantics();
            try {
              await t.pumpWidget(factory(p, suite, (intent) => exit = intent));
              await action(t, source, 'open-location');
              await t.pumpAndSettle();
              await action(t, source, 'data-location-move');
              await t.pumpAndSettle();
              final route = ModalRoute.of(
                t.element(
                  find.byKey(const Key('data-location-confirm-dialog')),
                ),
              ) as StarBridgeDialogRoute;
              expect(route.instant, source != 'pointer');
              expect(find.byType(SuiteProgressBar), findsNothing);
              expect(p.tickets, isEmpty);
              await action(t, confirmationSource, 'data-location-confirm');
              await t.pumpAndSettle();
              expect(exit, isNotNull);
              expect(find.byType(DataLocationDialog), findsNothing);
              expect(p.tickets, isEmpty);
              expect(await exit!.beforeExit!(), isTrue);
              expect(p.tickets, [p.choice!.ticket]);
            } finally {
              await shut(t);
              semantics.dispose();
            }
          },
        );
      }
      testWidgets(
        '$suite $source reject UI confirmation or Escape keeps original location',
        (t) async {
          final p = LocationPort();
          final semantics = t.ensureSemantics();
          try {
            await panel(t, p, suite);
            await action(t, source, 'data-location-move');
            await t.pumpAndSettle();
            if (source == 'keyboard') {
              await t.sendKeyEvent(LogicalKeyboardKey.escape);
              await t.pump();
              await t.pump();
            } else {
              await action(t, source, 'data-location-keep');
              await t.pumpAndSettle();
            }
            expect(
              find.byKey(const Key('data-location-confirm-dialog')),
              findsNothing,
            );
            expect(find.text(p.location.path), findsOneWidget);
            expect(p.tickets, isEmpty);
          } finally {
            await shut(t);
            semantics.dispose();
          }
        },
      );
    }
    for (final wpf in [false, true]) {
      testWidgets(
        '$suite failed beforeExit keeps app open with source-aware useful feedback $wpf',
        (t) async {
          final p = LocationPort()
            ..confirmationError = wpf
                ? const BridgeRemoteException('dataLocation.wpf_running')
                : StateError('synthetic private details');
          ExitApplicationIntent? exit;
          try {
            await t.pumpWidget(factory(p, suite, (value) => exit = value));
            await action(t, 'pointer', 'open-location');
            await t.pumpAndSettle();
            await action(t, 'pointer', 'data-location-move');
            await t.pumpAndSettle();
            await action(t, 'keyboard', 'data-location-confirm');
            await t.pumpAndSettle();
            expect(await exit!.beforeExit!(), isFalse);
            await t.pump();
            await t.pump();
            final text = find.textContaining(wpf ? '请先从托盘' : '迁移未能启动');
            expect(text, findsOneWidget);
            expect(InteractionScope.of(t.element(text)).reduceMotion, isTrue);
            expect(find.textContaining('private details'), findsNothing);
          } finally {
            await shut(t);
          }
        },
      );
    }
    testWidgets(
      '$suite leaving while native picker is pending ignores a late choice',
      (t) async {
        final p = LocationPort()
          ..choosing = Completer<DataLocationMigrationChoice?>();
        ExitApplicationIntent? exit;
        try {
          await t.pumpWidget(factory(p, suite, (value) => exit = value));
          await action(t, 'pointer', 'open-location');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'data-location-move');
          await action(t, 'keyboard', 'data-location-close');
          await t.pump();
          p.choosing!.complete(p.choice);
          await t.pump();
          await t.pumpAndSettle();
          expect(find.byType(DataLocationDialog), findsNothing);
          expect(exit, isNull);
          expect(p.tickets, isEmpty);
        } finally {
          await shut(t);
        }
      },
    );
    testWidgets(
      '$suite original retry schedule and manual retry remain distinct',
      (t) async {
        final p = LocationPort()..failRead = true;
        try {
          await panel(t, p, suite);
          expect(p.reads, 1);
          await t.pump(const Duration(seconds: 2));
          await t.pumpAndSettle();
          expect(p.reads, 2);
          p.failRead = false;
          await action(t, 'pointer', 'data-location-retry');
          await t.pumpAndSettle();
          expect(p.reads, 3);
          await t.pump(const Duration(seconds: 6));
          await t.pumpAndSettle();
          expect(p.reads, 3);
        } finally {
          await shut(t);
        }
      },
    );
    testWidgets('$suite live reduce lands an already running pointer wait', (
      t,
    ) async {
      final p = LocationPort()..opening = Completer<void>();
      try {
        await panel(t, p, suite);
        await action(t, 'pointer', 'data-location-open');
        await t.pumpWidget(
          scopedApp(
            DataLocationDialog(port: p, exitAvailable: true),
            suite,
            reduce: true,
          ),
        );
        await t.pump();
        expect(
          InteractionScope.of(t.element(find.byType(SuiteProgressBar)))
              .reduceMotion,
          isTrue,
        );
        await t.pump(const Duration(seconds: 1));
        await t.pump();
        expect(t.binding.hasScheduledFrame, isFalse);
        p.opening!.complete();
        await t.pump();
        await t.pumpAndSettle();
      } finally {
        await shut(t);
      }
    });
    testWidgets('$suite failed clipboard operation never claims copied', (
      t,
    ) async {
      final p = LocationPort();
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'synthetic-private-error');
          }
          return null;
        },
      );
      try {
        await panel(t, p, suite);
        await action(t, 'pointer', 'data-location-copy');
        await t.pumpAndSettle();
        expect(find.text('未能复制，请重试。'), findsOneWidget);
        expect(find.text('路径已复制'), findsNothing);
        expect(find.textContaining('private-error'), findsNothing);
        expect(p.opens, 0);
      } finally {
        await shut(t);
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      }
    });
    testWidgets(
      '$suite lost exit capability retires an already open migration confirmation',
      (t) async {
        final p = LocationPort();
        try {
          await panel(t, p, suite);
          await action(t, 'pointer', 'data-location-move');
          await t.pumpAndSettle();
          await t.pumpWidget(
            scopedApp(DataLocationDialog(port: p, exitAvailable: false), suite),
          );
          await t.pump();
          await t.pump();
          expect(
            find.byKey(const Key('data-location-confirm-dialog')),
            findsNothing,
          );
          expect(p.tickets, isEmpty);
        } finally {
          await shut(t);
        }
      },
    );
    for (final gate in ['exit', 'port']) {
      testWidgets(
        '$suite lost $gate capability while picker is pending does not open confirmation',
        (t) async {
          final p = LocationPort()
            ..choosing = Completer<DataLocationMigrationChoice?>();
          try {
            await panel(t, p, suite);
            await action(t, 'pointer', 'data-location-move');
            if (gate == 'port') p.available = false;
            await t.pumpWidget(
              scopedApp(
                DataLocationDialog(port: p, exitAvailable: gate != 'exit'),
                suite,
              ),
            );
            await t.pump();
            p.choosing!.complete(p.choice);
            await t.pump();
            await t.pumpAndSettle();
            expect(
              find.byKey(const Key('data-location-confirm-dialog')),
              findsNothing,
            );
            expect(p.tickets, isEmpty);
            expect(find.text(p.location.path), findsOneWidget);
          } finally {
            await shut(t);
          }
        },
      );
    }
    testWidgets(
      '$suite confirm rechecks a capability getter even without a new widget',
      (t) async {
        final p = LocationPort();
        try {
          await panel(t, p, suite);
          await action(t, 'pointer', 'data-location-move');
          await t.pumpAndSettle();
          final confirm = t
              .widgetList<StarBridgeActionButton>(
                find.byType(StarBridgeActionButton),
              )
              .singleWhere(
                (button) =>
                    button.controlKey == const Key('data-location-confirm'),
              );
          p.available = false;
          confirm.onActivate!(InteractionSource.keyboard);
          await t.pump();
          await t.pumpAndSettle();
          expect(
            find.byKey(const Key('data-location-confirm-dialog')),
            findsNothing,
          );
          expect(p.tickets, isEmpty);
        } finally {
          await shut(t);
        }
      },
    );
    testWidgets('$suite a late picker choice cannot act on a new Port', (
      t,
    ) async {
      final old = LocationPort()
            ..choosing = Completer<DataLocationMigrationChoice?>(),
          next = LocationPort();
      try {
        await panel(t, old, suite);
        await action(t, 'pointer', 'data-location-move');
        await panel(t, next, suite);
        old.choosing!.complete(old.choice);
        await t.pump();
        await t.pumpAndSettle();
        expect(
          find.byKey(const Key('data-location-confirm-dialog')),
          findsNothing,
        );
        expect(old.tickets, isEmpty);
        expect(next.tickets, isEmpty);
      } finally {
        await shut(t);
      }
    });
    testWidgets('$suite completed active opens are not merged', (t) async {
      final p = LocationPort();
      try {
        await panel(t, p, suite);
        for (var i = 0; i < 4; i++) {
          await action(t, 'pointer', 'data-location-open');
          await t.pump(const Duration(milliseconds: 100));
        }
        await t.pumpAndSettle();
        expect(p.opens, 4);
      } finally {
        await shut(t);
      }
    });
    for (final reason in [
      'missing-folder',
      'exit-unavailable',
      'migration-unavailable',
    ]) {
      testWidgets('$suite $reason cannot enable migration', (t) async {
        final p = LocationPort();
        if (reason == 'missing-folder') {
          p.location = const DataLocation(
            path: 'C:/synthetic/missing',
            exists: false,
          );
        }
        if (reason == 'migration-unavailable') p.available = false;
        try {
          await t.pumpWidget(
            scopedApp(
              DataLocationDialog(
                port: p,
                exitAvailable: reason != 'exit-unavailable',
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          final move = t
              .widgetList<StarBridgeActionButton>(
                find.byType(StarBridgeActionButton),
              )
              .singleWhere(
                (w) => w.controlKey == const Key('data-location-move'),
              );
          expect(move.onActivate, isNull);
          expect(p.choices, 0);
          expect(p.tickets, isEmpty);
        } finally {
          await shut(t);
        }
      });
    }
    testWidgets(
      '$suite old open response cannot replace the next port feedback',
      (t) async {
        final old = LocationPort()..opening = Completer<void>(),
            next = LocationPort()
              ..location = const DataLocation(
                path: 'D:/synthetic/next',
                exists: true,
              );
        try {
          await panel(t, old, suite);
          await action(t, 'pointer', 'data-location-open');
          await panel(t, next, suite);
          old.opening!.complete();
          await t.pump();
          await t.pumpAndSettle();
          expect(find.text(next.location.path), findsOneWidget);
          expect(find.text('已打开文件夹'), findsNothing);
        } finally {
          await shut(t);
        }
      },
    );
    testWidgets(
      '$suite dispose retires only its confirmation below a newer route',
      (t) async {
        final p = LocationPort(), visible = ValueNotifier(true);
        BuildContext? rootContext;
        try {
          await t.pumpWidget(
            scopedApp(
              Builder(
                builder: (context) {
                  rootContext = context;
                  return ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, value, _) => value
                        ? DataLocationDialog(port: p, exitAvailable: true)
                        : const Text('left'),
                  );
                },
              ),
              suite,
            ),
          );
          await t.pumpAndSettle();
          await action(t, 'pointer', 'data-location-move');
          await t.pumpAndSettle();
          unawaited(
            showStarBridgeDialog<void>(
              rootContext!,
              builder: (_) => const AlertDialog(content: Text('newer')),
            ),
          );
          await t.pumpAndSettle();
          visible.value = false;
          await t.pump();
          await t.pump();
          expect(find.text('newer'), findsOneWidget);
          expect(
            find.byKey(const Key('data-location-confirm-dialog')),
            findsNothing,
          );
          expect(p.tickets, isEmpty);
        } finally {
          await shut(t);
          visible.dispose();
        }
      },
    );
    testWidgets(
      '$suite keyboard opening does not silence later pointer failure feedback',
      (t) async {
        final p = LocationPort()
          ..confirmationError = StateError('synthetic failure');
        ExitApplicationIntent? exit;
        try {
          await t.pumpWidget(factory(p, suite, (value) => exit = value));
          await action(t, 'keyboard', 'open-location');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'data-location-move');
          await t.pumpAndSettle();
          await action(t, 'pointer', 'data-location-confirm');
          await t.pumpAndSettle();
          expect(await exit!.beforeExit!(), isFalse);
          await t.pump();
          await t.pump();
          expect(
            InteractionScope.of(t.element(find.textContaining('迁移未能启动')))
                .reduceMotion,
            isFalse,
          );
        } finally {
          await shut(t);
        }
      },
    );
  }
}
