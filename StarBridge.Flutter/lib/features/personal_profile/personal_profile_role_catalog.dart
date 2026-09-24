import 'personal_profile_models.dart';

/// Stable role IDs retained from the old profile catalog; display only.
abstract final class PersonalProfileRoleCatalog {
  static const categories = <String, PersonalProfileTagCategory>{
    'fleet-command': PersonalProfileTagCategory.command,
    'squad-command': PersonalProfileTagCategory.command,
    'action-coordination': PersonalProfileTagCategory.command,
    'navigator': PersonalProfileTagCategory.command,
    'pilot': PersonalProfileTagCategory.ship,
    'copilot': PersonalProfileTagCategory.ship,
    'gunner': PersonalProfileTagCategory.ship,
    'ship-engineer': PersonalProfileTagCategory.ship,
    'remote-weapon-operator': PersonalProfileTagCategory.ship,
    'fighter-pilot': PersonalProfileTagCategory.airCombat,
    'interceptor-pilot': PersonalProfileTagCategory.airCombat,
    'bomber-pilot': PersonalProfileTagCategory.airCombat,
    'carrier-pilot': PersonalProfileTagCategory.airCombat,
    'assault-trooper': PersonalProfileTagCategory.groundCombat,
    'sniper': PersonalProfileTagCategory.groundCombat,
    'heavy-gunner': PersonalProfileTagCategory.groundCombat,
    'boarding-specialist': PersonalProfileTagCategory.groundCombat,
    'vehicle-driver': PersonalProfileTagCategory.groundCombat,
    'scout': PersonalProfileTagCategory.recon,
    'route-planner': PersonalProfileTagCategory.recon,
    'scanner-operator': PersonalProfileTagCategory.recon,
    'intel-observer': PersonalProfileTagCategory.recon,
    'mining-operator': PersonalProfileTagCategory.industry,
    'salvage-operator': PersonalProfileTagCategory.industry,
    'cargo-specialist': PersonalProfileTagCategory.industry,
    'trader': PersonalProfileTagCategory.industry,
    'resource-processor': PersonalProfileTagCategory.industry,
    'medic': PersonalProfileTagCategory.medical,
    'search-and-rescue': PersonalProfileTagCategory.medical,
    'casualty-transport': PersonalProfileTagCategory.medical,
    'field-medic': PersonalProfileTagCategory.medical,
    'supply-specialist': PersonalProfileTagCategory.logistics,
    'maintenance-engineer': PersonalProfileTagCategory.logistics,
    'ship-dispatcher': PersonalProfileTagCategory.logistics,
    'transport-driver': PersonalProfileTagCategory.logistics,
  };

  static PersonalProfileTagValue? resolve(String value) {
    final id = value.trim().toLowerCase();
    final category = categories[id];
    if (category == null) return null;
    return PersonalProfileTagValue(
      labelKey: 'profile.legacyRole.$id',
      category: category,
    );
  }
}
