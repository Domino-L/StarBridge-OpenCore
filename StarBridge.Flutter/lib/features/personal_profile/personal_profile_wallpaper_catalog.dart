import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum PersonalProfileWallpaperAttribution { none, cigFankit }

@immutable
final class PersonalProfileWallpaperPreset {
  const PersonalProfileWallpaperPreset({
    required this.id,
    required this.labelKey,
    this.assetPath,
    this.attribution = PersonalProfileWallpaperAttribution.none,
    this.focalAlignment = Alignment.center,
  });

  final String id;
  final String labelKey;
  final String? assetPath;
  final PersonalProfileWallpaperAttribution attribution;
  final AlignmentGeometry focalAlignment;

  bool get hasImage => assetPath != null;
  // Presentation only: saved IDs and assets do not change when labels change.
  String get displayNumber =>
      (PersonalProfileWallpaperCatalog.presets
                  .where((preset) => preset.hasImage)
                  .toList()
                  .indexWhere((preset) => preset.id == id) +
              1)
          .toString()
          .padLeft(2, '0');
  bool get requiresCigFankitNotice =>
      attribution == PersonalProfileWallpaperAttribution.cigFankit;
}

abstract final class PersonalProfileWallpaperCatalog {
  static const noneId = 'none';
  static const defaultId = noneId;

  static const presets = <PersonalProfileWallpaperPreset>[
    PersonalProfileWallpaperPreset(
      id: noneId,
      labelKey: 'profile.background.none',
    ),
    PersonalProfileWallpaperPreset(
      id: 'formation-flight',
      labelKey: 'profile.background.formationFlight',
      assetPath: 'assets/profile-wallpapers/formation-flight.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    ..._numberedPresets,
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-corridor',
      labelKey: 'profile.background.interiorCorridor',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-corridor.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-grd-brt',
      labelKey: 'profile.background.interiorGrdBrt',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-grd-brt.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-habs',
      labelKey: 'profile.background.interiorHabs',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-habs.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-memorial',
      labelKey: 'profile.background.interiorMemorial',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-memorial.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-refiner',
      labelKey: 'profile.background.interiorRefinery',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-refiner.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-qhd-interior-shops',
      labelKey: 'profile.background.interiorShops',
      assetPath: 'assets/profile-wallpapers/sc-qhd-interior-shops.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-4k-exterior-1',
      labelKey: 'profile.background.exterior01',
      assetPath: 'assets/profile-wallpapers/sc-4k-exterior-1.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-4k-exterior-2',
      labelKey: 'profile.background.exterior02',
      assetPath: 'assets/profile-wallpapers/sc-4k-exterior-2.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-4k-exterior-3',
      labelKey: 'profile.background.exterior03',
      assetPath: 'assets/profile-wallpapers/sc-4k-exterior-3.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'star-citizen-4-0-04',
      labelKey: 'profile.background.starCitizen40',
      assetPath: 'assets/profile-wallpapers/star-citizen-4-0-04.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
  ];

  static const _numberedPresets = <PersonalProfileWallpaperPreset>[
    PersonalProfileWallpaperPreset(
      id: 'sc-02',
      labelKey: 'profile.background.sc02',
      assetPath: 'assets/profile-wallpapers/sc-02.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-03',
      labelKey: 'profile.background.sc03',
      assetPath: 'assets/profile-wallpapers/sc-03.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-04',
      labelKey: 'profile.background.sc04',
      assetPath: 'assets/profile-wallpapers/sc-04.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-05',
      labelKey: 'profile.background.sc05',
      assetPath: 'assets/profile-wallpapers/sc-05.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-06',
      labelKey: 'profile.background.sc06',
      assetPath: 'assets/profile-wallpapers/sc-06.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-07',
      labelKey: 'profile.background.sc07',
      assetPath: 'assets/profile-wallpapers/sc-07.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-08',
      labelKey: 'profile.background.sc08',
      assetPath: 'assets/profile-wallpapers/sc-08.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-09',
      labelKey: 'profile.background.sc09',
      assetPath: 'assets/profile-wallpapers/sc-09.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-11',
      labelKey: 'profile.background.sc11',
      assetPath: 'assets/profile-wallpapers/sc-11.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-13',
      labelKey: 'profile.background.sc13',
      assetPath: 'assets/profile-wallpapers/sc-13.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-14',
      labelKey: 'profile.background.sc14',
      assetPath: 'assets/profile-wallpapers/sc-14.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-15',
      labelKey: 'profile.background.sc15',
      assetPath: 'assets/profile-wallpapers/sc-15.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-16',
      labelKey: 'profile.background.sc16',
      assetPath: 'assets/profile-wallpapers/sc-16.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-18',
      labelKey: 'profile.background.sc18',
      assetPath: 'assets/profile-wallpapers/sc-18.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-19',
      labelKey: 'profile.background.sc19',
      assetPath: 'assets/profile-wallpapers/sc-19.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-20',
      labelKey: 'profile.background.sc20',
      assetPath: 'assets/profile-wallpapers/sc-20.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-21',
      labelKey: 'profile.background.sc21',
      assetPath: 'assets/profile-wallpapers/sc-21.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-22',
      labelKey: 'profile.background.sc22',
      assetPath: 'assets/profile-wallpapers/sc-22.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-23',
      labelKey: 'profile.background.sc23',
      assetPath: 'assets/profile-wallpapers/sc-23.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-25',
      labelKey: 'profile.background.sc25',
      assetPath: 'assets/profile-wallpapers/sc-25.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-26',
      labelKey: 'profile.background.sc26',
      assetPath: 'assets/profile-wallpapers/sc-26.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-27',
      labelKey: 'profile.background.sc27',
      assetPath: 'assets/profile-wallpapers/sc-27.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-28',
      labelKey: 'profile.background.sc28',
      assetPath: 'assets/profile-wallpapers/sc-28.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-29',
      labelKey: 'profile.background.sc29',
      assetPath: 'assets/profile-wallpapers/sc-29.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-30',
      labelKey: 'profile.background.sc30',
      assetPath: 'assets/profile-wallpapers/sc-30.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-31',
      labelKey: 'profile.background.sc31',
      assetPath: 'assets/profile-wallpapers/sc-31.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-33',
      labelKey: 'profile.background.sc33',
      assetPath: 'assets/profile-wallpapers/sc-33.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-34',
      labelKey: 'profile.background.sc34',
      assetPath: 'assets/profile-wallpapers/sc-34.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-35',
      labelKey: 'profile.background.sc35',
      assetPath: 'assets/profile-wallpapers/sc-35.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-36',
      labelKey: 'profile.background.sc36',
      assetPath: 'assets/profile-wallpapers/sc-36.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-37',
      labelKey: 'profile.background.sc37',
      assetPath: 'assets/profile-wallpapers/sc-37.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
    PersonalProfileWallpaperPreset(
      id: 'sc-38',
      labelKey: 'profile.background.sc38',
      assetPath: 'assets/profile-wallpapers/sc-38.jpg',
      attribution: PersonalProfileWallpaperAttribution.cigFankit,
    ),
  ];

  static PersonalProfileWallpaperPreset resolve(String id) {
    return presets.firstWhere(
      (preset) => preset.id == id,
      orElse: () => presets.first,
    );
  }

  static bool contains(String id) => presets.any((preset) => preset.id == id);
}
