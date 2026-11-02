import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_local_tools.dart';
import 'package:starbridge_flutter/app/menu_overlay/menu_image_edit.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_activation_origin.dart';

import '../../app/menu_overlay/menu_reference_adjustments_test.dart'
    show pngHeader;

void main() {
  for (final source in InteractionSource.values) {
    for (final method in [
      'image',
      'capture',
      'save',
      'editScreenshot',
      'editReference',
      'pin',
      'clear',
    ]) {
      for (final failure in [false, true]) {
        test(
          '$source $method admitted feedback is local, blocked input cannot replace it fail=$failure',
          () async {
            final reply = Completer<Object?>();
            final calls = <(String, Map<String, Object?>)>[];
            final data = pngHeader();
            final tools =
                MenuLocalToolsController((name, args) {
                    calls.add((name, args));
                    return reply.future;
                  })
                  ..reference = data
                  ..screenshot = data;
            final Future<dynamic> operation =
                runStarBridgeSynchronousActivation(
                  source,
                  () => switch (method) {
                    'image' => tools.image(),
                    'capture' => tools.image(capture: true),
                    'save' => tools.save(),
                    'editScreenshot' => tools.editScreenshot(
                      const MenuImageEdit(turns: 1),
                    ),
                    'editReference' => tools.editReference(
                      const MenuImageEdit(turns: 1),
                    ),
                    'pin' => tools.pin(const {
                      'x': 1,
                      'y': 2,
                      'width': 3,
                      'height': 4,
                    }),
                    _ => tools.clear(),
                  },
                );
            expect(tools.busy, isTrue);
            expect(tools.imageFeedbackSource, source);
            final admitted = calls.single;
            await runStarBridgeSynchronousActivation(
              InteractionSource.keyboard,
              () => tools.image(),
            );
            expect(calls, [admitted]);
            expect(tools.imageFeedbackSource, source);
            expect(
              admitted.$2.keys.any(
                (k) => k.contains('ource') || k.contains('eedback'),
              ),
              isFalse,
            );
            if (failure) {
              reply.completeError(PlatformException(code: 'synthetic'));
            } else {
              reply.complete(
                [
                      'image',
                      'capture',
                      'editScreenshot',
                      'editReference',
                    ].contains(method)
                    ? data
                    : true,
              );
            }
            await operation;
            expect(tools.busy, isFalse);
            expect(calls, [admitted]);
            tools.dispose();
            expect(tools.imageFeedbackSource, InteractionSource.programmatic);
          },
        );
      }
    }
    for (final outcome in ['success', 'cancel', 'fail', 'dispose']) {
      test(
        '$source capture-save carries only this admitted operation source $outcome',
        () async {
          final capture = Completer<Object?>(), save = Completer<Object?>();
          final calls = <(String, Map<String, Object?>)>[];
          final tools = MenuLocalToolsController((name, args) {
            calls.add((name, args));
            return name == 'capture' ? capture.future : save.future;
          });
          final operation = runStarBridgeSynchronousActivation(
            source,
            () => tools.captureAndSave(),
          );
          expect(tools.imageFeedbackSource, source);
          expect(calls.single.$1, 'capture');
          expect(calls.single.$2, {'hideMenu': true});
          capture.complete(Uint8List.fromList([1, 2, 3]));
          await Future<void>.delayed(Duration.zero);
          expect(calls.map((c) => c.$1), ['capture', 'save']);
          expect(tools.imageFeedbackSource, source);
          expect(calls.last.$2, {
            ...const MenuImageEdit().toMap(),
            'export': {'format': 'png', 'jpegQuality': 90},
          });
          expect(tools.screenshotNoticeKey, isEmpty);
          if (outcome == 'dispose') tools.dispose();
          if (outcome == 'fail') {
            save.completeError(StateError('synthetic'));
          } else {
            save.complete(outcome != 'cancel');
          }
          await operation;
          expect(tools.screenshotNoticeKey, switch (outcome) {
            'success' => 'exported',
            'cancel' => 'cancelled',
            'fail' => 'saveFailed',
            _ => '',
          });
          if (!tools.closed) tools.dispose();
        },
      );
    }
  }
}
