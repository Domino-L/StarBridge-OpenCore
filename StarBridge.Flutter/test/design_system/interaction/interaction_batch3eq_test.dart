import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_field_frame.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/starbridge_tokens.dart';
import 'package:starbridge_flutter/features/achievements/achievements_page.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../features/achievements/achievement_collection_controller_test.dart'
    show achievementTestAccount;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3eo_test.dart' show IdeasProbe, activate, key;
import 'interaction_batch3i_test.dart' show scopedApp;

Finder fieldFrame(Finder editor) =>
    find.ancestor(of: editor, matching: find.byType(SuiteFieldFrame)).first;

Widget validationApp(
  Widget child,
  InteractionSuite suite, {
  bool light = false,
  double scale = 1,
  Locale? locale,
}) {
  final base = scopedApp(child, suite, light: light) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: locale == null
        ? base.theme
        : buildStarBridgeTheme(
            base.theme!.extension<StarBridgeTokens>()!,
            locale,
            interactionSuite: suite,
          ),
    themeAnimationDuration: Duration.zero,
    locale: locale ?? base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: base.builder!(context, child),
    ),
    home: base.home,
  );
}

/// Render only the public foreground painter, not the native error border.
/// This proves the suite's own layer uses danger, rather than sampling the SDK.
Future<Color> edgeColor(WidgetTester t, Finder target) async {
  final frame = t.widget<SuiteFieldFrame>(target);
  final box = t.getSize(target);
  final rect = frame.boundsResolver!(box);
  final painted = find
      .descendant(
        of: target,
        matching: find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.foregroundPainter != null &&
              w.child is SizedBox,
        ),
      )
      .first;
  final painter = t.widget<CustomPaint>(painted).foregroundPainter!;
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), box);
  final picture = recorder.endRecording();
  return (await t.runAsync(() async {
    final image = await picture.toImage(box.width.ceil(), box.height.ceil());
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final at =
        (rect.center.dy.floor() * image.width + rect.left.ceil() + 1) * 4;
    final color = Color.fromARGB(
      bytes.getUint8(at + 3),
      bytes.getUint8(at),
      bytes.getUint8(at + 1),
      bytes.getUint8(at + 2),
    );
    image.dispose();
    picture.dispose();
    return color;
  }))!;
}

class NativeValidationHarness extends StatefulWidget {
  const NativeValidationHarness(
    this.suite, {
    this.follow = true,
    this.explicit = false,
    super.key,
  });
  final InteractionSuite suite;
  final bool follow, explicit;
  @override
  State<NativeValidationHarness> createState() => NativeValidationState();
}

class NativeValidationState extends State<NativeValidationHarness> {
  final form = GlobalKey<FormState>(), boundary = GlobalKey();
  GlobalKey<FormFieldState<String>> field = GlobalKey();
  final controller = TextEditingController(), focus = FocusNode();
  final revision = ValueNotifier(0);
  String? forced;
  bool errorWidget = false;
  AutovalidateMode auto = AutovalidateMode.disabled;
  int builds = 0, validations = 0;
  late var suite = widget.suite;
  bool reduce = false, light = false;

  void presentation(VoidCallback change) => setState(change);

  void nativeChange(VoidCallback change) {
    change();
    revision.value++;
  }

  @override
  void dispose() {
    revision.dispose();
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return scopedApp(
      Center(
        child: SizedBox(
          width: 300,
          child: Form(
            key: form,
            child: RepaintBoundary(
              key: boundary,
              child: StarBridgeFieldFrame(
                focusNode: focus,
                followNativeError: widget.follow,
                error: widget.explicit,
                builder: (_, f) => ValueListenableBuilder<int>(
                  valueListenable: revision,
                  builder: (_, _, _) => TextFormField(
                    key: field,
                    focusNode: f,
                    controller: controller,
                    showCursor: false,
                    maxLength: 24,
                    forceErrorText: forced,
                    autovalidateMode: auto,
                    decoration: const InputDecoration(
                      labelText: 'Original label',
                      helperText: 'Native helper',
                    ),
                    errorBuilder: errorWidget
                        ? (_, text) => Text('Native error widget: $text')
                        : null,
                    validator: (value) {
                      validations++;
                      return value?.trim().isEmpty == true
                          ? 'Required value'
                          : null;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      suite,
      reduce: reduce,
      light: light,
    );
  }
}

Future<Color> renderedEdge(WidgetTester t, NativeValidationState state) async {
  final target = find.byType(SuiteFieldFrame);
  final frame = t.widget<SuiteFieldFrame>(target);
  final rect = frame.boundsResolver!(t.getSize(target));
  return (await t.runAsync(() async {
    final image =
        await (state.boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final at =
        (rect.center.dy.floor() * image.width + rect.left.ceil() + 2) * 4;
    final color = Color.fromARGB(
      bytes.getUint8(at + 3),
      bytes.getUint8(at),
      bytes.getUint8(at + 1),
      bytes.getUint8(at + 2),
    );
    image.dispose();
    return color;
  }))!;
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final locale in [
      const Locale('zh', 'CN'),
      const Locale('zh', 'TW'),
      const Locale('en', 'US'),
    ]) {
      testWidgets(
        '$suite $locale validation text is not ellipsized at 380px and 1.5x text',
        (t) async {
          size(t, const Size(380, 1000));
          final account = ValueNotifier(achievementTestAccount(7));
          final ideas = IdeasProbe();
          try {
            await t.pumpWidget(
              validationApp(
                AchievementsPage(account: account, ideas: ideas),
                suite,
                scale: 1.5,
                locale: locale,
              ),
            );
            await t.pumpAndSettle();
            await activate(t, key('achievement-contribute'), 'pointer');
            await t.pumpAndSettle();
            await activate(t, key('achievement-idea-submit'), 'pointer');
            await t.pumpAndSettle();
            for (final name in [
              'achievement-idea-name',
              'achievement-idea-condition',
            ]) {
              final error = t
                  .state<FormFieldState<String>>(key(name))
                  .errorText!;
              final paragraph = t.renderObject<RenderParagraph>(
                find.text(error),
              );
              expect(paragraph.didExceedMaxLines, isFalse);
              final frame = t.widget<SuiteFieldFrame>(fieldFrame(key(name)));
              expect(
                frame.boundsResolver!(t.getSize(fieldFrame(key(name)))).height,
                lessThan(t.getSize(fieldFrame(key(name))).height),
              );
            }
            expect(ideas.receipts, isEmpty);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox());
            account.dispose();
          }
        },
      );
    }

    testWidgets(
      '$suite native IME, selection and validation survive all live presentation settings',
      (t) async {
        size(t, const Size(800, 800));
        final host = GlobalKey<NativeValidationState>();
        await t.pumpWidget(NativeValidationHarness(suite, key: host));
        await t.pumpAndSettle();
        final s = host.currentState!;
        s.nativeChange(() => s.forced = 'Original native error');
        await t.pumpAndSettle();
        await t.tap(find.byKey(s.field));
        await t.pumpAndSettle();
        const value = TextEditingValue(
          text: '正在输入星海',
          selection: TextSelection(baseOffset: 1, extentOffset: 4),
          composing: TextRange(start: 1, end: 4),
        );
        t.testTextInput.updateEditingValue(value);
        await t.pump();
        final editor = t.state<EditableTextState>(find.byType(EditableText));
        final native = s.field.currentState;
        for (final next in InteractionSuite.values) {
          s.presentation(() {
            s.suite = next;
            s.reduce = !s.reduce;
            s.light = !s.light;
          });
          await t.pump();
          await t.pump();
          expect(
            t.state<EditableTextState>(find.byType(EditableText)),
            same(editor),
          );
          expect(s.field.currentState, same(native));
          expect(s.field.currentState!.hasError, isTrue);
          expect(s.controller.value, value);
          expect(s.focus.hasFocus, isTrue);
          expect(s.validations, 0);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite native validate/clear/reset repaints without rebuilding the frame owner',
      (t) async {
        size(t, const Size(800, 800));
        final host = GlobalKey<NativeValidationState>();
        await t.pumpWidget(NativeValidationHarness(suite, key: host));
        await t.pumpAndSettle();
        final s = host.currentState!;
        final state = s.field.currentState;
        final frameState = t.state(find.byType(StarBridgeFieldFrame));
        final data = InteractionScope.of(
          t.element(find.byType(SuiteFieldFrame)),
        );
        final before = await renderedEdge(t, s);
        final builds = s.builds;
        expect(s.form.currentState!.validate(), isFalse);
        await t.pumpAndSettle();
        expect(s.field.currentState!.hasError, isTrue);
        expect(s.builds, builds);
        expect(s.validations, 1);
        if (suite != InteractionSuite.standard) {
          expect(before, isNot(data.palette.danger));
          expect(
            await edgeColor(t, find.byType(SuiteFieldFrame)),
            data.palette.danger,
          );
          expect(await renderedEdge(t, s), data.palette.danger);
        }
        expect(s.validations, 1); // paint never re-runs the validator.
        await t.enterText(find.byKey(s.field), 'Valid original');
        expect(s.form.currentState!.validate(), isTrue);
        await t.pumpAndSettle();
        expect(s.field.currentState, same(state));
        expect(t.state(find.byType(StarBridgeFieldFrame)), same(frameState));
        expect(s.builds, builds);
        if (suite != InteractionSuite.standard) {
          expect(
            await edgeColor(t, find.byType(SuiteFieldFrame)),
            isNot(data.palette.danger),
          );
          expect(await renderedEdge(t, s), isNot(data.palette.danger));
        }
        final calls = s.validations;
        s.form.currentState!.reset();
        await t.pumpAndSettle();
        expect(s.controller.text, isEmpty);
        expect(s.field.currentState!.hasError, isFalse);
        expect(s.validations, calls);
        expect(s.builds, builds);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite native forceErrorText and errorBuilder project independently of parent builds',
      (t) async {
        size(t, const Size(800, 800));
        final host = GlobalKey<NativeValidationState>();
        await t.pumpWidget(NativeValidationHarness(suite, key: host));
        await t.pumpAndSettle();
        final s = host.currentState!, builds = host.currentState!.builds;
        final editor = t.state<EditableTextState>(find.byType(EditableText));
        for (final custom in [false, true]) {
          s.nativeChange(() {
            s.forced = '';
            s.errorWidget = custom;
          });
          await t.pumpAndSettle();
          expect(s.field.currentState!.hasError, isTrue);
          expect(s.validations, 0);
          final frame = t.widget<SuiteFieldFrame>(find.byType(SuiteFieldFrame));
          frame.boundsResolver!(t.getSize(find.byType(SuiteFieldFrame)));
          expect(frame.errorResolver!(), isTrue);
          if (suite != InteractionSuite.standard) {
            expect(
              await edgeColor(t, find.byType(SuiteFieldFrame)),
              InteractionScope.of(t.element(find.byType(SuiteFieldFrame)))
                  .palette
                  .danger,
            );
          }
          s.nativeChange(() => s.forced = null);
          await t.pumpAndSettle();
          expect(s.field.currentState!.hasError, isFalse);
          expect(frame.errorResolver!(), isFalse);
          expect(
            t.state<EditableTextState>(find.byType(EditableText)),
            same(editor),
          );
        }
        expect(s.builds, builds);
        expect(s.validations, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite native autovalidate/rekey retains original validation owner',
      (t) async {
        size(t, const Size(800, 800));
        final host = GlobalKey<NativeValidationState>();
        await t.pumpWidget(NativeValidationHarness(suite, key: host));
        await t.pumpAndSettle();
        final s = host.currentState!, builds = host.currentState!.builds;
        s.nativeChange(() => s.auto = AutovalidateMode.onUserInteraction);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(s.field), 'Valid');
        await t.pumpAndSettle();
        await t.enterText(find.byKey(s.field), '');
        await t.pumpAndSettle();
        expect(s.field.currentState!.hasError, isTrue);
        if (suite != InteractionSuite.standard) {
          expect(
            await edgeColor(t, find.byType(SuiteFieldFrame)),
            InteractionScope.of(t.element(find.byType(SuiteFieldFrame)))
                .palette
                .danger,
          );
        }
        final oldEditor = t.state<EditableTextState>(find.byType(EditableText));
        s.nativeChange(() {
          s.field = GlobalKey();
          s.auto = AutovalidateMode.disabled;
        });
        await t.pumpAndSettle();
        expect(s.field.currentState!.hasError, isFalse);
        expect(
          t.state<EditableTextState>(find.byType(EditableText)),
          isNot(same(oldEditor)),
        );
        final frame = t.widget<SuiteFieldFrame>(find.byType(SuiteFieldFrame));
        frame.boundsResolver!(t.getSize(find.byType(SuiteFieldFrame)));
        expect(frame.errorResolver!(), isFalse);
        expect(s.builds, builds);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite native error projection is opt-in and explicit errors retain precedence',
      (t) async {
        size(t, const Size(800, 800));
        final host = GlobalKey<NativeValidationState>();
        await t.pumpWidget(
          NativeValidationHarness(
            suite,
            follow: false,
            explicit: true,
            key: host,
          ),
        );
        await t.pumpAndSettle();
        final s = host.currentState!;
        expect(s.field.currentState!.hasError, isFalse);
        final frame = t.widget<SuiteFieldFrame>(find.byType(SuiteFieldFrame));
        expect(frame.errorResolver, isNull);
        expect(frame.error, isTrue);
        if (suite != InteractionSuite.standard) {
          expect(
            await edgeColor(t, find.byType(SuiteFieldFrame)),
            InteractionScope.of(t.element(find.byType(SuiteFieldFrame)))
                .palette
                .danger,
          );
        }
        expect(s.validations, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$suite achievement fields project SDK validation and keep original editors',
      (t) async {
        size(t, const Size(1100, 950));
        final account = ValueNotifier(achievementTestAccount(7));
        final ideas = IdeasProbe();
        try {
          await t.pumpWidget(
            scopedApp(AchievementsPage(account: account, ideas: ideas), suite),
          );
          await t.pumpAndSettle();
          await activate(t, key('achievement-contribute'), 'pointer');
          await t.pumpAndSettle();
          final name = key('achievement-idea-name'),
              condition = key('achievement-idea-condition');
          final nameState = t.state<FormFieldState<String>>(name);
          final conditionState = t.state<FormFieldState<String>>(condition);
          final nameController = t.widget<TextFormField>(name).controller;
          final conditionController = t
              .widget<TextFormField>(condition)
              .controller;
          expect(fieldFrame(name), findsOneWidget);
          expect(fieldFrame(condition), findsOneWidget);
          await activate(t, key('achievement-idea-submit'), 'pointer');
          await t.pumpAndSettle();
          expect(nameState.hasError, isTrue);
          expect(conditionState.hasError, isTrue);
          expect(ideas.receipts, isEmpty);
          for (final target in [name, condition]) {
            final frame = fieldFrame(target);
            final bounds = t.widget<SuiteFieldFrame>(frame).boundsResolver!(
              t.getSize(frame),
            );
            expect(bounds.height, lessThan(t.getSize(frame).height));
            if (suite != InteractionSuite.standard) {
              expect(
                await edgeColor(t, frame),
                InteractionScope.of(t.element(frame)).palette.danger,
              );
            }
          }
          await t.enterText(name, 'My voyage');
          await t.enterText(condition, 'Visit another system');
          await activate(t, key('achievement-idea-submit'), 'keyboard');
          await t.pump();
          expect(nameState.hasError, isFalse);
          expect(conditionState.hasError, isFalse);
          expect(ideas.drafts, [(7, 'My voyage', 'Visit another system')]);
          expect(t.widget<SuiteFieldFrame>(fieldFrame(name)).enabled, isFalse);
          expect(
            t.widget<SuiteFieldFrame>(fieldFrame(condition)).enabled,
            isFalse,
          );
          expect(
            t.widget<TextFormField>(name).controller,
            same(nameController),
          );
          expect(
            t.widget<TextFormField>(condition).controller,
            same(conditionController),
          );
          expect(t.state<FormFieldState<String>>(name), same(nameState));
          expect(
            t.state<FormFieldState<String>>(condition),
            same(conditionState),
          );
          ideas.pending.complete();
          await t.pumpAndSettle();
          expect(nameController!.text, isEmpty);
          expect(conditionController!.text, isEmpty);
          expect(t.widget<SuiteFieldFrame>(fieldFrame(name)).enabled, isFalse);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          account.dispose();
        }
      },
    );
  }
}
