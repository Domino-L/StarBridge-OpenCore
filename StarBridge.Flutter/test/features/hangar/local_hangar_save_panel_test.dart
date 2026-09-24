import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_port.dart';
import 'package:starbridge_flutter/features/hangar/local_hangar_save_panel.dart';

void main() {
  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'save confirmation fits narrow width and saves only on consent $locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final port = PanelPort();
        var saved = 0;
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: const [
              Locale('zh', 'CN'),
              Locale('zh', 'TW'),
              Locale('en'),
            ],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildStarBridgeTheme(
              FutureRestraintStyle.resolve(AppearanceMode.dark),
              locale,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(12),
                child: LocalHangarSavePanel(
                  port: port,
                  view: const {
                    'operationId': 'scan',
                    'shipCount': 0,
                    'phase': 'complete',
                  },
                  onSaved: () => saved++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final button = find.byKey(const Key('local-hangar-save'));
        expect(tester.widget<FilledButton>(button).onPressed, isNull);
        await tester.tap(find.byKey(const Key('local-hangar-confirm')));
        await tester.pump();
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(port.confirmed, true);
        expect(saved, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class PanelPort implements LocalHangarPort {
  bool confirmed = false;
  @override
  Future<LocalHangarSnapshot> read() async =>
      const LocalHangarSnapshot(revision: 0, ships: []);
  @override
  Future<LocalHangarSnapshot> save(
    String operationId,
    int expectedRevision, {
    bool confirmEmpty = false,
  }) async {
    confirmed = confirmEmpty;
    return LocalHangarSnapshot(
      revision: 1,
      operationId: operationId,
      ships: const [],
    );
  }
}
