// Facts only: the six blueprint category keys and their subcategory values
// accepted by the SCM blueprint API, as listed on the SCM website (snapshot
// 2026-11-08). The SCM API has no category list. No SCM code is copied here;
// labels are our own. Never infer categories from a result page.
import '../../app/localization/app_strings.dart';

const catalogBlueprintCategories = [
  'FPSWeapons',
  'FPSArmours',
  'Ammo',
  'ShipWeapons',
  'Components',
  'MissionItems',
];
const catalogBlueprintSubcategories = <String, List<String>>{
  'FPSWeapons': ['sniper', 'rifle', 'pistol', 'shotgun', 'smg', 'lmg'],
  'FPSArmours': ['helmet', 'core', 'arms', 'legs'],
  'Ammo': ['ballistic', 'energy'],
  'ShipWeapons': ['ballistic', 'laser', 'distortion'],
  'Components': [
    'cooler',
    'powerplant',
    'shield',
    'quantumdrive',
    'radar',
    'mininglaser',
    'tractorbeam',
    'refuelling',
    'salvage',
  ],
};

String catalogItemClass(AppStrings strings, String value) {
  final key = 'catalog.class.$value';
  final label = strings.text(key);
  return label == key ? value : label;
}

String catalogSubcategory(AppStrings strings, Object? category, Object? value) {
  if (value == null || value.toString().trim().isEmpty) return '';
  final key = 'catalog.sub.$category.$value';
  final label = strings.text(key);
  return label == key ? value.toString() : label;
}
