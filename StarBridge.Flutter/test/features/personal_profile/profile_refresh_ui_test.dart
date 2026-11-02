import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/interaction/starbridge_action_button.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_page.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_content_probe.dart';
import 'package:starbridge_flutter/shared/diagnostics/loading_metrics.dart';

import 'profile_refresh_retention_test.dart' show HeldRefreshProfile;

void main() {
  for (final hard in [false, true]) {
    testWidgets(
      'profile draft survives ordinary updates and ${hard ? 'is cleared by hard invalidation' : 'releases refresh after cancel'}',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final port = HeldRefreshProfile();
        final module = createPersonalProfileModule(port);
        addTearDown(module.dispose);
        await module.initialize();
        await tester.pumpWidget(_app(module, const Locale('en')));
        await tester.pumpAndSettle();
        final edit = find.byKey(const Key('profile-edit'));
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final about = find.byKey(const Key('profile-about-field'));
        await tester.ensureVisible(about);
        await tester.enterText(about, 'unsaved profile draft');
        for (var i = 0; i < 10; i++) {
          port.soft.add(null);
        }
        await module.refresh();
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(about).controller!.text,
          'unsaved profile draft',
        );
        expect(port.reads, 1);
        expect(port.saves, 0);
        port.readGate = Completer<PersonalProfileSnapshot>();
        if (hard) {
          port.hard.add(null);
          await tester.pump();
          expect(find.byKey(const Key('profile-editor-panel')), findsNothing);
          expect(
            find.byKey(const Key('profile-identity-header')),
            findsNothing,
          );
        } else {
          final cancel = find.byKey(const Key('profile-edit-cancel'));
          await tester.ensureVisible(cancel);
          await tester.tap(cancel);
          await tester.pump();
          expect(find.byKey(const Key('profile-editor-panel')), findsNothing);
          expect(
            find.byKey(const Key('profile-identity-header')),
            findsOneWidget,
          );
        }
        expect(port.reads, 2);
        port.readGate!.complete(await port.delegate.read());
        await tester.pumpAndSettle();
        expect(port.reads, 2);
        expect(port.saves, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final locale in AppStrings.supportedLocales) {
    testWidgets(
      '$locale profile refresh keeps content, reports failure and retries',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 1000);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final port = HeldRefreshProfile();
        final module = createPersonalProfileModule(
          port,
          clock: () => DateTime.utc(2026, 10, 15, 12),
        );
        addTearDown(module.dispose);
        await module.initialize();
        await tester.pumpWidget(_app(module, locale));
        await tester.pumpAndSettle();
        final refresh = find.byKey(const Key('profile-refresh'));
        await tester.ensureVisible(refresh);
        port.readGate = Completer<PersonalProfileSnapshot>();
        await tester.tap(refresh);
        await tester.pump();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<StarBridgeActionButton>(
                find
                    .ancestor(
                      of: refresh,
                      matching: find.byType(StarBridgeActionButton),
                    )
                    .first,
              )
              .onActivate,
          isNull,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        port.readGate!.completeError(
          TimeoutException('synthetic transport outage'),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('profile-identity-header')),
          findsOneWidget,
        );
        final notice = tester
            .widget<Text>(find.byKey(const Key('profile-sync-failed')))
            .data!;
        final context = tester.element(find.byType(PersonalProfilePage));
        final template = AppStrings.of(context).text('profile.syncFailedAt');
        expect(notice, startsWith(template.split('{time}').first));
        expect(notice, contains('2026'));
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('profile-edit')))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<LoadingContentProbe>(find.byType(LoadingContentProbe))
              .status,
          LoadingContentStatus.partial,
        );
        await tester.ensureVisible(refresh);
        port.readGate = null;
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('profile-sync-failed')), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('profile-edit')))
              .onPressed,
          isNotNull,
        );
        expect(port.saves, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Widget _app(PersonalProfileModule module, Locale locale) => MaterialApp(
  locale: locale,
  supportedLocales: AppStrings.supportedLocales,
  localizationsDelegates: const [
    AppStringsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: buildStarBridgeTheme(
    FutureRestraintStyle.resolve(AppearanceMode.dark),
    locale,
  ),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child!,
  ),
  home: Scaffold(body: PersonalProfilePage(module: module)),
);
