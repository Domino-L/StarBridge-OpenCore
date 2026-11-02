import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/features/communities/community_logo_port.dart';
import 'package:starbridge_flutter/features/communities/community_wide_image_crop.dart';
import 'package:starbridge_flutter/features/communities/community_wide_image_port.dart';

import 'community_creation_dialog_test.dart' show FormPort;
import 'community_image_test_support.dart';
import 'community_profile_dialog_test.dart';
import '../friends/social_layout_test.dart' show loadFonts;

class WideEditorPort extends EditorPort implements CommunityWideImagePort {
  WideEditorPort({this.sourceWidth = 1600, this.sourceHeight = 900});
  final int sourceWidth, sourceHeight;
  bool wideAvailable = true;
  final wideCrops = <(String, double, double, double)>[];
  int widePicks = 0, wideClears = 0;
  @override
  bool get canPickWideImage => wideAvailable;
  @override
  Future<CommunityLogoSource?> pickWideImage(String kind) async {
    widePicks++;
    return CommunityLogoSource(
      'c' * 32,
      FormPort.image,
      sourceWidth,
      sourceHeight,
    );
  }

  @override
  Future<String> cropWideImage(
    String sourceRef,
    String kind,
    double x,
    double y,
    double width,
  ) async {
    // Same bounds as BridgeCommunities.cropWideImage and the Host.
    final height =
        sourceWidth * width / communityWideImageAspect[kind]! / sourceHeight;
    if (x < 0 ||
        y < 0 ||
        width < .2 ||
        width > 1 ||
        x + width > 1 + 1e-12 ||
        y + height > 1 + 1e-12) {
      throw const FormatException();
    }
    wideCrops.add((kind, x, y, width));
    return FormPort.image;
  }

  @override
  Future<void> clearWideImage() async => wideClears++;
}

void _access(EditorPort port, {bool banner = true, bool supported = true}) {
  port.profile
    ..['wideImagesSupported'] = supported
    ..['hasBanner'] = true
    ..['hasBackground'] = false
    ..['access'] = {
      'canEditProfile': true,
      'canEditLogo': true,
      'canEditBanner': banner,
    };
}

Finder _box() => find.byKey(const ValueKey('community-profile-wide-images'));

void main() {
  setUpAll(loadFonts);

  testWidgets('An old server keeps the banner/background editor hidden', (
    tester,
  ) async {
    final port = WideEditorPort();
    _access(port, supported: false);
    await open(tester, port);
    expect(_box(), findsNothing);
    // The legacy remove-banner action is still offered on old servers.
    expect(find.byKey(const Key('profile-remove-banner')), findsOneWidget);
  });

  testWidgets('Choosing a background crops 16:9 and saves only that image', (
    tester,
  ) async {
    final port = WideEditorPort();
    _access(port);
    await open(tester, port);
    expect(_box(), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('profile-wide-banner-status')),
          )
          .data,
      text(tester, 'wideSet'),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-pick-background')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-pick-background')));
    await settleCommunityImages(tester);
    expect(find.byType(CommunityWideImageCrop), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
    await settleCommunityImages(tester);
    expect(port.widePicks, 1);
    expect(port.wideClears, 1);
    final crop = port.wideCrops.single;
    expect(crop.$1, 'background');
    // 1600×900 is already 16:9, so the default crop is the whole image.
    expect(crop.$4, closeTo(1, 1e-9));
    expect(crop.$2, closeTo(0, 1e-9));
    expect(crop.$3, closeTo(0, 1e-9));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('profile-wide-background-status')),
          )
          .data,
      text(tester, 'wideReplace'),
    );
    expect(
      find.byKey(const ValueKey('profile-wide-background-draft')),
      findsOneWidget,
    );
    await tester.ensureVisible(_box());
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('profile-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File('build/community-wide-images-review.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
    });
    await save(tester);
    expect(port.saves.single, {'backgroundImageData': FormPort.image});
  });

  testWidgets(
    'Removing the banner sends a clear and dropping a draft does not',
    (tester) async {
      final port = WideEditorPort();
      _access(port);
      await open(tester, port);
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-remove-banner')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-remove-banner')));
      await settleCommunityImages(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('profile-wide-banner-status')),
            )
            .data,
        text(tester, 'wideRemove'),
      );
      // A background chosen and then removed again is simply dropped.
      await tester.tap(find.byKey(const ValueKey('profile-pick-background')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const ValueKey('profile-remove-background')));
      await settleCommunityImages(tester);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('profile-wide-background-status')),
            )
            .data,
        text(tester, 'wideEmpty'),
      );
      await save(tester);
      expect(port.saves.single, {'clearBannerImage': true});
    },
  );

  testWidgets('Without the combined permission both images are read-only', (
    tester,
  ) async {
    final port = WideEditorPort();
    _access(port, banner: false);
    await open(tester, port);
    expect(
      find.byKey(const ValueKey('profile-wide-no-permission')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-pick-banner')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-pick-banner')));
    await settleCommunityImages(tester);
    expect(port.widePicks, 0);
  });

  testWidgets('A panorama too wide for 16:9 cannot be applied', (tester) async {
    final port = WideEditorPort(sourceWidth: 4000, sourceHeight: 300);
    _access(port);
    await open(tester, port);
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-pick-background')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-pick-background')));
    await settleCommunityImages(tester);
    expect(find.byKey(const Key('community-wide-crop-failed')), findsOneWidget);
    await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
    await settleCommunityImages(tester);
    expect(port.wideCrops, isEmpty);
  });

  testWidgets('A narrow banner crop keeps 4:1 and stays inside the source', (
    tester,
  ) async {
    final port = WideEditorPort(sourceWidth: 1000, sourceHeight: 1000);
    _access(port);
    await open(tester, port);
    await tester.ensureVisible(
      find.byKey(const ValueKey('profile-pick-banner')),
    );
    await tester.tap(find.byKey(const ValueKey('profile-pick-banner')));
    await settleCommunityImages(tester);
    await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
    await settleCommunityImages(tester);
    final crop = port.wideCrops.single;
    expect(crop.$1, 'banner');
    expect(crop.$4, closeTo(1, 1e-9));
    // Height is 1000 × 1 / 4 = 250, centred vertically: (1000 - 250) / 2 / 1000.
    expect(crop.$3, closeTo(.375, 1e-9));
  });

  for (final (kind, w, h) in [
    ('background', 1000, 320),
    ('background', 1001, 563),
    ('banner', 1003, 251),
    ('banner', 777, 1333),
  ]) {
    testWidgets('Default $kind crop of $w×$h stays inside the Host bounds', (
      tester,
    ) async {
      final port = WideEditorPort(sourceWidth: w, sourceHeight: h);
      _access(port);
      await open(tester, port);
      await tester.ensureVisible(find.byKey(ValueKey('profile-pick-$kind')));
      await tester.tap(find.byKey(ValueKey('profile-pick-$kind')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
      await settleCommunityImages(tester);
      expect(port.wideCrops, hasLength(1));
      expect(find.byType(CommunityWideImageCrop), findsNothing);
    });
  }

  testWidgets(
    'A saved banner shows its preview until a draft replaces or clears it',
    (tester) async {
      final port = WideEditorPort();
      _access(port);
      final saved = base64Decode(FormPort.image.split(',').last);
      await open(tester, port, bannerBytes: saved);
      final current = find.byKey(const ValueKey('profile-wide-banner-current'));
      expect(current, findsOneWidget);
      expect(
        ((tester.widget<Image>(current).image as ResizeImage).imageProvider
                as MemoryImage)
            .bytes,
        saved,
      );
      // The unset background keeps its placeholder.
      expect(
        find.byKey(const ValueKey('profile-wide-background-current')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('profile-wide-background-draft')),
        findsNothing,
      );
      // A new draft takes over the preview.
      await tester.ensureVisible(
        find.byKey(const ValueKey('profile-pick-banner')),
      );
      await tester.tap(find.byKey(const ValueKey('profile-pick-banner')));
      await settleCommunityImages(tester);
      await tester.tap(find.byKey(const Key('community-wide-crop-apply')));
      await settleCommunityImages(tester);
      expect(
        find.byKey(const ValueKey('profile-wide-banner-draft')),
        findsOneWidget,
      );
      expect(current, findsNothing);
      // Removing a saved banner drops any draft and shows the placeholder.
      await tester.tap(find.byKey(const ValueKey('profile-remove-banner')));
      await settleCommunityImages(tester);
      expect(current, findsNothing);
      expect(
        find.byKey(const ValueKey('profile-wide-banner-draft')),
        findsNothing,
      );
    },
  );

  testWidgets('The section title and its hint never overlap', (tester) async {
    final port = WideEditorPort();
    _access(port);
    await open(tester, port, width: 760);
    final title = tester.getRect(find.text(text(tester, 'wideImages')));
    final hint = tester.getRect(
      find.byKey(const ValueKey('profile-wide-hint')),
    );
    expect(hint.top, greaterThanOrEqualTo(title.bottom));
  });
}
