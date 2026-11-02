import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/communities_module.dart';
import 'package:starbridge_flutter/features/communities/community_creation_port.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_profile_dialog.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../_support/visual_output_dir.dart';
import '../../features/communities/community_creation_dialog_test.dart'
    show FormPort;
import '../../features/communities/community_profile_dialog_test.dart'
    show WorkspaceEditorPort;
import '../../features/communities/community_workspace_test.dart'
    show mediaChunk;
import '../../features/communities/community_image_test_support.dart'
    show settleCommunityImages;
import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;
import 'interaction_batch3fv_directory_test.dart' show frames, changed;
import 'interaction_batch3gb_logs_presets_test.dart' show actTarget;

final _review = visualOutputDir(
  'interaction_motion_batch3gc_20261017',
  legacySubdirectory: 'review',
);

class _Port extends WorkspaceEditorPort {
  Completer<CommunityCreationOptions>? optionsGate;
  Completer<Map<String, Object?>>? mediaGate;
  Completer<String>? cropGate;
  int optionsReads = 0;
  final mediaCalls = <(String, String, int, String?)>[];
  final cropCalls = <(String, double, double, double)>[];
  void optionsDone() {
    final pending = optionsGate!;
    optionsGate = null;
    pending.complete(super.creationOptions());
  }

  void mediaDone() {
    final pending = mediaGate!;
    mediaGate = null;
    pending.complete(
      mediaChunk(base64Decode(FormPort.image.split(',').last), 0, kind: 'logo'),
    );
  }

  @override
  Future<CommunityCreationOptions> creationOptions() {
    optionsReads++;
    return optionsGate?.future ?? super.creationOptions();
  }

  @override
  Future<Map<String, Object?>> readMedia(
    String targetRef,
    String kind, {
    String? memberRef,
    required int offset,
    String? version,
  }) {
    mediaCalls.add((targetRef, kind, offset, version));
    return mediaGate?.future ??
        super.readMedia(
          targetRef,
          kind,
          memberRef: memberRef,
          offset: offset,
          version: version,
        );
  }

  @override
  Future<String> cropLogo(String ref, double x, double y, double size) {
    cropCalls.add((ref, x, y, size));
    return cropGate?.future ?? Future.value(FormPort.image);
  }
}

class _Probe {
  _Probe(this.suite, this.kind, {this.large = false, this.light = false});
  final port = _Port();
  final capture = GlobalKey();
  final InteractionSuite suite;
  final String kind;
  bool large, light, reduce = false;
  late StateSetter update;
  Object? result;
  SemanticsHandle? semantics;
  Widget app() => RepaintBoundary(
    key: capture,
    child: StatefulBuilder(
      builder: (context, set) {
        update = set;
        final base = scopedApp(
          Builder(
            builder: (context) => StarBridgeActionButton(
              controlKey: const Key('open-profile-media'),
              onActivate: (_) async {
                result = await showStarBridgeDialog<Object?>(
                  context,
                  barrierDismissible: false,
                  builder: (_) => kind == 'crop'
                      ? CommunityLogoCrop(
                          port: port,
                          source: const CommunityLogoSource(
                            'crop-source',
                            FormPort.image,
                            300,
                            200,
                          ),
                        )
                      : CommunityProfileDialog(port: port, targetRef: 'a' * 32),
                );
              },
              child: const Text('Open'),
            ),
          ),
          suite,
          reduce: reduce,
          light: light,
        ) as MaterialApp;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: base.theme,
          themeAnimationDuration: Duration.zero,
          locale: base.locale,
          supportedLocales: base.supportedLocales,
          localizationsDelegates: base.localizationsDelegates,
          home: base.home,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
            child: base.builder!(context, child),
          ),
        );
      },
    ),
  );
  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await port.changes.close();
    semantics?.dispose();
    semantics = null;
    expect(t.takeException(), isNull);
  }
}

// ignore: library_private_types_in_public_api
Future<void> open(WidgetTester t, _Probe p, String source) async {
  p.semantics = t.ensureSemantics();
  size(t, const Size(1200, 1100));
  await t.pumpWidget(p.app());
  await frames(t);
  await actKey(t, const Key('open-profile-media'), source);
  await frames(t);
}

Finder marker(String phase) => find.byKey(ValueKey('profile-$phase-activity'));
Future<void> actKey(WidgetTester t, Key key, String source) => actTarget(
  t,
  find
      .ancestor(
        of: find.byKey(key),
        matching: find.byType(StarBridgeActionButton),
      )
      .first,
  source,
);
void waiting(WidgetTester t, String phase, {required bool animated}) {
  expect(marker(phase), findsOneWidget);
  final busy = find.descendant(
    of: marker(phase),
    matching: find.byType(SuiteBusyFrame),
  );
  expect(busy, findsOneWidget);
  expect(InteractionScope.of(t.element(busy)).reduceMotion, !animated);
}

void main() {
  setUpAll(loadFonts);
  testWidgets('3gc held options have static keyboard feedback', (t) async {
    final p = _Probe(InteractionSuite.standard, 'options');
    p.port.optionsGate = Completer();
    await open(t, p, 'keyboard');
    waiting(t, 'options', animated: false);
    expect(p.port.optionsReads, 1);
    await p.clean(t);
  });
  testWidgets('3gc held crop has static keyboard feedback', (t) async {
    final p = _Probe(InteractionSuite.standard, 'crop');
    p.port.cropGate = Completer();
    await open(t, p, 'pointer');
    await t.pumpAndSettle();
    await actKey(t, const Key('community-crop-apply'), 'keyboard');
    await frames(t);
    waiting(t, 'crop', animated: false);
    expect(p.port.cropCalls, [('crop-source', 1 / 6, 0.0, 1.0)]);
    await p.clean(t);
  });
  moreCases();
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
    for (final phase in ['options', 'logo']) {
      testWidgets('3gc $suite invalidation retires $phase before late read', (
        t,
      ) async {
        final p = _Probe(suite, phase);
        if (phase == 'options') {
          p.port.optionsGate = Completer();
        } else {
          p.port.mediaGate = Completer();
        }
        await open(t, p, 'pointer');
        waiting(t, phase, animated: true);
        p.port.changes.add(null);
        await frames(t);
        expect(find.byType(CommunityProfileDialog), findsNothing);
        if (phase == 'options') {
          p.port.optionsDone();
        } else {
          p.port.mediaDone();
        }
        await frames(t);
        expect(find.byType(CommunityProfileDialog), findsNothing);
        expect(p.port.saves, isEmpty);
        expect(p.port.writes, isEmpty);
        await p.clean(t);
      });
    }
    testWidgets('3gc $suite crop cancel has no crop or persistence', (t) async {
      final p = _Probe(suite, 'crop');
      await open(t, p, 'pointer');
      await t.pumpAndSettle();
      await actKey(t, const Key('community-crop-cancel'), 'reader');
      await frames(t, 40);
      expect(find.byType(CommunityLogoCrop), findsNothing);
      expect(p.result, isNull);
      expect(p.port.cropCalls, isEmpty);
      expect(p.port.saves, isEmpty);
      expect(p.port.writes, isEmpty);
      await p.clean(t);
    });
    testWidgets('3gc $suite logo failure keeps profile and stops waiting', (
      t,
    ) async {
      final p = _Probe(suite, 'logo');
      p.port.mediaGate = Completer();
      await open(t, p, 'pointer');
      p.port.mediaGate!.completeError(const CommunityFailure('unavailable'));
      await frames(t);
      final state = t.state<CommunityProfileDialogState>(
        find.byType(CommunityProfileDialog),
      );
      expect(state.logoFailed, isTrue);
      expect(state.localError, 'imageFailed');
      expect(state.model.profile, isNotNull);
      expect(marker('logo'), findsNothing);
      expect(p.port.saves, isEmpty);
      await p.clean(t);
    });
    testWidgets(
      '3gc $suite foreground crop pauses auxiliary options feedback',
      (t) async {
        final p = _Probe(suite, 'options');
        p.port.optionsGate = Completer();
        await open(t, p, 'pointer');
        await actKey(t, const Key('profile-pick-logo'), 'keyboard');
        await frames(t, 40);
        expect(find.byType(CommunityLogoCrop), findsOneWidget);
        final background = find.byKey(
          const ValueKey('profile-options-activity'),
          skipOffstage: false,
        );
        expect(background, findsOneWidget);
        final busy = find.descendant(
          of: background,
          matching: find.byType(SuiteBusyFrame),
          skipOffstage: false,
        );
        expect(InteractionScope.of(t.element(busy)).reduceMotion, isTrue);
        // The original workspace image decoder runs outside fake async. Let
        // its already-returned bytes decode before checking for stray loops.
        await settleCommunityImages(t);
        await t.pumpAndSettle();
        await actKey(t, const Key('community-crop-cancel'), 'keyboard');
        await frames(t, 40);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        waiting(t, 'options', animated: true);
        expect(p.port.cropCalls, isEmpty);
        expect(p.port.saves, isEmpty);
        p.port.optionsDone();
        await frames(t);
        await p.clean(t);
      },
    );
    for (final source in ['pointer', 'keyboard', 'reader']) {
      for (final phase in ['options', 'logo', 'crop']) {
        testWidgets(
          '3gc $suite $source $phase live preference and completion',
          (t) async {
            final p = _Probe(suite, phase);
            if (phase == 'options') p.port.optionsGate = Completer();
            if (phase == 'logo') p.port.mediaGate = Completer();
            if (phase == 'crop') p.port.cropGate = Completer();
            await open(t, p, phase == 'crop' ? 'pointer' : source);
            if (phase == 'crop') {
              await t.pumpAndSettle();
              await actKey(t, const Key('community-crop-apply'), source);
              await frames(t);
              expect(p.port.cropCalls, [('crop-source', 1 / 6, 0.0, 1.0)]);
              for (final key in [
                'community-crop-apply',
                'community-crop-cancel',
              ]) {
                final button = t.widget<StarBridgeActionButton>(
                  find
                      .ancestor(
                        of: find.byKey(Key(key)),
                        matching: find.byType(StarBridgeActionButton),
                      )
                      .first,
                );
                expect(button.onActivate, isNull);
              }
              expect(
                t
                    .widgetList<Slider>(find.byType(Slider))
                    .every((s) => s.onChanged == null),
                isTrue,
              );
            }
            waiting(t, phase, animated: source == 'pointer');
            if (phase != 'crop') {
              final state = t.state<CommunityProfileDialogState>(
                find.byType(CommunityProfileDialog),
              );
              expect(state.model.fields['description'], 'Original');
              expect(state.model.dirty, isFalse);
            }
            p.update(() => p.reduce = true);
            await frames(t, 2);
            waiting(t, phase, animated: false);
            p.update(() => p.reduce = false);
            await frames(t, 2);
            waiting(t, phase, animated: source == 'pointer');
            if (phase == 'options') {
              expect(p.port.optionsReads, 1);
              p.port.optionsDone();
            }
            if (phase == 'logo') {
              expect(p.port.mediaCalls, [('a' * 32, 'logo', 0, null)]);
              p.port.mediaDone();
            }
            if (phase == 'crop') p.port.cropGate!.complete(FormPort.image);
            await frames(t, 50);
            expect(marker(phase), findsNothing);
            expect(p.port.saves, isEmpty);
            expect(p.port.writes, isEmpty);
            if (phase == 'crop') expect(p.result, FormPort.image);
            await p.clean(t);
          },
        );
      }
    }
    for (final source in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '3gc $suite options failure explicit $source retry keeps draft',
        (t) async {
          final p = _Probe(suite, 'options');
          p.port.optionsGate = Completer();
          await open(t, p, 'pointer');
          p.port.optionsGate!.completeError(
            const CommunityFailure('unavailable'),
          );
          await frames(t);
          final state = t.state<CommunityProfileDialogState>(
            find.byType(CommunityProfileDialog),
          );
          final field = find.byKey(
            ValueKey('profile-${state.serial}-description'),
          );
          await t.ensureVisible(field);
          await t.enterText(field, 'Keep unsaved description');
          await frames(t);
          expect(state.model.dirty, isTrue);
          expect(state.optionsFailed, isTrue);
          p.port.optionsGate = Completer();
          await actKey(t, const Key('profile-options-retry'), source);
          await frames(t);
          waiting(t, 'options', animated: source == 'pointer');
          expect(p.port.optionsReads, 2);
          expect(state.model.fields['description'], 'Keep unsaved description');
          p.port.optionsDone();
          await frames(t);
          expect(state.optionsFailed, isFalse);
          expect(state.model.dirty, isTrue);
          expect(p.port.saves, isEmpty);
          await p.clean(t);
        },
      );
      testWidgets('3gc $suite crop failure explicit $source retry one result', (
        t,
      ) async {
        final p = _Probe(suite, 'crop');
        p.port.cropGate = Completer();
        await open(t, p, 'pointer');
        await t.pumpAndSettle();
        await actKey(t, const Key('community-crop-apply'), 'pointer');
        await frames(t);
        p.port.cropGate!.completeError(StateError('synthetic crop failure'));
        await frames(t);
        expect(marker('crop'), findsNothing);
        expect(p.result, isNull);
        expect(p.port.cropCalls, hasLength(1));
        p.port.cropGate = Completer();
        await actKey(t, const Key('community-crop-apply'), source);
        await frames(t);
        waiting(t, 'crop', animated: source == 'pointer');
        expect(p.port.cropCalls, hasLength(2));
        p.port.cropGate!.complete(FormPort.image);
        await frames(t, 50);
        expect(p.result, FormPort.image);
        expect(p.port.saves, isEmpty);
        expect(p.port.writes, isEmpty);
        await p.clean(t);
      });
      testWidgets(
        '3gc $suite logo reload follows $source not previous opening',
        (t) async {
          final p = _Probe(suite, 'logo');
          p.port.mediaGate = Completer();
          await open(t, p, 'pointer');
          p.port.mediaDone();
          await frames(t);
          p.port.profile['profileRevision'] = 8;
          p.port.mediaGate = Completer();
          await actKey(t, const Key('profile-reload'), source);
          await frames(t);
          waiting(t, 'logo', animated: source == 'pointer');
          expect(p.port.mediaCalls, hasLength(2));
          p.port.mediaDone();
          await frames(t);
          expect(marker('logo'), findsNothing);
          expect(p.port.saves, isEmpty);
          await p.clean(t);
        },
      );
    }
    testWidgets('3gc $suite passive lease logo stays static with draft', (
      t,
    ) async {
      final p = _Probe(suite, 'logo');
      p.port.mediaGate = Completer();
      await open(t, p, 'pointer');
      p.port.mediaDone();
      await frames(t);
      final state = t.state<CommunityProfileDialogState>(
        find.byType(CommunityProfileDialog),
      );
      final field = find.byKey(ValueKey('profile-${state.serial}-description'));
      await t.ensureVisible(field);
      await t.enterText(field, 'Unsaved');
      await frames(t);
      p.port.profile['profileRevision'] = 8;
      p.port.mediaGate = Completer();
      await state.model.refreshLease();
      await frames(t);
      waiting(t, 'logo', animated: false);
      expect(state.model.fields['description'], 'Unsaved');
      expect(state.model.dirty, isTrue);
      p.port.mediaDone();
      await frames(t);
      await p.clean(t);
    });
    for (final phase in ['options', 'logo', 'crop']) {
      testWidgets('3gc $suite $phase late completion after disposal', (
        t,
      ) async {
        final p = _Probe(suite, phase);
        if (phase == 'options') p.port.optionsGate = Completer();
        if (phase == 'logo') p.port.mediaGate = Completer();
        if (phase == 'crop') p.port.cropGate = Completer();
        await open(t, p, 'pointer');
        if (phase == 'crop') {
          await t.pumpAndSettle();
          await actKey(t, const Key('community-crop-apply'), 'pointer');
          await frames(t);
        }
        await t.pumpWidget(const SizedBox());
        if (phase == 'options') p.port.optionsDone();
        if (phase == 'logo') p.port.mediaDone();
        if (phase == 'crop') p.port.cropGate!.complete(FormPort.image);
        await frames(t);
        expect(p.result, isNull);
        expect(p.port.saves, isEmpty);
        expect(p.port.writes, isEmpty);
        await p.port.changes.close();
        p.semantics?.dispose();
        p.semantics = null;
        expect(t.takeException(), isNull);
      });
      testWidgets('3gc $suite review $phase bounded feedback and live reduce', (
        t,
      ) async {
        final p = _Probe(
          suite,
          phase,
          large: true,
          light:
              suite == InteractionSuite.rail || suite == InteractionSuite.glow,
        );
        if (phase == 'options') p.port.optionsGate = Completer();
        if (phase == 'logo') p.port.mediaGate = Completer();
        if (phase == 'crop') p.port.cropGate = Completer();
        await open(t, p, 'pointer');
        if (phase == 'crop') {
          await t.pumpAndSettle();
          await actKey(t, const Key('community-crop-apply'), 'pointer');
          await frames(t);
        }
        await t.ensureVisible(marker(phase));
        await frames(t);
        final rect = t.getRect(marker(phase));
        final a = await pixels(t, p, rect, png: '$phase-${suite.name}');
        var maxChange = 0;
        for (final interval in [80, 128, 256]) {
          await t.pump(Duration(milliseconds: interval));
          final b = await pixels(t, p, rect);
          final count = changed(a, b);
          if (count > maxChange) maxChange = count;
        }
        expect(maxChange, greaterThan(0));
        p.update(() => p.reduce = true);
        await frames(t, 2);
        final c = await pixels(t, p, rect);
        await frames(t, 38);
        final d = await pixels(t, p, rect);
        expect(changed(c, d), 0);
        expect(t.getRect(marker(phase)), rect);
        File('$_review/$phase-${suite.name}.json').writeAsStringSync(
          jsonEncode({
            'movingPixels': maxChange,
            'staticPixels': changed(c, d),
            'rect': [rect.left, rect.top, rect.width, rect.height],
          }),
        );
        await p.clean(t);
      });
    }
  }
}
