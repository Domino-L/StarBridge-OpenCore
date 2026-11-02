import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_snack_bar.dart';
import 'package:starbridge_flutter/design_system/controls/semantic_action_style.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_layout.dart';

import 'interaction_batch3at_test.dart' as profile;
import 'interaction_batch3aa_test.dart' show select;

import 'interaction_batch3ae_test.dart' show mount;
import 'interaction_batch3ac_test.dart' show LiveState;
import '../../features/friends/social_layout_test.dart' show loadFonts;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;

class Host extends StatefulWidget {
  const Host({super.key});
  @override
  State<Host> createState() => HostState();
}

class HostState extends State<Host> {
  late BuildContext caller;
  bool localReduce = false, visible = true;
  void change(VoidCallback update) => setState(update);
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    String label, {
    InteractionSource source = InteractionSource.pointer,
    Duration duration = const Duration(seconds: 4),
    SnackBar? original,
  }) => showStarBridgeSnackBar(
    caller,
    original ?? SnackBar(content: Text(label), duration: duration),
    source: source,
    tone: ActionTone.danger,
  );
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: localReduce),
    child: visible
        ? Builder(
            builder: (context) {
              caller = context;
              return const Text('Source');
            },
          )
        : const Text('Source left'),
  );
}

Future<(HostState, LiveState)> host(
  WidgetTester t,
  InteractionSuite suite, {
  GlobalKey? capture,
}) async {
  final key = GlobalKey<HostState>();
  final live = await mount(t, Host(key: key), suite, capture: capture);
  return (key.currentState!, live);
}

SuiteSurfaceTransition transition(WidgetTester t) =>
    t.widget<SuiteSurfaceTransition>(
      find.byWidgetPredicate(
        (w) => w is SuiteSurfaceTransition && w.kind == SurfaceKind.toast,
      ),
    );
AnimationController animation(WidgetTester t) =>
    transition(t).animation as AnimationController;
Future<void> frame(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

Future<void> openControl(WidgetTester t, Key key, String source) async {
  final target = find.byKey(key).first;
  await t.ensureVisible(target);
  if (source == 'pointer') {
    await t.tap(target);
  } else if (source == 'keyboard') {
    final focus = t.widget<SuitePressable>(target).focusNode!;
    expect(focus.canRequestFocus, isTrue);
    focus.requestFocus();
    await t.pump();
    expect(FocusManager.instance.primaryFocus, same(focus));
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final node = t.getSemantics(target);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
  }
  await frame(t);
}

Future<void> selectControl(
  WidgetTester t,
  Object identity,
  Object value,
  String source,
) async {
  if (source != 'reader') return select(t, identity, value, source);
  final row = find.byKey(ValueKey<Object>((identity, value)));
  final node = t.getSemantics(row);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
  t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await frame(t);
}

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pump();
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final bytes = await image.toByteData(format: ImageByteFormat.png);
    final dir = Directory('build/reviews/interaction-batch3aw');
    await dir.create(recursive: true);
    await File('${dir.path}/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in InteractionSource.values) {
      testWidgets('native timer and onVisible are retained $suite $source', (
        t,
      ) async {
        final (state, _) = await host(t, suite);
        var visible = 0;
        SnackBarClosedReason? reason;
        final original = SnackBar(
          content: const Text('Failure'),
          onVisible: () => visible++,
        );
        state
            .show('Failure', original: original, source: source)
            .closed
            .then((r) => reason = r);
        await frame(t);
        final c = animation(t);
        if (source == InteractionSource.keyboard) {
          expect(c.value, 1);
          expect(c.isAnimating, isFalse);
        }
        if (source != InteractionSource.keyboard) {
          await t.pump(c.duration! + const Duration(milliseconds: 1));
        }
        await frame(t);
        expect(visible, 1);
        await t.pump(const Duration(milliseconds: 3999));
        expect(reason, isNull);
        await t.pump(const Duration(milliseconds: 1));
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        expect(reason, SnackBarClosedReason.timeout);
        expect(visible, 1);
        expect(find.text('Failure'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    for (final phase in ['entrance', 'settled', 'exit']) {
      testWidgets(
        'local reduced motion settles pending native futures $suite $phase',
        (t) async {
          final (state, _) = await host(t, suite);
          SnackBarClosedReason? closed;
          final first = state.show('First');
          first.closed.then((r) => closed = r);
          await frame(t);
          if (phase != 'entrance') {
            await t.pump(const Duration(milliseconds: 500));
          }
          if (phase == 'exit') {
            first.close();
            await t.pump(const Duration(milliseconds: 20));
          }
          final c = animation(t);
          state.change(() => state.localReduce = true);
          await frame(t);
          await t.pump();
          expect(c.isAnimating, isFalse);
          if (phase == 'exit') {
            expect(closed, SnackBarClosedReason.hide);
            expect(find.text('First'), findsNothing);
          } else {
            expect(c.value, 1);
            expect(closed, isNull);
            first.close();
            await frame(t);
            expect(closed, SnackBarClosedReason.hide);
          }
          expect(t.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'keyboard entry does not disable queued pointer animation $suite',
      (t) async {
        final (state, _) = await host(t, suite);
        final reasons = <SnackBarClosedReason>[];
        final first = state.show('First', source: InteractionSource.keyboard);
        first.closed.then(reasons.add);
        state.show('Second').closed.then(reasons.add);
        await frame(t);
        expect(find.text('Second'), findsNothing);
        expect(animation(t).value, 1);
        first.close();
        await frame(t);
        expect(reasons, [SnackBarClosedReason.hide]);
        await frame(t);
        expect(find.text('Second'), findsOneWidget);
        expect(animation(t).value, lessThan(1));
        await t.pump(const Duration(milliseconds: 500));
        ScaffoldMessenger.of(state.caller).removeCurrentSnackBar();
        await frame(t);
        expect(reasons, [
          SnackBarClosedReason.hide,
          SnackBarClosedReason.remove,
        ]);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'source may leave while queue follows the global scope $suite',
      (t) async {
        final (state, live) = await host(t, suite);
        final first = state.show('First');
        state.show('Second');
        await frame(t);
        state.change(() => state.visible = false);
        live.change(() => live.suite = InteractionSuite.glow);
        await frame(t);
        first.close();
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        expect(find.text('Second'), findsOneWidget);
        await t.pump(const Duration(milliseconds: 500));
        final d = InteractionScope.of(t.element(find.text('Second')));
        expect(d.suite, InteractionSuite.glow);
        await t.pumpWidget(const SizedBox.shrink());
        await frame(t);
        expect(InteractionScope.debugLiveLinks, 0);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'native props geometry action and close reason are retained $suite',
      (t) async {
        final (state, _) = await host(t, suite);
        var actions = 0;
        SnackBarClosedReason? closed;
        const key = ValueKey('original-native');
        final original = SnackBar(
          key: key,
          content: const Text('Failure'),
          behavior: SnackBarBehavior.floating,
          width: 500,
          backgroundColor: Colors.indigo,
          elevation: 7,
          padding: const EdgeInsets.all(18),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          dismissDirection: DismissDirection.horizontal,
          clipBehavior: Clip.antiAlias,
          action: SnackBarAction(label: 'Retry', onPressed: () => actions++),
          persist: false,
        );
        state
            .show('Failure', original: original)
            .closed
            .then((r) => closed = r);
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        final native = t.widget<SnackBar>(find.byKey(key));
        expect(native.width, original.width);
        expect(native.shape, original.shape);
        expect(native.padding, original.padding);
        expect(native.action!.label, original.action!.label);
        expect(native.action!.key, original.action!.key);
        expect(native.persist, false);
        expect(native.elevation, 7);
        expect(native.animation!.value, 1);
        expect(transition(t).surfaceBounds!.width, closeTo(500, 1));
        await t.tap(find.text('Retry'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        expect(actions, 1);
        expect(closed, SnackBarClosedReason.action);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets('reader dismiss preserves native reason $suite', (t) async {
      final handle = t.ensureSemantics();
      final (state, _) = await host(t, suite);
      SnackBarClosedReason? closed;
      state.show('Failure').closed.then((r) => closed = r);
      await frame(t);
      await t.pump(const Duration(milliseconds: 500));
      final nodes = t.binding.renderViews.single.owner!.semanticsOwner!;
      final root = t.getSemantics(find.byType(SnackBar));
      var found = false;
      void visit(SemanticsNode node) {
        if (node.getSemanticsData().hasAction(SemanticsAction.dismiss)) {
          nodes.performAction(node.id, SemanticsAction.dismiss);
          found = true;
        } else {
          node.visitChildren((c) {
            visit(c);
            return !found;
          });
        }
      }

      visit(root);
      await frame(t);
      expect(found, true);
      expect(closed, SnackBarClosedReason.dismiss);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('keyboard close icon preserves native dismiss $suite', (
      t,
    ) async {
      final (state, _) = await host(t, suite);
      SnackBarClosedReason? closed;
      state
          .show(
            'Failure',
            original: const SnackBar(
              content: Text('Failure'),
              showCloseIcon: true,
            ),
          )
          .closed
          .then((r) => closed = r);
      await frame(t);
      await t.pump(const Duration(milliseconds: 500));
      final icon = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byType(IconButton),
      );
      final focus = Focus.of(
        t.element(find.descendant(of: icon, matching: find.byType(Icon)).first),
      );
      focus.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await frame(t);
      expect(closed, SnackBarClosedReason.dismiss);
      expect(find.text('Failure'), findsNothing);
      expect(t.takeException(), isNull);
    });

    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        'native action delegates once with actual source $suite $source',
        (t) async {
          final semantics = t.ensureSemantics();
          final (state, _) = await host(t, suite);
          final origins = <InteractionSource>[];
          SnackBarClosedReason? reason;
          state
              .show(
                'Failure',
                original: SnackBar(
                  content: const Text('Failure'),
                  action: SnackBarAction(
                    label: 'Retry',
                    onPressed: () =>
                        origins.add(currentStarBridgeActivationSource),
                  ),
                  persist: false,
                ),
              )
              .closed
              .then((r) => reason = r);
          await frame(t);
          await t.pump(const Duration(milliseconds: 500));
          final target = find.text('Retry');
          if (source == 'pointer') {
            await t.tap(target);
            await t.pump();
            expect(animation(t).isAnimating, true);
            await t.pump(const Duration(milliseconds: 500));
          } else if (source == 'keyboard') {
            Focus.of(t.element(target)).requestFocus();
            await t.pump();
            await t.sendKeyEvent(LogicalKeyboardKey.enter);
          } else {
            final node = t.getSemantics(target);
            t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
              node.id,
              SemanticsAction.tap,
            );
          }
          await frame(t);
          expect(origins, [
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          expect(reason, SnackBarClosedReason.action);
          expect(find.text('Failure'), findsNothing);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          semantics.dispose();
        },
      );

      for (final failure in ['capacity', 'space']) {
        testWidgets(
          'actual grid $failure failure preserves layout $suite $source',
          (t) async {
            final semantics = t.ensureSemantics();
            final (state, _) = await profile.grid(t, suite);
            state.change(
              () => state.layout = PersonalProfileLayout.normalize(
                failure == 'capacity'
                    ? [
                        profile.item.copyWith(
                          size: PersonalProfileModuleSize.two,
                          favoriteShipIds: [profile.a, profile.b],
                        ),
                      ]
                    : [
                        for (var i = 0; i < 64; i++)
                          PersonalProfileModuleLayoutItem(
                            moduleId: i == 0
                                ? 'favorite-ships'
                                : 'favorite-ships-$i',
                            size: PersonalProfileModuleSize.three,
                            isVisible: true,
                            position: i * 3,
                            favoriteShipIds: const [],
                          ),
                      ],
              ),
            );
            await settleCommunityImages(t);
            final before = state.layout;
            if (failure == 'capacity') {
              await openControl(
                t,
                const Key('profile-module-size-favorite-ships'),
                source,
              );
              await settleCommunityImages(t);
              await selectControl(
                t,
                'profile-module-size-favorite-ships',
                PersonalProfileModuleSize.one,
                source,
              );
            } else {
              await openControl(
                t,
                const Key('profile-add-module-anchor'),
                source,
              );
              await settleCommunityImages(t);
              await selectControl(
                t,
                'profile-add-module',
                'hangar-summary',
                source,
              );
            }
            await frame(t);
            final label = AppStrings.of(state.context).text(
              failure == 'capacity'
                  ? 'profile.favorites.resize'
                  : 'profile.layout.noSpace',
            );
            expect(find.text(label), findsOneWidget);
            expect(state.calls, isEmpty);
            expect(
              PersonalProfileLayout.hasSameLayout(state.layout, before),
              true,
            );
            if (source != 'pointer') expect(animation(t).isAnimating, false);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
          },
        );
      }
    }

    for (final close in ['swipe', 'clear']) {
      testWidgets('native $close retains original queue semantics $suite', (
        t,
      ) async {
        final (state, _) = await host(t, suite);
        SnackBarClosedReason? reason;
        state.show('First').closed.then((r) => reason = r);
        state.show('Second');
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        if (close == 'swipe') {
          await t.drag(find.byType(SnackBar), const Offset(0, 150));
        } else {
          ScaffoldMessenger.of(state.caller).clearSnackBars();
        }
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        expect(
          reason,
          close == 'swipe'
              ? SnackBarClosedReason.swipe
              : SnackBarClosedReason.hide,
        );
        expect(
          find.text('Second'),
          close == 'swipe' ? findsOneWidget : findsNothing,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await frame(t);
        expect(InteractionScope.debugLiveLinks, 0);
        expect(t.takeException(), isNull);
      });
    }
    testWidgets(
      'live global theme and reduction apply to open and queued entry $suite',
      (t) async {
        final (state, live) = await host(t, suite);
        final first = state.show('First');
        state.show('Second');
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        live.change(() {
          live.suite = InteractionSuite.scan;
          live.reduce = true;
          live.light = true;
        });
        await frame(t);
        final data = InteractionScope.of(t.element(find.text('First')));
        expect(data.suite, InteractionSuite.scan);
        expect(data.palette.brightness, Brightness.light);
        expect(animation(t).isAnimating, false);
        live.change(() => live.reduce = false);
        await frame(t);
        first.close();
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        expect(find.text('Second'), findsOneWidget);
        expect(
          InteractionScope.of(t.element(find.text('Second'))).reduceMotion,
          false,
        );
        expect(animation(t).value, lessThan(1));
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'mixed native queue retains its original controller timings $suite',
      (t) async {
        final (state, _) = await host(t, suite);
        final first = state.show('First');
        final messenger = ScaffoldMessenger.of(state.caller);
        messenger.showSnackBar(const SnackBar(content: Text('Raw native')));
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        first.close();
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        await frame(t);
        final raw = t.widget<SnackBar>(find.byType(SnackBar));
        final c = raw.animation! as AnimationController;
        expect(c.duration, const Duration(milliseconds: 250));
        expect(c.reverseDuration, isNull);
        expect(t.takeException(), isNull);
      },
    );

    testWidgets(
      'throwing native callback does not close or duplicate action $suite',
      (t) async {
        final (state, _) = await host(t, suite);
        var calls = 0;
        SnackBarClosedReason? reason;
        state
            .show(
              'Failure',
              original: SnackBar(
                content: const Text('Failure'),
                action: SnackBarAction(
                  label: 'Retry',
                  onPressed: () {
                    calls++;
                    throw StateError('callback rejected');
                  },
                ),
                persist: false,
              ),
            )
            .closed
            .then((r) => reason = r);
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        await t.tap(find.text('Retry'));
        expect(t.takeException(), isA<StateError>());
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        expect(calls, 1);
        expect(reason, isNull);
        expect(find.text('Failure'), findsOneWidget);
        await t.tap(find.text('Retry'));
        await frame(t);
        expect(calls, 1);
        expect(t.takeException(), isNull);
      },
    );

    if (suite != InteractionSuite.standard) {
      testWidgets('toast frames review $suite', (t) async {
        final boundary = GlobalKey();
        final (state, _) = await host(t, suite, capture: boundary);
        final item = state.show(
          'Failure',
          original: const SnackBar(
            content: Text('空间不足，布局没有更改。请调整模块大小后重试。'),
            behavior: SnackBarBehavior.floating,
            width: 520,
          ),
        );
        await frame(t);
        await t.pump(const Duration(milliseconds: 80));
        await capture(t, boundary, '${suite.name}-entry');
        await t.pump(const Duration(milliseconds: 500));
        await capture(t, boundary, '${suite.name}-settled');
        item.close();
        await t.pump();
        await t.pump(const Duration(milliseconds: 30));
        expect(animation(t).value, greaterThan(0));
        expect(animation(t).value, lessThan(1));
        await capture(t, boundary, '${suite.name}-exit');
        await settleCommunityImages(t);
        state.show('空间不足，布局没有更改。请调整模块大小后重试。');
        await frame(t);
        await t.pump(const Duration(milliseconds: 500));
        await capture(t, boundary, '${suite.name}-fixed');
        expect(t.takeException(), isNull);
      });
    }
  }
}
