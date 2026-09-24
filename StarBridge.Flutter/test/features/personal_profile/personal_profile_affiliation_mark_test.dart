import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/preferences/app_preferences.dart';
import 'package:starbridge_flutter/design_system/icons/icon_semantic.dart';
import 'package:starbridge_flutter/design_system/icons/starbridge_icon.dart';
import 'package:starbridge_flutter/design_system/style_registry.dart';
import 'package:starbridge_flutter/design_system/theme/theme_builder.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_affiliation_mark.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';

void main() {
  testWidgets(
    'renders a directory-sized logo without the small avatar cutoff',
    (tester) async {
      final bytes = Uint8List(300 * 1024);
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      bytes.setRange(0, png.length, png);
      await tester.pumpWidget(
        _app(
          PersonalProfileAffiliationMark(
            affiliation: PersonalProfileAffiliationSummary(
              kind: PersonalProfileAffiliationKind.featuredCommunity,
              name: 'Fixture',
              code: 'TEST',
              positionLabelKey: 'Member',
              logoImageData: 'data:image/png;base64,${base64Encode(bytes)}',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('profile-affiliation-logo-featuredCommunity')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('profile-affiliation-fallback-featuredCommunity')),
        findsNothing,
      );
    },
  );
  testWidgets('uses distinct fleet and community fallback marks', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const Row(
          children: [
            PersonalProfileAffiliationMark(affiliation: _fleetAffiliation),
            PersonalProfileAffiliationMark(affiliation: _communityAffiliation),
          ],
        ),
      ),
    );
    await tester.pump();

    final fleetIcon = tester.widget<StarBridgeIcon>(
      find.byKey(const Key('profile-affiliation-fallback-officialFleet')),
    );
    final communityIcon = tester.widget<StarBridgeIcon>(
      find.byKey(const Key('profile-affiliation-fallback-featuredCommunity')),
    );
    expect(fleetIcon.semantic, StarBridgeIconSemantic.officialFleet);
    expect(communityIcon.semantic, StarBridgeIconSemantic.community);
  });

  testWidgets('prefers a supplied organization logo over the fallback mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const PersonalProfileAffiliationMark(
          affiliation: PersonalProfileAffiliationSummary(
            kind: PersonalProfileAffiliationKind.featuredCommunity,
            name: 'Northwind 联合社区',
            code: 'NORTH',
            positionLabelKey: 'profile.affiliation.position.operationHost',
            logoImageData:
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
                'CAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('profile-affiliation-logo-featuredCommunity')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('profile-affiliation-fallback-featuredCommunity')),
      findsNothing,
    );
  });

  testWidgets('uses a supplied official fleet HTTPS logo', (tester) async {
    await tester.pumpWidget(
      _app(
        const PersonalProfileAffiliationMark(
          affiliation: PersonalProfileAffiliationSummary(
            kind: PersonalProfileAffiliationKind.officialFleet,
            name: "Aster's Wing",
            code: 'ASTER',
            positionLabelKey: 'profile.affiliation.position.fleetMember',
            logoUrl: 'https://cdn.example.test/aster.png',
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(
      find.byKey(const Key('profile-affiliation-logo-officialFleet')),
    );
    expect(image.image, isA<NetworkImage>());
  });
}

const _fleetAffiliation = PersonalProfileAffiliationSummary(
  kind: PersonalProfileAffiliationKind.officialFleet,
  name: "Aster's Wing",
  code: 'ASTER',
  positionLabelKey: 'profile.affiliation.position.fleetMember',
);

const _communityAffiliation = PersonalProfileAffiliationSummary(
  kind: PersonalProfileAffiliationKind.featuredCommunity,
  name: 'Northwind 联合社区',
  code: 'NORTH',
  positionLabelKey: 'profile.affiliation.position.operationHost',
);

Widget _app(Widget child) {
  final tokens = StyleRegistry()
      .resolve(AppPreferences.defaults.designStyleId, AppearanceMode.dark)
      .tokens;
  return MaterialApp(
    theme: buildStarBridgeTheme(tokens, const Locale('zh', 'CN')),
    home: Scaffold(body: Center(child: child)),
  );
}
