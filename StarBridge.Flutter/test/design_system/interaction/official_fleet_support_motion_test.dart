// Review-only test source. Run only in an isolated application whose
// official_fleet_support_views.dart is this batch's candidate, not in primary.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/common/social_read_activity.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_support_views.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/official_fleet_motion_helpers.dart'
    show loadFonts, size, scopedApp, frames, exposedNodes;

const _native = Key('original-outline-icon');
final _action = find.byKey(const Key('official-fleet-retry-native'));
final _target = find.byKey(const Key('official-fleet-retry-target'));

OutlinedButton _button(WidgetTester t, Finder target) =>
    t.widget<OutlinedButton>(target);

Future<void> _act(WidgetTester t, String source) async {
  expect(_target, findsOneWidget);
  expect(_action, findsOneWidget);
  if (source == 'pointer') {
    await t.tap(_action);
  } else if (source == 'keyboard') {
    final focus = _button(t, _action).focusNode!;
    focus.requestFocus();
    await t.pump();
    expect(focus.hasFocus, true);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
  } else {
    final label = AppStrings.of(t.element(_action))
        .text('officialFleet.action.retry');
    final nodes = exposedNodes(t).where((node) {
      final data = node.getSemanticsData();
      return data.label == label && data.flagsCollection.isButton;
    }).toList();
    // Dispatch through the exposed owner-root node, not a cached internal
    // native node or a direct Semantics callback that bypasses merging.
    expect(nodes, hasLength(1));
    expect(
      nodes.single.getSemanticsData().hasAction(ui.SemanticsAction.tap),
      true,
    );
    t.binding.renderViews.single.owner!.semanticsOwner!.performAction(
      nodes.single.id,
      ui.SemanticsAction.tap,
    );
  }
  await t.pump();
  await frames(t);
}

class _Layout {
  const _Layout({
    required this.outer,
    required this.face,
    required this.faceOffset,
    required this.text,
    required this.textOffset,
    required this.icon,
    required this.iconOffset,
    required this.padding,
    required this.constraints,
    required this.foreground,
    required this.side,
  });
  final Size outer, face, text, icon;
  final Offset faceOffset, textOffset, iconOffset;
  final EdgeInsets padding;
  final BoxConstraints constraints;
  final Color? foreground;
  final BorderSide side;
}

_Layout _layout(WidgetTester t, Finder target) {
  final face = find
      .descendant(of: target, matching: find.byType(Material))
      .first;
  final ink = find.descendant(of: target, matching: find.byType(InkWell)).first;
  final padding = find
      .descendant(of: ink, matching: find.byType(Padding))
      .first;
  final constraint = find
      .ancestor(of: face, matching: find.byType(ConstrainedBox))
      .first;
  final text = find.descendant(of: target, matching: find.byType(Text)).first;
  final icon = find
      .descendant(of: target, matching: find.byType(StarBridgeIcon))
      .first;
  final style = DefaultTextStyle.of(t.element(text)).style
      .merge(t.widget<Text>(text).style);
  final renderedPadding = t.renderObject<RenderPadding>(padding);
  final shape = t.widget<Material>(face).shape! as OutlinedBorder;
  return _Layout(
    outer: t.getSize(target),
    face: t.getSize(face),
    faceOffset: t.getTopLeft(face) - t.getTopLeft(target),
    text: t.getSize(text),
    textOffset: t.getTopLeft(text) - t.getTopLeft(target),
    icon: t.getSize(icon),
    iconOffset: t.getTopLeft(icon) - t.getTopLeft(target),
    padding: renderedPadding.padding.resolve(renderedPadding.textDirection),
    constraints: t
        .renderObject<RenderConstrainedBox>(constraint)
        .additionalConstraints,
    foreground: style.color,
    side: shape.side,
  );
}

Future<_Layout> _observeLayout(
  WidgetTester t,
  Finder target,
  String state,
) async {
  final native = _button(t, target);
  FocusManager.instance.primaryFocus?.unfocus();
  await frames(t, 40);
  if (state == 'focus') {
    // Focus visuals follow keyboard input (KeyboardModality).
    await t.sendKeyEvent(LogicalKeyboardKey.shift);
    native.focusNode!.requestFocus();
    await frames(t, 40);
    expect(native.focusNode!.hasFocus, true);
    expect(native.statesController!.value, contains(WidgetState.focused));
  }
  TestGesture? gesture;
  if (state == 'pressed') {
    gesture = await t.startGesture(t.getCenter(target));
    await frames(t, 40);
    expect(native.statesController!.value, contains(WidgetState.pressed));
  }
  try {
    return _layout(t, target);
  } finally {
    if (gesture != null) {
      await gesture.cancel();
      await frames(t, 40);
    }
  }
}

void _sameLayout(_Layout actual, _Layout reference, InteractionSuite suite) {
  expect(actual.outer, reference.outer);
  expect(actual.face, reference.face);
  expect(actual.faceOffset, reference.faceOffset);
  expect(actual.text, reference.text);
  expect(actual.textOffset, reference.textOffset);
  expect(actual.icon, reference.icon);
  expect(actual.iconOffset, reference.iconOffset);
  // These are the applied native Padding/ConstrainedBox values, not a
  // theme.merge(default) object also copied by the candidate implementation.
  expect(actual.padding, reference.padding);
  expect(actual.constraints.minWidth, reference.constraints.minWidth);
  expect(actual.constraints.minHeight, reference.constraints.minHeight);
  expect(actual.constraints.maxWidth, reference.constraints.maxWidth);
  expect(actual.constraints.maxHeight, reference.constraints.maxHeight);
  expect(actual.foreground, reference.foreground);
  if (suite == InteractionSuite.standard) {
    expect(actual.side, reference.side);
  } else {
    // Approved native stroke suppression. Local Suite edge paint is a
    // separate visual contract; BorderSide.none is not an equivalent frame.
    expect(actual.side, BorderSide.none);
  }
}

Widget panel({
  String? action = 'officialFleet.action.retry',
  Future<void> Function()? onAction,
}) => OfficialFleetStatePanel(
  icon: StarBridgeIconSemantic.warning,
  titleKey: 'officialFleet.unavailable.title',
  bodyKey: 'officialFleet.error.transient',
  actionKey: action,
  onAction: onAction,
);

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets('3gk candidate $suite $source original async callback once', (
        t,
      ) async {
        final semantics = t.ensureSemantics();
        final pending = Completer<void>();
        final calls = <InteractionSource>[];
        try {
          size(t, const Size(1000, 900));
          await t.pumpWidget(
            scopedApp(
              panel(
                onAction: () {
                  calls.add(captureStarBridgeActivationSource()());
                  return pending.future;
                },
              ),
              suite,
            ),
          );
          await frames(t);
          await _act(t, source);
          expect(calls, [
            source == 'pointer'
                ? InteractionSource.pointer
                : InteractionSource.keyboard,
          ]);
          // No new local busy gate: the original owner still decides whether
          // its callback is admitted. Presentation must not swallow a second input.
          await _act(t, source);
          expect(calls, hasLength(2));
          expect(_button(t, _action).onPressed, isNotNull);
          expect(
            find.descendant(
              of: _target,
              matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
            ),
            findsOneWidget,
          );
          pending.complete();
          await frames(t);
          expect(calls, hasLength(2));
          expect(t.takeException(), isNull);
        } finally {
          if (!pending.isCompleted) pending.complete();
          await t.pumpWidget(const SizedBox());
          semantics.dispose();
        }
      });
    }
    for (final missing in ['callback', 'key']) {
      testWidgets('3gk candidate $suite missing $missing exposes no action', (
        t,
      ) async {
        size(t, const Size(1000, 900));
        await t.pumpWidget(
          scopedApp(
            panel(
              action: missing == 'key' ? null : 'officialFleet.action.retry',
              onAction: missing == 'callback' ? null : () async {},
            ),
            suite,
          ),
        );
        await frames(t);
        expect(_action, findsNothing);
        expect(_target, findsNothing);
        expect(
          find.byWidgetPredicate((w) => w is ButtonStyleButton),
          findsNothing,
        );
        expect(find.byType(SuitePressable), findsNothing);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      });
    }
    for (final light in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets(
          '3gk candidate $suite outline geometry light=$light scale=$scale',
          (t) async {
            size(t, Size(scale == 1 ? 1280 : 900, 1000));
            final nativeFocus = FocusNode();
            final nativeStates = WidgetStatesController();
            addTearDown(() async {
              await t.pumpWidget(const SizedBox());
              nativeFocus.dispose();
              nativeStates.dispose();
            });
            await t.pumpWidget(
              scopedApp(
                Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        panel(onAction: () async {}),
                        Align(
                          widthFactor: 1,
                          heightFactor: 1,
                          child: Builder(
                            builder: (context) => OutlinedButton.icon(
                              key: _native,
                              focusNode: nativeFocus,
                              statesController: nativeStates,
                              onPressed: () {},
                              icon: const StarBridgeIcon(
                                StarBridgeIconSemantic.refresh,
                              ),
                              label: Text(
                                AppStrings.of(context)
                                    .text('officialFleet.action.retry'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                suite,
                light: light,
              ),
            );
            await frames(t, 40);
            expect(_target, findsOneWidget);
            final oldTarget = find.byKey(_native);
            for (final state in ['idle', 'focus', 'pressed']) {
              final reference = await _observeLayout(t, oldTarget, state);
              final actual = await _observeLayout(t, _action, state);
              _sameLayout(actual, reference, suite);
            }
            expect(
              find.descendant(
                of: _action,
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is StarBridgeIcon &&
                      w.semantic == StarBridgeIconSemantic.refresh,
                ),
              ),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
          },
        );
      }
      testWidgets(
        '3gk candidate $suite loading static unique semantics light=$light',
        (t) async {
          final semantics = t.ensureSemantics();
          try {
            size(t, const Size(1000, 900));
            await t.pumpWidget(
              scopedApp(const OfficialFleetLoadingView(), suite, light: light),
            );
            await frames(t, 40);
            final context = t.element(find.byType(OfficialFleetLoadingView));
            final label = AppStrings.of(context).text('officialFleet.loading');
            final activity = t.widget<SocialReadActivity>(
              find.byType(SocialReadActivity),
            );
            expect(activity.source, InteractionSource.programmatic);
            expect(activity.opening, false);
            final labels = <String>[];
            for (final node in exposedNodes(t)) {
              final data = node.getSemanticsData();
              if (data.label.contains(label)) labels.add(data.label);
              expect(data.value.contains('%'), false);
            }
            expect(labels, [label]);
            if (suite == InteractionSuite.standard) {
              final spinner = find.byType(CircularProgressIndicator);
              expect(t.widget<CircularProgressIndicator>(spinner).value, .5);
              expect(
                t.getSize(spinner),
                Size.square(context.tokens.icons.medium),
              );
            } else {
              expect(
                t
                    .widget<LinearProgressIndicator>(
                      find.byType(LinearProgressIndicator),
                    )
                    .value,
                .5,
              );
            }
            expect(t.binding.hasScheduledFrame, false);
            await frames(t, 40);
            expect(t.binding.hasScheduledFrame, false);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            semantics.dispose();
          }
        },
      );
    }
  }
}
