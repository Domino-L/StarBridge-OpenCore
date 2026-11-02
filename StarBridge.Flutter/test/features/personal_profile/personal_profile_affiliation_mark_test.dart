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
import 'package:starbridge_flutter/features/common/organization_logo_hints.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_affiliation_mark.dart';
import 'package:starbridge_flutter/features/personal_profile/personal_profile_models.dart';
import 'package:starbridge_flutter/shared/remote_image.dart';
import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../../support/remote_image_fixture.dart';
import '../../app/menu_overlay/menu_profile_images_test.dart' show ImageClient;

void main() {
  _hintTests();
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
  testWidgets('a fleet without any logo shows its initials, never an emblem', (
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

    // User decision 2026-10-24: the main fleet mark is never a placeholder.
    expect(
      find.byKey(const Key('profile-affiliation-fallback-officialFleet')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('profile-affiliation-initials-officialFleet')),
        matching: find.text('AS'),
      ),
      findsOneWidget,
    );
    final communityIcon = tester.widget<StarBridgeIcon>(
      find.byKey(const Key('profile-affiliation-fallback-featuredCommunity')),
    );
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
    final mode = ImageMode();
    final client = ImageClient()
      ..bytes.complete(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    final loader = RemoteImageLoader(mode: mode, createClient: () => client);
    await tester.pumpWidget(
      _app(
        RemoteImageScope(
          loader: loader,
          child: const PersonalProfileAffiliationMark(
            affiliation: PersonalProfileAffiliationSummary(
              kind: PersonalProfileAffiliationKind.officialFleet,
              name: "Aster's Wing",
              code: 'ASTER',
              positionLabelKey: 'profile.affiliation.position.fleetMember',
              logoUrl: 'https://cdn.example.test/aster.png',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('profile-affiliation-logo-officialFleet')),
      findsOneWidget,
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(client.reads, 1);
    await tester.pumpWidget(const SizedBox());
    loader.dispose();
    mode.dispose();
  });
}

void _hintTests() {
  testWidgets('a fleet without its own logo uses the known main fleet logo', (
    tester,
  ) async {
    final mode = ImageMode();
    final client = ImageClient()
      ..bytes.complete(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
      );
    final loader = RemoteImageLoader(mode: mode, createClient: () => client);
    final source = ValueNotifier(0);
    final asked = <String>[];
    await tester.pumpWidget(
      _app(
        RemoteImageScope(
          loader: loader,
          child: OrganizationLogoHints(
            notifier: source,
            resolve: (code) {
              asked.add(code);
              return code == 'ASTER'
                  ? 'https://cdn.example.test/aster.png'
                  : null;
            },
            child: const Row(
              children: [
                PersonalProfileAffiliationMark(affiliation: _fleetAffiliation),
                PersonalProfileAffiliationMark(
                  affiliation: _communityAffiliation,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('profile-affiliation-logo-officialFleet')),
      findsOneWidget,
    );
    // Communities never borrow the main fleet's logo.
    expect(asked, ['ASTER']);
    expect(
      find.byKey(const Key('profile-affiliation-fallback-featuredCommunity')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    loader.dispose();
    mode.dispose();
    source.dispose();
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
