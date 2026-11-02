import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/tokens/color_tokens.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_details.dart';
import 'package:starbridge_flutter/features/marketplace/marketplace_widgets.dart';

import 'marketplace_slice4_test.dart' show preview;

void main() {
  test('checklist orders use the SCM crate, single items keep their photo', () {
    expect(
      marketThumbnail({'displayType': 2, 'thumbnailUrl': 'https://img.invalid/a.png'}),
      marketChecklistArt,
    );
    expect(
      marketThumbnail({'displayType': 1, 'thumbnailUrl': 'https://img.invalid/a.png'}),
      'https://img.invalid/a.png',
    );
    expect(
      marketThumbnail(marketOwnListingCard({'id': 'O1', 'side': 'sell', 'checklist': true})),
      marketChecklistArt,
    );
    expect(
      marketThumbnail(marketOwnListingCard({'id': 'O2', 'side': 'barter', 'checklist': true})),
      isNot(marketChecklistArt),
    );
  });

  testWidgets('crate art renders from the bundled asset', (tester) async {
    await tester.pumpWidget(
      preview(const SizedBox.square(dimension: 120, child: MarketArt(marketChecklistArt)), AppearanceMode.dark),
    );
    await tester.pump(); // localizations load before the first real frame
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect((image.image as AssetImage).assetName, 'assets/brand/scm_market_crate.png');
  });
}
