import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_dialog.dart';
import 'package:starbridge_flutter/features/communities/community_logo_crop.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_image_editor.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_images.dart';

import '../../features/friends/social_layout_test.dart' show loadFonts, size;
import 'interaction_batch3i_test.dart' show scopedApp;

const _image =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
const _source = CommunityLogoSource(
  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  _image,
  1,
  1,
);
const _editorKey = Key('image-flow-editor');

InteractionSource _origin(String input) =>
    input == 'pointer' ? InteractionSource.pointer : InteractionSource.keyboard;

/// External local-image seam only. The real editor, crop, routes and actions
/// retain all admission, private draft, confirmation and retirement behavior.
class _Port implements LocalHangarImagePort {
  bool allowed = true;
  String? currentImage;
  int reads = 0, picks = 0, crops = 0, saves = 0, restores = 0, clears = 0;
  final pickOrigins = <InteractionSource>[];
  final cropOrigins = <InteractionSource>[];
  final saveOrigins = <InteractionSource>[];
  final restoreOrigins = <InteractionSource>[];
  final cropArguments = <(String, double, double, double)>[];
  Completer<CommunityLogoSource?>? pickGate;
  Completer<String>? cropGate;
  Completer<void>? saveGate, restoreGate;

  @override
  bool get canPickLogo => allowed;

  @override
  Future<String?> readImage() async {
    reads++;
    return currentImage;
  }

  @override
  Future<CommunityLogoSource?> pickLogo() async {
    picks++;
    pickOrigins.add(currentStarBridgeActivationSource);
    return pickGate == null ? _source : await pickGate!.future;
  }

  @override
  Future<String> cropLogo(
    String reference,
    double x,
    double y,
    double side,
  ) async {
    crops++;
    cropOrigins.add(currentStarBridgeActivationSource);
    cropArguments.add((reference, x, y, side));
    return cropGate == null ? _image : await cropGate!.future;
  }

  @override
  Future<void> saveImage() async {
    saves++;
    saveOrigins.add(currentStarBridgeActivationSource);
    if (saveGate != null) {
      await saveGate!.future;
    }
    currentImage = _image;
  }

  @override
  Future<void> restoreImage() async {
    restores++;
    restoreOrigins.add(currentStarBridgeActivationSource);
    if (restoreGate != null) {
      await restoreGate!.future;
    }
    currentImage = null;
  }

  @override
  Future<void> clearLogo() async {
    clears++;
  }

  void release() {
    if (pickGate case final gate? when !gate.isCompleted) {
      gate.complete(null);
    }
    if (cropGate case final gate? when !gate.isCompleted) {
      gate.complete(_image);
    }
    if (saveGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
    if (restoreGate case final gate? when !gate.isCompleted) {
      gate.complete();
    }
  }
}

class _Probe {
  _Probe(this.suite, {String? initialImage}) {
    original.currentImage = initialImage;
    current = original;
  }
  final InteractionSuite suite;
  final original = _Port();
  late _Port current;
  final callbacks = <_Port>[];
  late StateSetter update;
  bool visible = true, editable = true;
  Widget app() => scopedApp(
    StatefulBuilder(
      builder: (_, setState) {
        update = setState;
        final shownPort = current;
        return visible
            ? SizedBox(
                width: 700,
                child: LocalHangarImageEditor(
                  key: _editorKey,
                  port: shownPort,
                  editable: editable,
                  onSaved: () => callbacks.add(shownPort),
                  fallback: const SizedBox(
                    width: 700,
                    height: 200,
                    child: Text('Catalog image'),
                  ),
                ),
              )
            : const Text('Editor left');
      },
    ),
    suite,
  );

  Future<void> close(WidgetTester t) async {
    original.release();
    if (!identical(current, original)) {
      current.release();
    }
    await _frames(t);
    await t.pumpWidget(const SizedBox.shrink());
    await _frames(t);
  }
}

Future<void> _frames(WidgetTester t, [int count = 2]) async {
  for (var i = 0; i < count; i++) {
    await t.pump();
  }
}

Future<void> _tail(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

bool _enabled(WidgetTester t, String key) {
  final adapter = find.ancestor(
    of: find.byKey(Key(key)),
    matching: find.byType(StarBridgeActionButton),
  );
  expect(adapter, findsOneWidget);
  return t.widget<StarBridgeActionButton>(adapter).onActivate != null;
}

/// Real Tab/Enter or the actual exposed semantics action; no direct callback.
/// The short post-action pumps deliberately preserve a reversing route so the
/// overlap regression can observe it before its exit animation completes.
Future<void> _act(WidgetTester t, String key, String input) async {
  final target = find.byKey(Key(key));
  expect(target, findsOneWidget);
  await t.ensureVisible(target);
  await _tail(t);
  if (input == 'keyboard') {
    final widget = t.widget(target);
    final FocusNode focus;
    if (widget is ButtonStyleButton) {
      focus = widget.focusNode!;
    } else {
      expect(widget, isA<SuitePressable>());
      final custom = widget as SuitePressable;
      focus =
          custom.focusNode ??
          t
              .widget<FocusableActionDetector>(
                find
                    .descendant(
                      of: target,
                      matching: find.byType(FocusableActionDetector),
                    )
                    .first,
              )
              .focusNode!;
    }
    expect(focus.canRequestFocus, isTrue);
    var tabs = 0;
    while (!focus.hasPrimaryFocus && tabs < 64) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await _frames(t);
      tabs++;
    }
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

StarBridgeDialogRoute<dynamic> _route(WidgetTester t, Finder content) =>
    ModalRoute.of(t.element(content))! as StarBridgeDialogRoute<dynamic>;

Finder _confirmation() => find.ancestor(
  of: find.byKey(const Key('hangar-image-confirm')),
  matching: find.byType(AlertDialog),
);

Future<_Probe> _mount(
  WidgetTester t,
  InteractionSuite suite, {
  String? initialImage,
}) async {
  size(t, const Size(1000, 1000));
  final probe = _Probe(suite, initialImage: initialImage);
  await t.pumpWidget(probe.app());
  await _frames(t);
  await _tail(t);
  expect(probe.original.reads, 1);
  expect(
    t.widget<LocalHangarImageEditor>(find.byKey(_editorKey)).port,
    same(probe.original),
  );
  return probe;
}

Future<StarBridgeDialogRoute<dynamic>> _openCrop(
  WidgetTester t,
  _Probe probe,
  String input,
) async {
  final port = probe.original;
  port.pickGate = Completer<CommunityLogoSource?>();
  await _act(t, 'hangar-image-choose', input);
  expect(port.picks, 1);
  expect(port.pickOrigins, [_origin(input)]);
  expect(port.pickGate!.isCompleted, isFalse);
  expect(find.byType(CommunityLogoCrop), findsNothing);
  expect(port.crops, 0);
  expect(port.saves, 0);
  expect(port.clears, 0);
  expect(probe.callbacks, isEmpty);
  expect(_enabled(t, 'hangar-image-choose'), isFalse);
  // Resolve asynchronously only after the actual initiating command returned.
  port.pickGate!.complete(_source);
  await _frames(t);
  final crop = find.byType(CommunityLogoCrop);
  expect(crop, findsOneWidget);
  expect(t.widget<CommunityLogoCrop>(crop).port, same(port));
  expect(t.widget<CommunityLogoCrop>(crop).source, same(_source));
  final route = _route(t, crop);
  expect(route.instant, input != 'pointer');
  expect(port.reads, 1);
  expect(port.saves, 0);
  return route;
}

Future<StarBridgeDialogRoute<dynamic>> _cropToConfirmation(
  WidgetTester t,
  _Probe probe,
  String input,
) async {
  final port = probe.original;
  port.cropGate = Completer<String>();
  await _act(t, 'community-crop-apply', input);
  expect(port.crops, 1);
  expect(port.cropOrigins, [_origin(input)]);
  expect(port.cropArguments, [(_source.sourceRef, 0.0, 0.0, 1.0)]);
  expect(port.cropGate!.isCompleted, isFalse);
  expect(find.byType(CommunityLogoCrop), findsOneWidget);
  expect(_enabled(t, 'community-crop-apply'), isFalse);
  expect(_enabled(t, 'community-crop-cancel'), isFalse);
  expect(_confirmation(), findsNothing);
  expect(port.saves, 0);
  expect(probe.callbacks, isEmpty);
  port.cropGate!.complete(_image);
  await _frames(t);
  expect(_confirmation(), findsOneWidget);
  final route = _route(t, _confirmation());
  expect(route.instant, input != 'pointer');
  expect(port.saves, 0, reason: 'Cropping does not save the local ship image.');
  expect(port.clears, 0);
  expect(probe.callbacks, isEmpty);
  expect(find.textContaining('不会上传或对外分享'), findsOneWidget);
  return route;
}

Future<void> _beginSave(WidgetTester t, _Probe probe, String input) async {
  final port = probe.original;
  port.saveGate = Completer<void>();
  await _act(t, 'hangar-image-confirm', input);
  expect(port.saves, 1);
  expect(port.saveOrigins, [_origin(input)]);
  expect(port.saveGate!.isCompleted, isFalse);
  expect(port.currentImage, isNull);
  expect(port.clears, 0);
  expect(probe.callbacks, isEmpty);
  expect(_enabled(t, 'hangar-image-choose'), isFalse);
}

void main() {
  setUpAll(loadFonts);
  for (final suite in InteractionSuite.values) {
    for (final input in ['pointer', 'keyboard', 'reader']) {
      testWidgets(
        '$suite $input held picker opens real crop; crop completion source owns next confirmation and cancelling never saves',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = await _mount(t, suite);
          try {
            final crop = await _openCrop(t, p, input);
            final completion = input == 'pointer' ? 'keyboard' : 'pointer';
            final confirm = await _cropToConfirmation(t, p, completion);
            expect(confirm, isNot(same(crop)));
            expect(crop.instant, input != 'pointer');
            expect(confirm.instant, completion != 'pointer');
            await _act(t, 'hangar-image-cancel', 'reader');
            await _tail(t);
            expect(_confirmation(), findsNothing);
            expect(find.byType(CommunityLogoCrop), findsNothing);
            expect(p.original.reads, 1);
            expect(p.original.picks, 1);
            expect(p.original.crops, 1);
            expect(p.original.saves, 0);
            expect(p.original.restores, 0);
            expect(p.original.clears, 1);
            expect(p.callbacks, isEmpty);
            expect(_enabled(t, 'hangar-image-choose'), isTrue);
            expect(t.takeException(), isNull);
          } finally {
            await p.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }

    testWidgets(
      '$suite real crop then reader save waits for successful local receipt',
      (t) async {
        final semantics = t.ensureSemantics();
        final p = await _mount(t, suite);
        try {
          await _openCrop(t, p, 'pointer');
          await _cropToConfirmation(t, p, 'keyboard');
          await _beginSave(t, p, 'reader');
          await _tail(t);
          expect(p.original.saves, 1);
          expect(p.callbacks, isEmpty);
          expect(find.text('已保存到本机。'), findsNothing);
          p.original.saveGate!.complete();
          await _frames(t);
          await _tail(t);
          expect(p.original.currentImage, _image);
          expect(p.original.reads, 1);
          expect(p.original.crops, 1);
          expect(p.original.saves, 1);
          expect(p.original.clears, 1);
          expect(p.callbacks, [p.original]);
          expect(find.text('已保存到本机。'), findsOneWidget);
          expect(find.text('Catalog image'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite local save rejection remains uncertain and never reports success',
      (t) async {
        final semantics = t.ensureSemantics();
        final p = await _mount(t, suite);
        try {
          await _openCrop(t, p, 'keyboard');
          await _cropToConfirmation(t, p, 'pointer');
          await _beginSave(t, p, 'keyboard');
          p.original.saveGate!.completeError(
            StateError('synthetic lost receipt'),
          );
          await _frames(t);
          await _tail(t);
          expect(p.original.reads, 1);
          expect(p.original.saves, 1);
          expect(p.original.clears, 1);
          expect(p.original.currentImage, isNull);
          expect(p.callbacks, isEmpty);
          expect(find.textContaining('暂时无法确认保存结果'), findsOneWidget);
          expect(find.text('已保存到本机。'), findsNothing);
          expect(_enabled(t, 'hangar-image-choose'), isTrue);
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    testWidgets(
      '$suite actual restore cancel keeps image; confirmed restore waits before refresh callback',
      (t) async {
        final semantics = t.ensureSemantics();
        final p = await _mount(t, suite, initialImage: _image);
        try {
          await _act(t, 'hangar-image-restore', 'keyboard');
          final restore = find.ancestor(
            of: find.byKey(const Key('hangar-image-restore-confirm')),
            matching: find.byType(AlertDialog),
          );
          expect(_route(t, restore).instant, isTrue);
          await _act(t, 'hangar-image-restore-cancel', 'reader');
          await _tail(t);
          expect(p.original.restores, 0);
          expect(p.original.currentImage, _image);
          expect(p.callbacks, isEmpty);
          expect(find.text('Catalog image'), findsNothing);

          await _act(t, 'hangar-image-restore', 'pointer');
          expect(_route(t, restore).instant, isFalse);
          p.original.restoreGate = Completer<void>();
          await _act(t, 'hangar-image-restore-confirm', 'keyboard');
          expect(p.original.restores, 1);
          expect(p.original.restoreOrigins, [InteractionSource.keyboard]);
          expect(p.original.restoreGate!.isCompleted, isFalse);
          expect(p.original.currentImage, _image);
          expect(p.callbacks, isEmpty);
          p.original.restoreGate!.complete();
          await _frames(t);
          await _tail(t);
          expect(p.original.currentImage, isNull);
          expect(p.original.saves, 0);
          expect(p.original.clears, 0);
          expect(p.original.reads, 1);
          expect(p.callbacks, [p.original]);
          expect(find.text('已恢复默认图片。'), findsOneWidget);
          expect(find.text('Catalog image'), findsOneWidget);
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );

    // Scan additionally exercises replacement/readonly. Every suite covers
    // dispose while both the outgoing crop and new confirmation are owned.
    for (final retirement in [
      'dispose',
      if (suite == InteractionSuite.scan) ...['replacement', 'readonly'],
    ]) {
      testWidgets(
        '$suite $retirement retires reversing crop plus confirmation but preserves unrelated top dialog',
        (t) async {
          final semantics = t.ensureSemantics();
          final p = await _mount(t, suite);
          try {
            final crop = await _openCrop(t, p, 'pointer');
            final confirmation = await _cropToConfirmation(t, p, 'pointer');
            expect(crop.animation!.status, AnimationStatus.reverse);
            expect(crop.isActive, isFalse);
            expect(confirmation.isActive, isTrue);
            var cropCompleted = false, confirmationCompleted = false;
            unawaited(crop.completed.then((_) => cropCompleted = true));
            unawaited(
              confirmation.completed.then((_) => confirmationCompleted = true),
            );
            late StarBridgeDialogRoute<void> unrelated;
            final unrelatedClosed = showStarBridgeDialog<void>(
              t.element(_confirmation()),
              source: InteractionSource.keyboard,
              onRouteCreated: (route) => unrelated = route,
              builder: (context) => AlertDialog(
                title: const Text('Unrelated top dialog'),
                actions: [
                  StarBridgeActionButton(
                    controlKey: const Key('unrelated-image-flow-close'),
                    onActivate: (source) =>
                        dismissStarBridgeDialog<void>(context, source: source),
                    child: const Text('Close unrelated'),
                  ),
                ],
              ),
            );
            await _frames(t);
            expect(unrelated.isCurrent, isTrue);
            p.update(() {
              if (retirement == 'dispose') {
                p.visible = false;
              } else if (retirement == 'replacement') {
                p.current = _Port();
              } else {
                p.editable = false;
              }
            });
            await _frames(t, 5);
            expect(cropCompleted, isTrue);
            expect(confirmationCompleted, isTrue);
            expect(crop.animation!.status, AnimationStatus.dismissed);
            expect(confirmation.isActive, isFalse);
            expect(
              find.byType(CommunityLogoCrop, skipOffstage: false),
              findsNothing,
            );
            expect(
              find.byKey(
                const Key('hangar-image-confirm'),
                skipOffstage: false,
              ),
              findsNothing,
            );
            expect(unrelated.isActive, isTrue);
            expect(unrelated.isCurrent, isTrue);
            expect(find.text('Unrelated top dialog'), findsOneWidget);
            expect(p.original.saves, 0);
            expect(p.original.clears, 1);
            expect(p.callbacks, isEmpty);
            if (retirement == 'replacement') {
              expect(p.current.reads, 1);
              expect(p.current.picks, 0);
              expect(p.current.saves, 0);
            }
            await _act(t, 'unrelated-image-flow-close', 'keyboard');
            await unrelatedClosed;
            await _frames(t);
            expect(t.takeException(), isNull);
          } finally {
            await p.close(t);
            semantics.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }

  for (final outcome in ['cancel', 'failure']) {
    testWidgets(
      'Scan picker $outcome never starts crop or local save and clears native draft once',
      (t) async {
        final semantics = t.ensureSemantics();
        final p = await _mount(t, InteractionSuite.scan);
        try {
          p.original.pickGate = Completer<CommunityLogoSource?>();
          await _act(t, 'hangar-image-choose', 'keyboard');
          expect(p.original.picks, 1);
          if (outcome == 'cancel') {
            p.original.pickGate!.complete(null);
          } else {
            p.original.pickGate!.completeError(
              StateError('synthetic picker refusal'),
            );
          }
          await _frames(t);
          await _tail(t);
          expect(find.byType(CommunityLogoCrop), findsNothing);
          expect(p.original.crops, 0);
          expect(p.original.saves, 0);
          expect(p.original.clears, 1);
          expect(p.callbacks, isEmpty);
          expect(
            find.text('未保存图片，请重新选择。'),
            outcome == 'failure' ? findsOneWidget : findsNothing,
          );
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }

  testWidgets(
    'Scan actual crop cancellation clears draft without cropping or saving',
    (t) async {
      final semantics = t.ensureSemantics();
      final p = await _mount(t, InteractionSuite.scan);
      try {
        await _openCrop(t, p, 'reader');
        await _act(t, 'community-crop-cancel', 'keyboard');
        await _tail(t);
        expect(find.byType(CommunityLogoCrop), findsNothing);
        expect(_confirmation(), findsNothing);
        expect(p.original.picks, 1);
        expect(p.original.crops, 0);
        expect(p.original.saves, 0);
        expect(p.original.clears, 1);
        expect(p.callbacks, isEmpty);
        expect(_enabled(t, 'hangar-image-choose'), isTrue);
        expect(t.takeException(), isNull);
      } finally {
        await p.close(t);
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Scan rejected crop stays editable for explicit retry; neither attempt saves before confirmation',
    (t) async {
      final semantics = t.ensureSemantics();
      final p = await _mount(t, InteractionSuite.scan);
      try {
        await _openCrop(t, p, 'reader');
        p.original.cropGate = Completer<String>();
        await _act(t, 'community-crop-apply', 'keyboard');
        p.original.cropGate!.completeError(
          StateError('synthetic crop refusal'),
        );
        await _frames(t);
        expect(find.byType(CommunityLogoCrop), findsOneWidget);
        expect(_enabled(t, 'community-crop-apply'), isTrue);
        expect(_enabled(t, 'community-crop-cancel'), isTrue);
        expect(_confirmation(), findsNothing);
        expect(p.original.crops, 1);
        expect(p.original.saves, 0);
        expect(p.original.clears, 0);
        p.original.cropGate = Completer<String>();
        await _act(t, 'community-crop-apply', 'reader');
        expect(p.original.crops, 2);
        p.original.cropGate!.complete(_image);
        await _frames(t);
        expect(_confirmation(), findsOneWidget);
        expect(_route(t, _confirmation()).instant, isTrue);
        expect(p.original.saves, 0);
        await _act(t, 'hangar-image-cancel', 'keyboard');
        await _tail(t);
        expect(p.original.saves, 0);
        expect(p.original.clears, 1);
        expect(p.callbacks, isEmpty);
        expect(t.takeException(), isNull);
      } finally {
        await p.close(t);
        semantics.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  for (final retirement in ['dispose', 'replacement']) {
    testWidgets(
      'Scan late local save receipt after $retirement never notifies replacement owner',
      (t) async {
        final semantics = t.ensureSemantics();
        final p = await _mount(t, InteractionSuite.scan);
        try {
          await _openCrop(t, p, 'keyboard');
          await _cropToConfirmation(t, p, 'keyboard');
          await _beginSave(t, p, 'pointer');
          p.update(() {
            if (retirement == 'dispose') {
              p.visible = false;
            } else {
              p.current = _Port();
            }
          });
          await _frames(t);
          expect(p.callbacks, isEmpty);
          p.original.saveGate!.complete();
          await _frames(t);
          await _tail(t);
          expect(p.original.saves, 1);
          expect(p.original.currentImage, _image);
          expect(p.original.clears, 1);
          expect(p.callbacks, isEmpty);
          if (retirement == 'replacement') {
            expect(
              t.widget<LocalHangarImageEditor>(find.byKey(_editorKey)).port,
              same(p.current),
            );
            expect(p.current.reads, 1);
            expect(p.current.picks, 0);
            expect(p.current.crops, 0);
            expect(p.current.saves, 0);
            expect(p.current.clears, 0);
          } else {
            expect(find.text('Editor left'), findsOneWidget);
          }
          expect(find.text('已保存到本机。'), findsNothing);
          expect(t.takeException(), isNull);
        } finally {
          await p.close(t);
          semantics.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}
