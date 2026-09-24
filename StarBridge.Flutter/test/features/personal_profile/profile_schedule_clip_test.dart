import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_schedule_editor.dart';

void main() {
  for (final scale in [1.0, 1.25, 1.5]) {
    testWidgets('expanded timezone label is inside paint clips at $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStringsDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          theme: buildStarBridgeTheme(
            FutureRestraintStyle.resolve(AppearanceMode.dark)
                .withReducedMotion(true),
            const Locale('zh', 'CN'),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  child: PersonalProfileScheduleEditor(
                    initial: const PersonalProfileSchedule(
                      timeZoneId: 'UTC',
                      rhythm: PersonalProfileActivityRhythm.casual,
                      windows: [],
                    ),
                    timeZones: const {'UTC': 'UTC'},
                    enabled: true,
                    onChanged: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-schedule-editor')));
      await tester.pumpAndSettle();
      final text = find.text('所在时区');
      expect(text, findsOneWidget);
      final label = tester.renderObject<RenderBox>(text);
      RenderObject child = label;
      var clips = 0;
      while (child.parent != null) {
        final parent = child.parent!;
        final clip = parent.describeApproximatePaintClip(child);
        if (clip != null) {
          clips++;
          final bounds = MatrixUtils.transformRect(
            label.getTransformTo(parent),
            label.paintBounds,
          );
          expect(
            bounds.top,
            greaterThanOrEqualTo(clip.top - 0.01),
            reason: '${parent.runtimeType}: label $bounds, clip $clip',
          );
          expect(bounds.bottom, lessThanOrEqualTo(clip.bottom + 0.01));
        }
        child = parent;
      }
      expect(clips, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
}
