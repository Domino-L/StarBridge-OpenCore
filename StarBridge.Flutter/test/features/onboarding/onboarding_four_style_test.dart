import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/app/preferences/in_memory_app_preferences.dart';
import 'package:starbridge_flutter/app/runtime/application_behavior_prompt.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_interaction_theme.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/onboarding/app_behavior_choice_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_controller.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_models.dart';
import 'package:starbridge_flutter/features/onboarding/onboarding_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import 'onboarding_test_support.dart';

// First-use setup steps and the existing-user startup/close prompt across
// the four interaction suites (Standard/Scan dark, Rail/Glow light), zh-CN
// at 1.5× text, 1200×1100. Findings are collected into a report (one batch
// run, no early stop) rather than failing on the first problem: buttons not
// rendered through the suite, overflow, hover with no visible response and
// reduce-motion instability. Screenshots go next to the report.
final _review = visualOutputDir('onboarding_four_style_20261024');
final _findings = <Map<String, Object?>>[];

bool _light(InteractionSuite s) =>
    s == InteractionSuite.rail || s == InteractionSuite.glow;

const _capture = Key('onboarding-four-style-capture');

Widget _app(InteractionSuite suite, Widget home, {bool reduce = false}) {
  const locale = Locale('zh', 'CN');
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    themeAnimationDuration: Duration.zero,
    locale: locale,
    supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    localizationsDelegates: const [
      AppStringsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: buildStarBridgeTheme(
      FutureRestraintStyle.resolve(
        _light(suite) ? AppearanceMode.light : AppearanceMode.dark,
      ).withReducedMotion(reduce),
      locale,
      interactionSuite: suite,
    ),
    builder: (context, child) => StarBridgeInteractionConfiguration(
      suite: suite,
      reduceMotion: reduce,
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: RepaintBoundary(key: _capture, child: child!),
      ),
    ),
    home: home,
  );
}

void _size(WidgetTester t) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(1200, 1100);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

InMemoryAppPreferences _prefs() {
  final prefs = InMemoryAppPreferences(
    initial: AppPreferences.defaults.copyWith(
      applicationBehavior: ApplicationBehaviorPreferences.defaults.copyWith(
        startupChoiceMade: false,
        closeBehaviorChoiceMade: false,
      ),
    ),
  );
  addTearDown(prefs.dispose);
  return prefs;
}

Future<void> _mountStep(
  WidgetTester t,
  InteractionSuite suite,
  OnboardingStep step, {
  bool reduce = false,
}) async {
  _size(t);
  final mode = switch (step) {
    OnboardingStep.online => OnboardingMode.online,
    OnboardingStep.welcome || OnboardingStep.mode => null,
    _ => OnboardingMode.local,
  };
  // Steps after identity need a confirmed identity, or the controller
  // (correctly) sends the page back to the identity step.
  final pastIdentity = step.index > OnboardingStep.identity.index;
  final fake = FakeOnboardingPort(
    facts(activeMode: mode ?? OnboardingMode.local, confirmed: pastIdentity),
  );
  if (mode == OnboardingMode.online) {
    await fake.execute(
      OnboardingAction.applyMode,
      const OnboardingCheckpoint(mode: OnboardingMode.online),
    );
    fake.actions.clear();
  }
  fake.restored = OnboardingCheckpoint(
    step: step,
    mode: mode,
    sourceKey: fake.facts.sourceKey,
    evidenceKey: fake.facts.evidenceKey,
  );
  final controller = OnboardingController(fake);
  addTearDown(controller.dispose);
  final behavior = AppBehaviorChoiceController(_prefs());
  addTearDown(behavior.dispose);
  await t.pumpWidget(
    _app(
      suite,
      OnboardingPage(
        controller: controller,
        onClose: () {},
        appBehavior: behavior,
      ),
      reduce: reduce,
    ),
  );
  await t.pumpAndSettle();
}

Future<List<int>> _pixels(WidgetTester t, Rect rect) async {
  final boundary =
      t.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  final image = await t.runAsync(() => boundary.toImage());
  final data = await t.runAsync(
    () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  final bytes = data!.buffer.asUint8List();
  final r = rect.intersect(
    Offset.zero & Size(image!.width.toDouble(), image.height.toDouble()),
  );
  final out = <int>[];
  for (var y = r.top.floor(); y < r.bottom.floor(); y++) {
    for (var x = r.left.floor(); x < r.right.floor(); x++) {
      final i = (y * image.width + x) * 4;
      out.addAll(bytes.sublist(i, i + 4));
    }
  }
  image.dispose();
  return out;
}

int _changed(List<int> a, List<int> b) {
  var n = 0;
  for (var i = 0; i + 2 < a.length && i + 2 < b.length; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
  }
  return n;
}

Future<void> _save(WidgetTester t, String name) async {
  final boundary =
      t.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$_review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

String _label(Element e) {
  final texts = <String>[];
  void visit(Element el) {
    final w = el.widget;
    if (w is Text && w.data != null) texts.add(w.data!);
    el.visitChildren(visit);
  }

  visit(e);
  return texts.join(' ').trim();
}

/// Records buttons that bypass the suite: raw Material buttons outside any
/// StarBridgeActionButton, and (non-Standard) action buttons with no
/// SuitePressable face.
void _auditButtons(WidgetTester t, InteractionSuite suite, String where) {
  final raw = find.byWidgetPredicate(
    (w) =>
        w is ButtonStyleButton ||
        w is IconButton ||
        w is InkWell && w.onTap != null,
  );
  for (final element in raw.evaluate()) {
    var inside = false;
    element.visitAncestorElements((a) {
      if (a.widget is StarBridgeActionButton || a.widget is SuitePressable) {
        inside = true;
        return false;
      }
      return true;
    });
    if (!inside) {
      _findings.add({
        'kind': 'raw-button',
        'suite': suite.name,
        'where': where,
        'widget': element.widget.runtimeType.toString(),
        'label': _label(element),
      });
    }
  }
  if (suite == InteractionSuite.standard) return;
  for (final element in find.byType(StarBridgeActionButton).evaluate()) {
    final faces = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(SuitePressable),
    );
    if (faces.evaluate().isEmpty) {
      _findings.add({
        'kind': 'no-suite-face',
        'suite': suite.name,
        'where': where,
        'label': _label(element),
      });
    }
  }
}

void _recordException(WidgetTester t, InteractionSuite suite, String where) {
  final error = t.takeException();
  if (error != null) {
    _findings.add({
      'kind': 'exception',
      'suite': suite.name,
      'where': where,
      'error': error.toString().split('\n').first,
    });
  }
}

Future<void> _hover(
  WidgetTester t,
  InteractionSuite suite,
  String where,
  Finder target,
) async {
  if (target.evaluate().isEmpty) return;
  final rect = t.getRect(target.first).inflate(4);
  final before = await _pixels(t, rect);
  final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: const Offset(1, 1));
  await mouse.moveTo(t.getCenter(target.first));
  await t.pumpAndSettle();
  final n = _changed(before, await _pixels(t, rect));
  if (n == 0) {
    _findings.add({'kind': 'no-hover', 'suite': suite.name, 'where': where});
  }
  await mouse.removePointer();
  await t.pumpAndSettle();
}

const _steps = [
  OnboardingStep.welcome,
  OnboardingStep.mode,
  OnboardingStep.log,
  OnboardingStep.identity,
  OnboardingStep.local,
  OnboardingStep.online,
  OnboardingStep.verify,
  OnboardingStep.summary,
];

void main() {
  setUpAll(() async {
    for (final font in {
      'Source Sans 3': 'assets/fonts/SourceSans3VF-Upright.ttf',
      'Saira': 'assets/fonts/Saira-VF.ttf',
      'Rajdhani': 'assets/fonts/Rajdhani-SemiBold.ttf',
      'Source Han Sans CN': 'assets/fonts/SourceHanSansCN-VF.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  tearDownAll(() async {
    final file = File('$_review/findings.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_findings),
    );
    // ignore: avoid_print
    print('FINDINGS ${_findings.length} -> ${file.path}');
  });

  for (final suite in InteractionSuite.values) {
    group('${suite.name} (${_light(suite) ? 'light' : 'dark'})', () {
      for (final step in _steps) {
        testWidgets('step ${step.name}', (t) async {
          await _mountStep(t, suite, step);
          final where = 'step.${step.name}';
          if (find.byKey(const Key('onboarding-page')).evaluate().isEmpty) {
            _findings.add({
              'kind': 'not-rendered',
              'suite': suite.name,
              'where': where,
            });
          }
          _recordException(t, suite, where);
          _auditButtons(t, suite, where);
          await _save(t, '${suite.name}-${step.name}');
          await _hover(
            t,
            suite,
            '$where/next',
            find.byKey(const Key('onboarding-next')),
          );
          _recordException(t, suite, '$where/hover');
        });
      }

      testWidgets('reduce motion on the welcome step', (t) async {
        await _mountStep(t, suite, OnboardingStep.welcome, reduce: true);
        final next = find.byKey(const Key('onboarding-next'));
        if (next.evaluate().isEmpty) return;
        final rect = t.getRect(next).inflate(4);
        final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
        addTearDown(mouse.removePointer);
        await mouse.addPointer(location: const Offset(1, 1));
        await mouse.moveTo(t.getCenter(next));
        await t.pump();
        await t.pump();
        final early = await _pixels(t, rect);
        await t.pump(const Duration(milliseconds: 608));
        final n = _changed(early, await _pixels(t, rect));
        if (n != 0) {
          _findings.add({
            'kind': 'reduce-unstable',
            'suite': suite.name,
            'pixels': n,
          });
        }
      });

      testWidgets('existing-user startup and close prompt', (t) async {
        _size(t);
        final prefs = _prefs();
        await t.pumpWidget(
          _app(
            suite,
            Scaffold(body: Builder(builder: (_) => const SizedBox.expand())),
          ),
        );
        await t.pumpAndSettle();
        unawaited(
          showApplicationBehaviorPrompt(
            t.element(find.byType(Scaffold)),
            prefs,
          ),
        );
        await t.pumpAndSettle();
        _recordException(t, suite, 'behaviorPrompt');
        _auditButtons(t, suite, 'behaviorPrompt');
        await _save(t, '${suite.name}-behavior-prompt');
        await _hover(
          t,
          suite,
          'behaviorPrompt/later',
          find.byKey(const Key('app-behavior-prompt-later')),
        );
      });
    });
  }
}
