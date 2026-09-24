import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/composition/app_composition.dart';
import 'package:starbridge_flutter/app/feature_registry.dart';
import 'package:starbridge_flutter/platform/window/in_memory_window_chrome.dart';

void main() {
  const builder = _emptyBuilder;

  test('registry rejects duplicate routes', () {
    expect(
      () => FeatureRegistry([
        _feature(
          id: 'home',
          route: '/',
          region: NavigationRegion.brand,
          builder: builder,
        ),
        _feature(
          id: 'other',
          route: '/',
          region: NavigationRegion.primary,
          builder: builder,
        ),
      ]),
      throwsStateError,
    );
  });

  test('registry requires exactly one brand home destination', () {
    expect(
      () => FeatureRegistry([
        _feature(
          id: 'one',
          route: '/one',
          region: NavigationRegion.primary,
          builder: builder,
        ),
      ]),
      throwsStateError,
    );
  });

  test('registry orders navigation without a shell switch', () {
    final registry = FeatureRegistry([
      _feature(
        id: 'home',
        route: '/',
        region: NavigationRegion.brand,
        builder: builder,
      ),
      _feature(
        id: 'later',
        route: '/later',
        region: NavigationRegion.primary,
        order: 20,
        builder: builder,
      ),
      _feature(
        id: 'earlier',
        route: '/earlier',
        region: NavigationRegion.primary,
        order: 10,
        builder: builder,
      ),
    ]);
    expect(registry.inRegion(NavigationRegion.primary).map((item) => item.id), [
      'earlier',
      'later',
    ]);
  });

  test('production primary navigation order is product-locked', () {
    final production = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    expect(
      production.features
          .inRegion(NavigationRegion.primary)
          .map((item) => item.id),
      [
        'official-fleet',
        'operations',
        'party-rooms',
        'marketplace',
        'communities',
      ],
    );
  });

  test('production personal navigation keeps tools before settings', () {
    final production = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );

    expect(
      production.features
          .inRegion(NavigationRegion.personal)
          .map((item) => item.id),
      ['hangar', 'overlay-settings', 'tools', 'settings'],
    );
  });

  test('account menu contains profile and account settings but not hangar', () {
    final production = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );

    expect(
      production.features
          .inRegion(NavigationRegion.accountMenu)
          .map((item) => item.id),
      ['personal-profile', 'account-and-identity'],
    );
    expect(
      production.features
          .inRegion(NavigationRegion.accountMenu)
          .map((item) => item.id),
      isNot(contains('hangar')),
    );
  });

  test('review and test compositions resolve the same feature set', () {
    final review = AppComposition.forShellReview(
      windowChrome: InMemoryWindowChrome(),
    );
    final test = AppComposition.forTest(windowChrome: InMemoryWindowChrome());

    expect(
      test.features.all.map((feature) => feature.id),
      review.features.all.map((feature) => feature.id),
    );
  });
}

Widget _emptyBuilder(BuildContext context) => const SizedBox.shrink();

FeatureDescriptor _feature({
  required String id,
  required String route,
  required NavigationRegion region,
  required DestinationBuilder builder,
  int order = 0,
}) {
  return FeatureDescriptor(
    id: id,
    route: route,
    labelKey: '$id.label',
    descriptionKey: '$id.description',
    icon: StarBridgeIconSemantic.home,
    navigationRegion: region,
    order: order,
    buildDestination: builder,
  );
}
