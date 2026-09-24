import 'package:flutter/material.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/app_strings.dart';
import 'package:starbridge_flutter/design_system/styles/future_restraint_style.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_positions_module.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_affiliation_mark.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_collaboration.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/features/communities/community_logo.dart';
import 'package:starbridge_flutter/shared/inline_image_cache.dart';

import '../friends/social_layout_test.dart' show loadFonts;

const logo =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
    'CAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
Widget app(Widget child, {Locale locale = const Locale('zh', 'CN')}) =>
    MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: buildStarBridgeTheme(
        FutureRestraintStyle.resolve(AppearanceMode.dark)
            .withReducedMotion(true),
        locale,
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUpAll(loadFonts);
  testWidgets(
    'position tags fit the real 747 by 140 module without paint clipping',
    (tester) async {
      await tester.pumpWidget(
        app(
          RepaintBoundary(
            key: const Key('position-correction-capture'),
            child: SizedBox(
              width: 747,
              height: 140,
              child: PersonalProfilePositionsModule(
                headerTrailing: IconButton(
                  onPressed: () {},
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit, size: 16),
                ),
                roles: [
                  for (final id in [
                    'fleet-command',
                    'pilot',
                    'gunner',
                    'fighter-pilot',
                    'assault-trooper',
                  ])
                    ProfileCollaboration.options['roles']![id]!,
                ],
                participationInterests: [
                  ProfileCollaboration.options['interests']!['pve']!,
                ],
                supportCapabilities: [
                  ProfileCollaboration.options['support']!['pilot']!,
                  ProfileCollaboration.options['support']!['gunner']!,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('参与偏好')).dx -
            tester.getTopLeft(find.text('擅长岗位')).dx,
        greaterThan(380),
        reason: 'Keep the original 5:4 left/right split; only fix the right sections',
      );
      for (final finder in [
        find.text('战斗机驾驶员'),
        find.text('突击队员'),
        find.text('PVE 战斗'),
        find.text('驾驶'),
        find.text('炮手').last,
      ]) {
        expect(finder, findsOneWidget);
        final label = tester.renderObject<RenderBox>(finder);
        RenderObject child = label;
        while (child.parent != null) {
          final parent = child.parent!;
          final clip = parent.describeApproximatePaintClip(child);
          if (clip != null) {
            final bounds = MatrixUtils.transformRect(
              label.getTransformTo(parent),
              label.paintBounds,
            );
            expect(
              bounds.bottom,
              lessThanOrEqualTo(clip.bottom + .01),
              reason: '$finder clipped by ${parent.runtimeType}',
            );
            expect(bounds.top, greaterThanOrEqualTo(clip.top - .01));
          }
          child = parent;
        }
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['STARBRIDGE_CAPTURE_POLISH'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('position-correction-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('../.artifacts/position-correction.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );

  for (final profile in [true, false]) {
    testWidgets(
      '${profile ? "profile affiliation" : "discovery logo"} reuses image decoding across route/list remounts',
      (tester) async {
        Widget mark() => profile
            ? const PersonalProfileAffiliationMark(
                affiliation: PersonalProfileAffiliationSummary(
                  kind: PersonalProfileAffiliationKind.featuredCommunity,
                  name: 'Synthetic',
                  code: 'TEST',
                  positionLabelKey: 'profile.affiliation.position.fleetMember',
                  logoImageData: logo,
                ),
              )
            : const CommunityLogo(data: logo);
        final providers = <ImageProvider>{};
        final cache = InlineImageCache();
        addTearDown(cache.clear);
        final watch = Stopwatch()..start();
        for (var i = 0; i < 8; i++) {
          await tester.pumpWidget(
            app(InlineImageCacheScope(cache: cache, child: mark())),
          );
          await tester.pump();
          providers.add(tester.widget<Image>(find.byType(Image).first).image);
          await tester.pumpWidget(app(const SizedBox()));
        }
        // Equality is Flutter's actual decoded-image cache key, not a mock counter.
        debugPrint(
          'Repeated ${profile ? "profile" : "directory"} entry: ${providers.length} image keys, ${watch.elapsedMilliseconds}ms fixture time',
        );
        expect(
          providers.length,
          1,
          reason: 'same image must not be decoded again on every visit',
        );
      },
    );
  }
}
