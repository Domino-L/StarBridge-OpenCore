import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/product_features.dart';

import 'image_maintenance_menu_boundaries_test.dart' show MenuMaintenanceScene;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group(
    'production maintenance waits existing engine retirement',
    () {
      test(
        'a positive Host count is not success before the surface receipt',
        () async {
          final scene = MenuMaintenanceScene();
          try {
            await scene.open();
            final gate = Completer<Object?>();
            final arrived = Completer<void>();
            var epoch = 0;
            scene.retirementReply = (call) {
              epoch = (call.arguments as Map)['resourceEpoch'] as int;
              if (epoch == 2 && !arrived.isCompleted) arrived.complete();
              return gate.future;
            };
            var complete = false;
            final clearing = scene.app.imageMaintenance.clear().then((value) {
              complete = true;
              return value;
            });
            await arrived.future.timeout(const Duration(seconds: 2));
            expect(scene.app.imageMaintenance.busy, isTrue);
            expect(scene.app.imageMaintenance.result, isNull);
            expect(complete, isFalse);
            gate.complete({
              'schemaVersion': 1,
              'resourceEpoch': epoch,
              'enginePresent': true,
            });
            expect(await clearing, 0);
            expect(scene.app.imageMaintenance.result, 'cleared');
            expect(
              scene.host.requests.where(
                (r) => r.name == 'diagnostics.clearImageCache',
              ),
              hasLength(1),
            );
          } finally {
            await scene.close();
          }
        },
      );
      for (final receipt in <Object?>[
        null,
        {'schemaVersion': 1, 'resourceEpoch': 0, 'enginePresent': true},
        {'schemaVersion': 1, 'resourceEpoch': 2, 'enginePresent': 'true'},
      ]) {
        test(
          'unconfirmed surface receipt $receipt keeps maintenance failed without replay',
          () async {
            final scene = MenuMaintenanceScene();
            try {
              await scene.open();
              scene.retirementReply = (_) async => receipt;
              await expectLater(
                scene.app.imageMaintenance.clear(),
                throwsStateError,
              );
              expect(scene.app.imageMaintenance.result, 'failed');
              expect(scene.app.imageMaintenance.busy, isFalse);
              expect(
                scene.host.requests.where(
                  (r) => r.name == 'diagnostics.clearImageCache',
                ),
                hasLength(1),
              );
            } finally {
              await scene.close();
            }
          },
        );
      }
    },
    skip: !menuOverlayEnabled
        ? 'Requires menu-enabled product composition'
        : false,
  );
}
