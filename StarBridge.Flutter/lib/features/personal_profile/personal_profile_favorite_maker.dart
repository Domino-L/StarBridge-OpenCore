import 'package:flutter/material.dart';

import '../hangar/local_hangar_manufacturers.dart';
import '../hangar/local_hangar_wall_card.dart';

/// The hangar wall's maker mark on the leading favourite's picture
/// (2026-11-05). A maker without a bundled logo shows nothing: no
/// placeholder, no text stand-in.
abstract final class ProfileFavoriteMaker {
  /// The maker whose light (on-art) logo is in the bundle, otherwise null.
  static LocalHangarManufacturer? shown(String manufacturer) {
    final maker = LocalHangarManufacturers.find(manufacturer);
    return maker != null &&
            LocalHangarMakerLogos.instance.has(maker, dark: true)
        ? maker
        : null;
  }

  /// Loads the bundle's logo list once, then rebuilds [state] if mounted.
  static void load(State state, VoidCallback rebuild) {
    LocalHangarMakerLogos.instance.ensureLoaded().then((_) {
      if (state.mounted) rebuild();
    });
  }
}

/// The mark at the bottom-right of the large card (user 11-05: "大图厂商放右下角");
/// empty when not [shown].
class ProfileFavoriteMakerMark extends StatelessWidget {
  const ProfileFavoriteMakerMark({
    required this.manufacturer,
    required this.runtimeId,
    super.key,
  });

  final String manufacturer;
  final String runtimeId;

  @override
  Widget build(BuildContext context) {
    final maker = ProfileFavoriteMaker.shown(manufacturer);
    if (maker == null) return const SizedBox.shrink();
    return Padding(
      key: Key('profile-favorite-maker-$runtimeId'),
      padding: const EdgeInsetsDirectional.only(start: 16, bottom: 2),
      child: LocalHangarMakerMark(
        maker: maker,
        height: 42,
        maxWidth: 210,
        onArt: true,
      ),
    );
  }
}

/// The Fan Kit notice next to the showcase whenever its mark shows.
class ProfileFavoriteMakerNotice extends StatelessWidget {
  const ProfileFavoriteMakerNotice({
    required this.manufacturer,
    required this.gap,
    super.key,
  });

  final String manufacturer;
  final double gap;

  @override
  Widget build(BuildContext context) =>
      ProfileFavoriteMaker.shown(manufacturer) == null
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsetsDirectional.only(end: gap, bottom: gap),
          child: const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: LocalHangarNotice(
              key: Key('profile-favorite-fankit-notice'),
            ),
          ),
        );
}
