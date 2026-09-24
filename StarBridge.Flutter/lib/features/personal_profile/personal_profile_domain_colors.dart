import '../../design_system/tokens/color_tokens.dart';
import 'personal_profile_models.dart';

extension PersonalProfileTagCategoryPresentation on PersonalProfileTagCategory {
  DomainColorRole get domainColorRole => switch (this) {
    PersonalProfileTagCategory.command => DomainColorRole.command,
    PersonalProfileTagCategory.ship => DomainColorRole.ship,
    PersonalProfileTagCategory.airCombat => DomainColorRole.airCombat,
    PersonalProfileTagCategory.groundCombat => DomainColorRole.groundCombat,
    PersonalProfileTagCategory.recon => DomainColorRole.recon,
    PersonalProfileTagCategory.industry => DomainColorRole.industry,
    PersonalProfileTagCategory.medical => DomainColorRole.medical,
    PersonalProfileTagCategory.logistics => DomainColorRole.logistics,
  };
}
