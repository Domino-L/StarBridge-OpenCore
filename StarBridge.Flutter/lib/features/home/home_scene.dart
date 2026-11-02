import 'dart:math';

/// One backdrop owns its video, still fallback and caption together.
class HomeScene {
  const HomeScene({
    required this.id,
    required this.videoAsset,
    required this.posterAsset,
    required this.locationKey,
  });

  final String id;
  final String videoAsset;
  final String posterAsset;
  final String locationKey;
}

abstract final class HomeScenes {
  static const orisonNight = HomeScene(
    id: 'orison-night',
    videoAsset: 'assets/home-scenes/orison-night-loop-v1.mp4',
    posterAsset: 'assets/home-scenes/orison-night-poster-v1.jpg',
    locationKey: 'home.scene.location',
  );
  static const area18Dusk = HomeScene(
    id: 'area18-dusk',
    videoAsset: 'assets/home-scenes/area18-dusk-loop-v1.mp4',
    posterAsset: 'assets/home-scenes/area18-dusk-poster-v1.jpg',
    locationKey: 'home.scene.area18',
  );
  static const lorvilleSkyline = HomeScene(
    id: 'lorville-skyline',
    videoAsset: 'assets/home-scenes/lorville-skyline-loop-v1.mp4',
    posterAsset: 'assets/home-scenes/lorville-skyline-poster-v1.jpg',
    locationKey: 'home.scene.lorville',
  );
  static const lorvillePort = HomeScene(
    id: 'lorville-port',
    videoAsset: 'assets/home-scenes/lorville-port-loop-v1.mp4',
    posterAsset: 'assets/home-scenes/lorville-port-poster-v1.jpg',
    locationKey: 'home.scene.lorville',
  );
  static const values = [
    orisonNight,
    area18Dusk,
    lorvilleSkyline,
    lorvillePort,
  ];

  /// Lazily choose once per application isolate, never on a page rebuild,
  /// account refresh or return to Home. Only the selected video is initialized.
  static final forLaunch = choose();

  static HomeScene choose([Random? random]) =>
      values[(random ?? Random()).nextInt(values.length)];
}
