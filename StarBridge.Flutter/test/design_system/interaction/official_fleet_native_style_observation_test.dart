// C-only independent observations; never a product implementation or theme fix.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon_painter.dart';
import 'package:starbridge_flutter/features/official_fleet/official_fleet_support_views.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../_support/official_fleet_motion_helpers.dart'
    show loadFonts, size, scopedApp, frames;

const _nativeKey = Key('original-style-reference');
final _nativeTarget = find.byKey(_nativeKey);
final _candidateTarget = find.byKey(const Key('official-fleet-retry-native'));
final _observations = <Map<String, Object?>>[];

class _Harness {
  _Harness(
    this.suite,
    this.light, {
    this.nullTheme = false,
    this.candidate = true,
  });
  final InteractionSuite suite;
  final bool light, nullTheme, candidate;
  final oldFocus = FocusNode();
  final oldStates = WidgetStatesController();
  late OutlinedButton reference;

  Widget app() => scopedApp(
    Builder(
      builder: (context) {
        final base = Theme.of(context);
        final original = base.outlinedButtonTheme.style ?? const ButtonStyle();
        bool active(Set<WidgetState> s) =>
            s.contains(WidgetState.focused) || s.contains(WidgetState.pressed);
        final theme = !nullTheme
            ? base
            : base.copyWith(
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style: original.copyWith(
                    foregroundColor: WidgetStateProperty.resolveWith(
                      (s) => active(s) ? null : const Color(0xffac14c7),
                    ),
                    side: WidgetStateProperty.resolveWith(
                      (s) => active(s)
                          ? null
                          : const BorderSide(
                              color: Color(0xff37a358),
                              width: 3,
                            ),
                    ),
                    textStyle: WidgetStateProperty.resolveWith(
                      (s) => active(s)
                          ? null
                          : const TextStyle(
                              inherit: false,
                              fontSize: 17,
                              letterSpacing: 1.25,
                            ),
                    ),
                  ),
                ),
              );
        return Theme(
          data: theme,
          child: Builder(
            builder: (context) => SizedBox(
              width: 700,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (candidate)
                    const SizedBox(
                      height: 280,
                      child: OfficialFleetStatePanel(
                        icon: StarBridgeIconSemantic.warning,
                        titleKey: 'officialFleet.unavailable.title',
                        bodyKey: 'officialFleet.error.transient',
                        actionKey: 'officialFleet.action.retry',
                        onAction: _noRequest,
                      ),
                    ),
                  const SizedBox(height: 24),
                  reference = OutlinedButton.icon(
                    key: _nativeKey,
                    focusNode: oldFocus,
                    statesController: oldStates,
                    onPressed: () {},
                    icon: const StarBridgeIcon(StarBridgeIconSemantic.refresh),
                    label: Text(
                      AppStrings.of(context).text('officialFleet.action.retry'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
    suite,
    light: light,
  );

  Future<void> mount(WidgetTester t) async {
    size(t, const Size(1000, 900));
    await t.pumpWidget(app());
    await frames(t, 40);
  }

  Future<void> dispose(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    oldFocus.dispose();
    oldStates.dispose();
  }
}

Future<void> _noRequest() async {}

FocusNode _focus(WidgetTester t, Finder target) =>
    t.widget<OutlinedButton>(target).focusNode!;

class _Rendered {
  const _Rendered(
    this.text,
    this.icon,
    this.side, [
    this.nativeStates = const {},
  ]);
  final TextStyle text;
  final Color icon;
  final BorderSide? side;
  final Set<WidgetState> nativeStates;
  Map<String, Object?> json() => {
    'textColor': text.color?.toARGB32().toRadixString(16),
    'fontFamily': text.fontFamily,
    'fontSize': text.fontSize,
    'fontWeight': text.fontWeight?.value,
    'height': text.height,
    'letterSpacing': text.letterSpacing,
    'iconColor': icon.toARGB32().toRadixString(16),
    'actualNativeMaterialSide': side == null
        ? null
        : {
            'color': side!.color.toARGB32().toRadixString(16),
            'width': side!.width,
            'style': side!.style.name,
          },
  };
}

_Rendered _rendered(WidgetTester t, Finder target) {
  final text = find.descendant(of: target, matching: find.byType(Text)).first;
  final effective = DefaultTextStyle.of(t.element(text)).style
      .merge(t.widget<Text>(text).style);
  final icon = find
      .descendant(of: target, matching: find.byType(StarBridgeIcon))
      .first;
  final paint = find
      .descendant(of: icon, matching: find.byType(CustomPaint))
      .first;
  final actualIcon =
      (t.widget<CustomPaint>(paint).painter! as StarBridgeIconPainter).color;
  final material = find.descendant(of: target, matching: find.byType(Material));
  final shape = material.evaluate().isEmpty
      ? null
      : t.widget<Material>(material.first).shape;
  return _Rendered(
    effective,
    actualIcon,
    shape is OutlinedBorder ? shape.side : null,
  );
}

Future<_Rendered> _observe(
  WidgetTester t,
  _Harness h,
  String state, {
  required bool original,
}) async {
  final target = original ? _nativeTarget : _candidateTarget;
  final focus = original ? h.oldFocus : _focus(t, target);
  final states = original
      ? h.oldStates
      : t.widget<OutlinedButton>(target).statesController!;
  FocusManager.instance.primaryFocus?.unfocus();
  await frames(t, 40);
  if (state == 'focus') {
    // Focus visuals follow keyboard input (KeyboardModality).
    await t.sendKeyEvent(LogicalKeyboardKey.shift);
    focus.requestFocus();
    await frames(t, 40);
    expect(focus.hasFocus, true);
    expect(states.value, contains(WidgetState.focused));
  }
  TestGesture? down;
  if (state == 'pressed') {
    down = await t.startGesture(t.getCenter(target));
    await frames(t, 40);
    expect(states.value, contains(WidgetState.pressed));
  }
  final raw = _rendered(t, target);
  final result = _Rendered(raw.text, raw.icon, raw.side, {...states.value});
  _observations.add({
    'suite': h.suite.name,
    'light': h.light,
    'nullTheme': h.nullTheme,
    'state': state,
    'original': original,
    'focus': focus.hasFocus,
    'actualNativeWidgetStates': result.nativeStates.map((e) => e.name).toList(),
    ...result.json(),
  });
  if (down != null) {
    await down.cancel();
    await frames(t, 40);
  }
  return result;
}

void _sameText(TextStyle a, TextStyle b) {
  expect(a.color, b.color);
  expect(a.fontFamily, b.fontFamily);
  expect(a.fontFamilyFallback, b.fontFamilyFallback);
  expect(a.fontSize, b.fontSize);
  expect(a.fontWeight, b.fontWeight);
  expect(a.height, b.height);
  expect(a.letterSpacing, b.letterSpacing);
}

void main() {
  setUpAll(loadFonts);
  tearDownAll(() async {
    await (await File(
      Platform.environment['STARBRIDGE_3GK_OBSERVATIONS'] ??
          '${visualOutputDir('3gk-validation-current-20261018', legacySubdirectory: '')}/native-style-observations.json',
    ).create(recursive: true)).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'scope':
            'independent actual native observations; not product acceptance',
        'records': _observations,
      }),
    );
  });
  // Four positive controls reach the real native fallback before comparisons.
  for (final light in [false, true]) {
    for (final state in ['focus', 'pressed']) {
      testWidgets('3gk native null-state positive light=$light $state', (
        t,
      ) async {
        final h = _Harness(
          InteractionSuite.standard,
          light,
          nullTheme: true,
          candidate: false,
        );
        try {
          await h.mount(t);
          final actual = await _observe(t, h, state, original: true);
          // Read the default's scalar fallback, not a merge of the theme.
          final defaults = h.reference.defaultStyleOf(t.element(_nativeTarget));
          final states = actual.nativeStates;
          final color = defaults.foregroundColor!.resolve(states);
          expect(actual.text.color, color);
          expect(actual.icon, color);
          final font = defaults.textStyle!.resolve(states)!;
          expect(actual.text.fontSize, font.fontSize);
          expect(actual.text.letterSpacing, font.letterSpacing);
          expect(actual.side, defaults.side!.resolve(states));
          expect(t.takeException(), isNull);
        } finally {
          await h.dispose(t);
        }
      });
    }
  }
  for (final suite in InteractionSuite.values) {
    for (final light in [false, true]) {
      for (final state in ['idle', 'focus', 'pressed']) {
        testWidgets('3gk independent native $suite light=$light $state', (
          t,
        ) async {
          final h = _Harness(suite, light);
          try {
            await h.mount(t);
            final native = await _observe(t, h, state, original: true);
            final candidate = await _observe(t, h, state, original: false);
            _sameText(candidate.text, native.text);
            expect(candidate.icon, native.icon);
            // The native Material now exists in every suite. NonStandard's
            // approved transparent native stroke is separate from local FX.
            if (suite == InteractionSuite.standard) {
              expect(candidate.side, native.side);
            } else {
              expect(candidate.side, BorderSide.none);
            }
            expect(t.takeException(), isNull);
          } finally {
            await h.dispose(t);
          }
        });
      }
      for (final state in ['focus', 'pressed']) {
        testWidgets('3gk independent null-state $suite light=$light $state', (
          t,
        ) async {
          final h = _Harness(suite, light, nullTheme: true);
          try {
            await h.mount(t);
            final native = await _observe(t, h, state, original: true);
            final candidate = await _observe(t, h, state, original: false);
            _sameText(candidate.text, native.text);
            expect(candidate.icon, native.icon);
            if (suite == InteractionSuite.standard) {
              expect(candidate.side, native.side);
            } else {
              expect(candidate.side, BorderSide.none);
            }
            expect(t.takeException(), isNull);
          } finally {
            await h.dispose(t);
          }
        });
      }
    }
  }
}
